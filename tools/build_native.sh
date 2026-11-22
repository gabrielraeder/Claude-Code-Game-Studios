#!/usr/bin/env bash
# One command per clone for the native simulation core (ADR-0007 sections 6 to 8, story 066).
#
#   tools/build_native.sh            build debug, release and bench DLLs (venv, godot-cpp, API dump, vcvars64, scons)
#   tools/build_native.sh --check    stale-DLL guard: recompute SH and FH, compare with each DLL's marker and build_hash.txt
#   tools/build_native.sh --hashes   print SH and the three FH values
#   tools/build_native.sh --bench    swap the bench DLL over the debug name and write bench.lock (refuses while Godot runs)
#   tools/build_native.sh --restore  copy the backed-up debug DLL back and remove bench.lock (never rebuilds)
#   tools/build_native.sh --scan-flags FILE   scan compiler command lines for forbidden flags (used by the build and its negative run)
#   tools/build_native.sh --probe-godot       list the open Godot processes (PROBE_FAILED when it cannot tell)
#
# Exit 0 on success, 1 on a failed check or build, 2 on bad usage or an unmet precondition.
# Env: GODOT (console exe), PYTHON, VSROOT (MSVC Build Tools), POWERSHELL (default powershell.exe),
#      COLD_TIMEOUT (seconds per variant build, default 900), PIP_TIMEOUT (300), FETCH_TIMEOUT (120), DUMP_TIMEOUT (120),
#      DOG_LOGDIR (build logs, default native/obj/logs), JOBS (scons jobs, default nproc),
#      HASH_LIST (file-list definition, default native/hash_files.txt; tests point it at a fixture).
# Timeouts: a command that runs past its limit is stopped with `taskkill /T /F` on the Windows pid of the command
# THIS script started, which ends that command's whole process tree (cmd, scons, cl). It never touches any other process.
set -u -o pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
GODOT="${GODOT:-C:/Godot/Godot_v4.8-beta3_win64_console.exe}"
PYTHON="${PYTHON:-C:/Python314/python}"
VSROOT="${VSROOT:-C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools}"
PS="${POWERSHELL:-powershell.exe}"
COLD_TIMEOUT="${COLD_TIMEOUT:-900}"
PIP_TIMEOUT="${PIP_TIMEOUT:-300}"
FETCH_TIMEOUT="${FETCH_TIMEOUT:-120}"
DUMP_TIMEOUT="${DUMP_TIMEOUT:-120}"
LOGDIR="${DOG_LOGDIR:-$ROOT/native/obj/logs}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 8)}"
SCONS_VERSION="4.11.1"
BIN="addons/dogworks_core/bin"
LIST="${HASH_LIST:-native/hash_files.txt}"
VARIANTS="debug release bench"

dll_name() {  # variant -> file name
	case "$1" in
		debug) echo "dogworks_core.windows.template_debug.x86_64.dll" ;;
		release) echo "dogworks_core.windows.template_release.x86_64.dll" ;;
		bench) echo "dogworks_core.windows.bench.x86_64.dll" ;;
	esac
}

# run_limited SECONDS LOGFILE CMD... : runs CMD with its output in LOGFILE; past SECONDS the whole process
# tree of CMD is stopped (taskkill /T /F on its Windows pid) and 124 is returned.
run_limited() {
	local limit="$1" log="$2" pid wpid start
	shift 2
	"$@" > "$log" 2>&1 &
	pid=$!
	wpid="$(cat "/proc/$pid/winpid" 2>/dev/null || echo "$pid")"
	start=$SECONDS
	while kill -0 "$pid" 2>/dev/null; do
		if [ $((SECONDS - start)) -ge "$limit" ]; then
			echo "TIMEOUT after ${limit}s: stopping the process tree of pid $wpid (started by this script)" | tee -a "$log" >&2
			taskkill //PID "$wpid" //T //F >/dev/null 2>&1
			wait "$pid" 2>/dev/null
			return 124
		fi
		sleep 1
	done
	wait "$pid"
}

