# Godot Engine — Version Reference

| Field | Value |
|-------|-------|
| **Engine Version** | Godot 4.8-beta3 (pre-release; move to 4.8 stable when released) |
| **Installed at pin time** | 4.8.beta3.official.c51ff06e8 — `C:/Godot/Godot_v4.8-beta3_win64_console.exe --version`, 2026-11-19 (match) |
| **Release Date** | 4.8 beta 3: 2026-11-09 · 4.8 stable: NOT SOURCEABLE — no date stated at https://godotengine.org/article/dev-snapshot-godot-4-8-beta-3/ |
| **Project Pinned** | 2026-11-19 (previously 4.7, 2026-10-17) |
| **Last Docs Verified** | 2026-11-19 (4.7 → 4.8 beta changes, from the godotengine.org 4.8 snapshot articles); 2026-10-21 (Windows driver default and Compositor, against Godot source); 2026-10-17 (release timeline and 4.7 changes); 2026-02-12 (4.4-4.6 content) |
| **LLM Knowledge Cutoff** | May 2025 |

## Knowledge Gap Warning

May 2025 is a floor for every model the studio runs on: a newer model may know more, but check this folder first.

The LLM's training data likely covers Godot up to ~4.3. Versions 4.5, 4.6,
4.7 and 4.8 were released after the cutoff and introduced significant changes that
the model does NOT know about; 4.4 came out shortly before it and may be thinly
covered. Always cross-reference this directory before suggesting Godot API calls.

## Installed-Version Gap Warning

The warning above is one-directional — it covers the **model** knowing less than
this pin. The reverse gap is real and `/setup-engine` §3 creates it deliberately
("pin the newer one and upgrade later"): this reference can sit **ahead of the
installed editor**, and an agent citing it correctly then emits APIs that do not
compile locally. **Check `Installed at pin time` above before trusting a
version-qualified claim** — `NOT DETERMINED` means the gap is unknown, not absent.

## Post-Cutoff Version Timeline

| Version | Release | Risk Level | Key Theme |
|---------|---------|------------|-----------|
| 4.5 | Sep 2025 | HIGH | Accessibility (AccessKit), variadic args, @abstract, shader baker, SMAA |
| 4.6 | Jan 2026 | HIGH | Jolt default, glow rework, IK restored |
| 4.7 | Jun 2026 | HIGH | AreaLight3D, HDR output, Asset Store replaces the Asset Library, VirtualJoystick, Jolt soft-body and world-boundary changes, typed-return overrides |
| 4.8 (beta) | dev1 Jul 6 2026 · feature freeze at dev7 (Sep 29) · beta1 Oct 15 · beta2 Oct 29 · beta3 Nov 9 2026 · stable NOT SOURCEABLE | HIGH | No inheriting own inner classes, strings-as-comments removed, Jolt 5.6.0, non-allocating physics queries, docked game view, contact shadows, texture streaming |

## Before the Cutoff

4.4 (Mar 2025, Jolt option, FileAccess return types) predates the May 2025
cutoff; the Knowledge Gap Warning still applies to it.

Dates from https://github.com/godotengine/godot/releases, checked 2026-10-17:
4.4 Mar 3 2025, 4.5 Sep 15 2025, 4.6 Jan 26 2026, 4.7 Jun 18 2026, 4.7.2 Aug 18
2026. Migration guides and release notes: `breaking-changes.md` § Sources.

4.8 dates from the GitHub release API (`https://api.github.com/repos/godotengine/godot-builds/releases/tags/4.8-<tag>`)
and the snapshot articles (https://godotengine.org/article/dev-snapshot-godot-4-8-dev-7/, https://godotengine.org/article/dev-snapshot-godot-4-8-beta-1/, https://godotengine.org/article/dev-snapshot-godot-4-8-beta-2/, https://godotengine.org/article/dev-snapshot-godot-4-8-beta-3/), checked 2026-11-19.
The official 4.7 → 4.8 migration guide does not exist yet (https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.8.html returned 404 on 2026-11-19);
re-check it when 4.8 reaches RC or stable (`/setup-engine refresh`).
Windows editor: `Godot_v4.8-beta3_win64.exe.zip` from https://github.com/godotengine/godot-builds/releases/tag/4.8-beta3.
