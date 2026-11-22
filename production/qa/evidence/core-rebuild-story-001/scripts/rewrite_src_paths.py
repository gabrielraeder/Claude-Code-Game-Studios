#!/usr/bin/env python3
"""Story core-rebuild-001, path commit (ADR-0001 section 9 step 2).

Rewrites every plain res://src/<old> reference to res://src/<new> using move_map.tsv (written
by move_to_legacy.sh), in the files Godot and the tools read: src/, assets/, tools/, tests/,
project.godot and .godot/global_script_class_cache.cfg; file types .tscn .tres .gd .gdshader
.godot .cfg .json .py .sh. uid= values are never touched (only the res:// path text changes).
History (docs/, design/, production/, .claude/) is left as written.
Also rewrites the one plain filesystem path list in tools/gen_castle_circuit.py ("src/track/...").
Prints each changed file and fails (exit 1) if any res://src/ path outside legacy/ or data/ remains.

Usage: python -I rewrite_src_paths.py REPO_ROOT
"""
import os
import re
import sys

EXTS = (".tscn", ".tres", ".gd", ".gdshader", ".godot", ".cfg", ".json", ".py", ".sh")
ROOTS = ("src", "assets", "tools", "tests")
FILES = ("project.godot", os.path.join(".godot", "global_script_class_cache.cfg"))
LEFTOVER = re.compile(r"res://src/(?!legacy/|data/)[^\s\"')\]]+")


def main(root):
    here = os.path.dirname(os.path.abspath(__file__))
    pairs = []
    with open(os.path.join(here, "move_map.tsv"), encoding="utf-8") as f:
        for line in f:
            old, new = line.rstrip("\n").split("\t")
            if not old.endswith(".uid"):
                pairs.append(("res://" + old, "res://" + new))
    pairs.sort(key=lambda p: -len(p[0]))  # longest first: no prefix of one path hits another
    plain = {"\"" + o[len("res://"):]: "\"" + n[len("res://"):] for o, n in pairs}
    targets = [os.path.join(root, f) for f in FILES]
    for top in ROOTS:
        for d, _, names in os.walk(os.path.join(root, top)):
            if "__pycache__" in d or os.sep + "dl-" in d:
                continue
            targets += [os.path.join(d, n) for n in names if n.endswith(EXTS)]
    changed, leftovers = 0, []
    for path in targets:
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", newline="") as f:
            text = f.read()
        new = text
        for o, n in pairs:
            new = re.sub(re.escape(o) + r"(?![\w./])", n, new)
        if path.endswith(os.path.join("tools", "gen_castle_circuit.py")):
            for o, n in plain.items():
                new = re.sub(re.escape(o) + r"(?=\")", n, new)
        if new != text:
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(new)
            changed += 1
            print("rewrote", os.path.relpath(path, root))
        for m in LEFTOVER.finditer(new):
            leftovers.append("%s: %s" % (os.path.relpath(path, root), m.group(0)))
    print("files rewritten: %d" % changed)
    for l in leftovers:
        print("LEFTOVER", l)
    return 1 if leftovers else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