# Sorted, de-duplicated list of the hashed files (byte order) from the committed list definition.
# FAILS (return 1, message on stderr) on: a missing list, an unknown line kind, a listed file that is missing,
# a tree that is missing or holds no files. Files and directories whose name starts with '.' are left out of a
# tree (addons/dogworks_core/source_hash.gd does the same).
hash_files() {
	[ -f "$LIST" ] || { echo "hash_files: missing $LIST" >&2; return 1; }
	local line kind path rest found out="" n=0
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%$'\r'}"
		line="${line#"${line%%[![:space:]]*}"}"
		case "$line" in ''|'#'*) continue ;; esac
		read -r kind path rest <<< "$line"
		if [ -z "${path:-}" ] || [ -n "${rest:-}" ]; then
			echo "hash_files: malformed line in $LIST: '$line' (expected 'file <path>' or 'tree <dir>')" >&2; return 1
		fi
		path="${path%/}"
		case "$kind" in
			file)
				[ -f "$path" ] || { echo "hash_files: listed file is missing: $path" >&2; return 1; }
				out+="$path"$'\n' ;;
			tree)
				[ -d "$path" ] || { echo "hash_files: listed tree is missing: $path" >&2; return 1; }
				found="$(find "$path" -type f | awk -v base="$path/" 'index($0, base) == 1 { rel = substr($0, length(base) + 1); if (rel ~ /(^|\/)\./) next } { print }')" \
					|| { echo "hash_files: find failed on $path" >&2; return 1; }
				[ -n "$found" ] || { echo "hash_files: tree holds no files: $path" >&2; return 1; }
				out+="$found"$'\n' ;;
			*)
				echo "hash_files: unknown line kind '$kind' in $LIST: '$line'" >&2; return 1 ;;
		esac
		n=$((n + 1))
	done < "$LIST"
	[ $n -gt 0 ] || { echo "hash_files: $LIST lists nothing" >&2; return 1; }
	printf '%s' "$out" | sort -u
}

# SH: sha256 over "path NUL sha256hex LF" for every hashed file. Returns 1 when the list or a file is bad.
source_hash() {
	local files f h tmp
	files="$(hash_files)" || return 1
	tmp="$(mktemp "${TMPDIR:-/tmp}/dogworks_sh.XXXXXX")" || return 1
	while IFS= read -r f; do
		h="$(sha256sum "$f" | cut -d' ' -f1)"
		if [ "${#h}" != 64 ]; then echo "source_hash: could not hash $f" >&2; rm -f "$tmp"; return 1; fi
		printf '%s\0%s\n' "$f" "$h" >> "$tmp"
	done <<< "$files"
	sha256sum < "$tmp" | cut -d' ' -f1
	rm -f "$tmp"
}

msvc_version() { ls -1 "$VSROOT/VC/Tools/MSVC" 2>/dev/null | sort -V | tail -1; }
api_hash() { sha256sum native/api/extension_api.json 2>/dev/null | cut -d' ' -f1; }

# FH: sha256 over SH, the API dump hash, the MSVC version string and the target.
full_hash() {  # sh target
	printf '%s\n%s\n%s\n%s' "$1" "$(api_hash)" "$(msvc_version)" "$2" | sha256sum | cut -d' ' -f1
}

ensure_gdignore() {
	local d
	for d in native native/godot-cpp native/.venv native/obj native/api; do
		mkdir -p "$d" && : > "$d/.gdignore"
	done
}

# The godot-cpp tree must be exactly the pinned commit and unmodified.
ensure_godotcpp() {
	local want have dirty
	want="$(tr -d '\r\n ' < native/GODOT_CPP_COMMIT)"
	have="$(git -C native/godot-cpp rev-parse HEAD 2>/dev/null || true)"
	if [ "$have" != "$want" ]; then
		echo "fetching godot-cpp $want"
		mkdir -p native/godot-cpp "$LOGDIR"
		git -C native/godot-cpp init -q || return 1
		git -C native/godot-cpp remote remove origin >/dev/null 2>&1
		git -C native/godot-cpp remote add origin https://github.com/godotengine/godot-cpp.git || return 1
		run_limited "$FETCH_TIMEOUT" "$LOGDIR/git-fetch.log" git -C native/godot-cpp fetch -q --depth 1 origin "$want" || { echo "git fetch failed or timed out (see $LOGDIR/git-fetch.log)" >&2; return 1; }
		git -C native/godot-cpp checkout -q -f FETCH_HEAD || return 1
		have="$(git -C native/godot-cpp rev-parse HEAD)"
		[ "$have" = "$want" ] || { echo "godot-cpp is at $have, expected $want" >&2; return 1; }
	fi
	dirty="$(git -C native/godot-cpp status --porcelain --untracked-files=no)"
	if [ -n "$dirty" ]; then
		echo "native/godot-cpp has local modifications; refusing to build on a modified tree:" >&2
		echo "$dirty" | head -5 >&2
		return 1
	fi
}

# The venv must hold exactly SCons $SCONS_VERSION.
ensure_venv() {
	local have
	mkdir -p "$LOGDIR"
	if [ ! -x native/.venv/Scripts/scons.exe ]; then
		echo "creating native/.venv"
		"$PYTHON" -m venv native/.venv || return 1
	fi
	have="$(native/.venv/Scripts/scons.exe --version 2>/dev/null | grep -oE 'SCons: v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/SCons: v//')"
	if [ "$have" != "$SCONS_VERSION" ]; then
		echo "installing SCons $SCONS_VERSION into native/.venv (found '${have:-none}')"
		run_limited "$PIP_TIMEOUT" "$LOGDIR/pip.log" native/.venv/Scripts/python -m pip install -q "scons==$SCONS_VERSION" || { echo "pip install failed or timed out (see $LOGDIR/pip.log)" >&2; return 1; }
		have="$(native/.venv/Scripts/scons.exe --version 2>/dev/null | grep -oE 'SCons: v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/SCons: v//')"
		[ "$have" = "$SCONS_VERSION" ] || { echo "SCons is '$have', expected $SCONS_VERSION" >&2; return 1; }
	fi
}

ensure_api() {
	local ver
	mkdir -p "$LOGDIR"
	ver="$("$GODOT" --version 2>/dev/null | tr -d '\r\n')"
	if [ -f native/api/extension_api.json ] && [ "$(cat native/api/godot_version.txt 2>/dev/null)" = "$ver" ]; then
		return 0
	fi
	echo "dumping the extension API from $ver"
	(cd native/api && run_limited "$DUMP_TIMEOUT" "$LOGDIR/api-dump.log" "$GODOT" --headless --dump-extension-api --dump-gdextension-interface --dump-gdextension-interface-json) \
		|| { echo "API dump failed or timed out (see $LOGDIR/api-dump.log)" >&2; return 1; }
	[ -f native/api/extension_api.json ] || return 1
	printf '%s' "$ver" > native/api/godot_version.txt
}

# ps_run SCRIPT : runs a PowerShell script and prints its output. When PowerShell is missing or fails, prints a
# line starting PROBE_FAILED instead of an empty (and so "nobody holds it") answer.
ps_run() {
	local out rc
	if ! command -v "$PS" >/dev/null 2>&1; then
		echo "PROBE_FAILED $PS not found"
		return 0
	fi
	out="$(BINWIN="$(cygpath -w "$ROOT/$BIN")" "$PS" -NoProfile -Command "$1" 2>&1)"
	rc=$?
	out="$(printf '%s' "$out" | tr -d '\r')"
	[ $rc -eq 0 ] || out="$out"$'\n'"PROBE_FAILED $PS exit $rc"
	printf '%s\n' "$out" | grep -v '^$'
	return 0
}

# Names the Godot process(es) that hold one of our DLLs (a loaded original DLL, not the editor's ~ copy).
# Prints PROBE_FAILED when it cannot tell (PowerShell missing, or a process's modules cannot be read).
dll_holders() {
	ps_run '
		$ErrorActionPreference = "Stop"
		try {
			if ($env:DOG_FORCE_PROBE_THROW) { throw "forced failure (DOG_FORCE_PROBE_THROW)" }
			Get-Process -Name "Godot*" -ErrorAction SilentlyContinue | ForEach-Object {
				$p = $_
				try {
					foreach ($m in $p.Modules) {
						$leaf = Split-Path $m.FileName -Leaf
						if ($m.FileName -like ($env:BINWIN + "\*") -and $leaf -like "dogworks_core.*" -and $leaf -notlike "~*") {
							Write-Output ("pid {0} {1} holds {2}" -f $p.Id, $p.ProcessName, $leaf); break
						}
					}
				} catch { Write-Output ("PROBE_FAILED cannot read the modules of pid {0}: {1}" -f $p.Id, $_.Exception.Message) }
			}
		} catch { Write-Output ("PROBE_FAILED " + $_.Exception.Message) }'
}

godot_processes() {
	ps_run '
		$ErrorActionPreference = "Stop"
		try {
			if ($env:DOG_FORCE_PROBE_THROW) { throw "forced failure (DOG_FORCE_PROBE_THROW)" }
			Get-Process -Name "Godot*" -ErrorAction SilentlyContinue | ForEach-Object { "pid {0} {1}" -f $_.Id, $_.ProcessName }
		} catch { Write-Output ("PROBE_FAILED " + $_.Exception.Message) }'
}

# scan_flags FILE : every line of FILE is a compiler command line. FAIL when one has /fp:fast, /arch:... or /MD(d),
# or lacks /fp:precise or /MT. Prints what it scanned.
scan_flags() {
	local f="$1" n bad missing
	[ -f "$f" ] || { echo "FAIL flag scan: $f is missing"; return 1; }
	n="$(grep -c . "$f")"
	bad="$(grep -nE '(^| )/(fp:fast|arch:[^ ]*|MDd?)( |$)' "$f")"
	if [ -n "$bad" ]; then
		echo "FAIL flag scan: forbidden flag in $f:"
		echo "$bad" | cut -c1-220 | head -5
		return 1
	fi
	missing="$(grep -vE '(^| )/fp:precise( |$)' "$f" | grep -vE '^$' | head -3)"
	if [ -z "$missing" ]; then missing="$(grep -vE '(^| )/MT( |$)' "$f" | grep -vE '^$' | head -3)"; fi
	if [ -n "$missing" ]; then
		echo "FAIL flag scan: a compile line in $f lacks /fp:precise or /MT:"
		echo "$missing" | cut -c1-220
		return 1
	fi
	echo "PASS flag scan: $n compile line(s) scanned in $f, none has /fp:fast, /arch: or /MD, all have /fp:precise and /MT"
}

do_check() {
	local fails=0 sh v dll marker count tgt msh mfh efh line
	sh="$(source_hash)" || { echo "FAIL source hash: the file list or a listed file is bad (see the message above)"; return 1; }
	if [ -z "$(api_hash)" ] || [ -z "$(msvc_version)" ]; then
		echo "FAIL full hash: needs native/api/extension_api.json and MSVC under $VSROOT; run tools/build_native.sh"
		return 1
	fi
	echo "SH $sh"
	if [ -e "$BIN/bench.lock" ]; then
		echo "FAIL bench.lock exists: a bench DLL is swapped in; run tools/build_native.sh --restore"
		fails=$((fails + 1))
	else
		echo "PASS no bench.lock"
	fi
	if [ -d .godot ] && [ ! -f .godot/extension_list.cfg ]; then
		echo "FAIL .godot/ exists without extension_list.cfg: the first --import of that tree exits with a segfault (139) on 4.8-beta3; run tools/build_native.sh"
		fails=$((fails + 1))
	fi
	for v in $VARIANTS; do
		dll="$BIN/$(dll_name "$v")"
		if [ ! -f "$dll" ]; then
			echo "FAIL $v: $dll is missing; run tools/build_native.sh"
			fails=$((fails + 1)); continue
		fi
		marker="$(grep -aoE 'DOGWORKS_BUILD:[a-z]+:[0-9a-f]{64}:[0-9a-f]{64}:END' "$dll")"
		count=$(printf '%s' "$marker" | grep -c . )
		if [ "$count" != 1 ]; then
			echo "FAIL $v: found $count build markers in $dll (need exactly 1)"
			fails=$((fails + 1)); continue
		fi
		tgt="$(echo "$marker" | cut -d: -f2)"; msh="$(echo "$marker" | cut -d: -f3)"; mfh="$(echo "$marker" | cut -d: -f4)"
		if [ "$tgt" != "$v" ]; then
			echo "FAIL $v: marker target is '$tgt' in $dll (expected '$v')$([ "$tgt" = bench ] && echo '; a bench DLL is in the debug slot, run tools/build_native.sh --restore')"
			fails=$((fails + 1)); continue
		fi
		if [ "$msh" != "$sh" ]; then
			echo "FAIL $v: stale DLL, source hash differs (DLL $msh, sources $sh); run tools/build_native.sh"
			fails=$((fails + 1)); continue
		fi
		efh="$(full_hash "$sh" "$v")"
		if [ "$mfh" != "$efh" ]; then
			echo "FAIL $v: full hash differs (DLL $mfh, expected $efh): compiler or API dump changed; run tools/build_native.sh"
			fails=$((fails + 1)); continue
		fi
		line="$(grep -F "$(dll_name "$v") " "$BIN/build_hash.txt" 2>/dev/null)"
		if [ "$line" != "$(dll_name "$v") target=$v sh=$sh fh=$efh" ]; then
			echo "FAIL $v: $BIN/build_hash.txt does not match; run tools/build_native.sh"
			fails=$((fails + 1)); continue
		fi
		echo "PASS $v ($count marker, sh and fh match)"
	done
	if [ $fails -gt 0 ]; then echo "CHECK FAIL ($fails)"; return 1; fi
	echo "CHECK PASS"
}

# Godot segfaults at exit on the first --import of a project whose .godot/extension_list.cfg does not
# exist yet (4.8-beta3, any extension; story 066 evidence). Seeding the list avoids it.
# Remove this when a first --import of a fresh project with an extension exits 0 (re-test at each re-pin).
ensure_extension_list() {
	mkdir -p .godot
	[ -f .godot/extension_list.cfg ] || printf '%s\n' 'res://addons/dogworks_core/dogworks_core.gdextension' > .godot/extension_list.cfg
}

# capture_compile_lines VARIANT LOG : keeps every compile command line of the log, scans them, and replaces the
# saved command line of the variant only when the new one is non-empty.
capture_compile_lines() {
	local v="$1" log="$2" all="$LOGDIR/compile_lines-$v.txt" cmdfile="$LOGDIR/compiler_command_line-$v.txt" rc
	grep -E '^cl /' "$log" > "$all" 2>/dev/null || : > "$all"
	scan_flags "$all" | tee "$LOGDIR/flag_scan-$v.txt"
	rc=${PIPESTATUS[0]}
	grep -m1 'toolchain_probe' "$all" > "$cmdfile.tmp" 2>/dev/null
	if [ -s "$cmdfile.tmp" ]; then mv -f "$cmdfile.tmp" "$cmdfile"; else rm -f "$cmdfile.tmp"; fi
	return "$rc"
}

do_build() {
	local sh v t0 t1 fh dll holders log all0 all1 rc
	ensure_gdignore
	mkdir -p "$LOGDIR" "$BIN"
	if [ -e "$BIN/bench.lock" ]; then echo "refusing to build while $BIN/bench.lock exists; run --restore first" >&2; return 2; fi
	ensure_godotcpp || { echo "godot-cpp setup failed" >&2; return 1; }
	ensure_venv || { echo "venv/SCons setup failed" >&2; return 1; }
	ensure_api || { echo "API dump failed" >&2; return 1; }
	ensure_extension_list
	holders="$(dll_holders)"
	if printf '%s' "$holders" | grep -q PROBE_FAILED; then
		echo "refusing to build: cannot tell whether a Godot process holds the DLL:" >&2
		echo "$holders" >&2
		return 2
	fi
	if [ -n "$holders" ]; then
		echo "refusing to build: a Godot process holds the DLL:" >&2
		echo "$holders" >&2
		return 2
	fi
	sh="$(source_hash)" || return 1
	export DOGWORKS_SH="$sh" JOBS
	all0=$(date +%s)
	for v in $VARIANTS; do
		fh="$(full_hash "$sh" "$v")"
		export DOGWORKS_FH="$fh"
		log="$LOGDIR/build-$v.log"
		t0=$(date +%s)
		echo "building $v (timeout ${COLD_TIMEOUT}s)"
		run_limited "$COLD_TIMEOUT" "$log" cmd //c "tools\\build_native.bat $v"
		rc=$?
		t1=$(date +%s)
		echo "$v rc=$rc seconds=$((t1 - t0))" | tee -a "$LOGDIR/times.txt"
		if [ $rc -ne 0 ]; then echo "build failed for $v (see $log)" >&2; tail -20 "$log" >&2; return 1; fi
		capture_compile_lines "$v" "$log" || { echo "build rejected: forbidden compiler flags for $v" >&2; return 1; }
	done
	# Rename into place only after every link succeeded. A DLL a Godot process holds is never a link target.
	holders="$(dll_holders)"
	if [ -n "$holders" ]; then echo "a Godot process took the DLL during the build, or the probe failed:" >&2; echo "$holders" >&2; return 2; fi
	: > "$BIN/build_hash.txt.new"
	for v in $VARIANTS; do
		dll="$(dll_name "$v")"
		mv -f "native/obj/$v/dist/$dll" "$BIN/$dll" || { echo "could not replace $BIN/$dll" >&2; return 1; }
		[ "$v" = debug ] && cp -f "native/obj/$v/dist/${dll%.dll}.pdb" "$BIN/${dll%.dll}.pdb" 2>/dev/null
		echo "$dll target=$v sh=$sh fh=$(full_hash "$sh" "$v")" >> "$BIN/build_hash.txt.new"
	done
	mv -f "$BIN/build_hash.txt.new" "$BIN/build_hash.txt"
	all1=$(date +%s)
	echo "total seconds=$((all1 - all0))" | tee -a "$LOGDIR/times.txt"
	do_check
}

do_bench() {
	local procs
	if [ -e "$BIN/bench.lock" ]; then echo "refusing: $BIN/bench.lock already exists" >&2; return 2; fi
	procs="$(godot_processes)"
	if [ -n "$procs" ]; then
		if printf '%s' "$procs" | grep -q PROBE_FAILED; then
			echo "refusing --bench: cannot tell whether a Godot process is open:" >&2
		else
			echo "refusing --bench: a Godot process is open (an editor counts):" >&2
		fi
		echo "$procs" >&2
		return 2
	fi
	do_check >/dev/null || { echo "refusing --bench: --check fails; run tools/build_native.sh first" >&2; return 2; }
	mkdir -p "$BIN/backup"
	local d; d="$(dll_name debug)"
	cp -f "$BIN/$d" "$BIN/backup/$d" || return 1
	[ -f "$BIN/${d%.dll}.pdb" ] && cp -f "$BIN/${d%.dll}.pdb" "$BIN/backup/"
	cp -f "$BIN/$(dll_name bench)" "$BIN/$d" || return 1
	date +%Y-%m-%dT%H:%M:%S > "$BIN/bench.lock"
	echo "bench DLL is now in the debug slot; bench.lock written. Restore with tools/build_native.sh --restore"
}

do_restore() {
	local d; d="$(dll_name debug)"
	[ -e "$BIN/bench.lock" ] || { echo "no $BIN/bench.lock; nothing to restore" >&2; return 2; }
	[ -f "$BIN/backup/$d" ] || { echo "no backup at $BIN/backup/$d; run tools/build_native.sh" >&2; return 2; }
	cp -f "$BIN/backup/$d" "$BIN/$d" || { echo "could not copy over $BIN/$d (is a Godot process holding it?)" >&2; return 1; }
	[ -f "$BIN/backup/${d%.dll}.pdb" ] && cp -f "$BIN/backup/${d%.dll}.pdb" "$BIN/"
	rm -f "$BIN/bench.lock"
	echo "debug DLL restored from backup; bench.lock removed"
}

case "${1:-}" in
	"") do_build ;;
	--check) do_check ;;
	--hashes) s="$(source_hash)" || exit 1; echo "SH $s"; for v in $VARIANTS; do echo "FH $v $(full_hash "$s" "$v")"; done ;;
	--bench) do_bench ;;
	--restore) do_restore ;;
	--scan-flags) scan_flags "${2:-}" ;;
	--probe-godot) godot_processes ;;
	*) echo "usage: tools/build_native.sh [--check|--hashes|--bench|--restore|--scan-flags FILE|--probe-godot]" >&2; exit 2 ;;
esac
