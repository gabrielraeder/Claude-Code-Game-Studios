#!/usr/bin/env python3
"""Checks that the shared data class scripts in src/data/ form a closed set (ADR-0001 section 9).

A src/data/ script may reference engine types and other src/data/ classes only: never a
class_name declared under src/legacy/, and never a res://src/legacy/ path. REGRESSION TOOL.

Usage: python -I tools/check_data_closure.py [REPO_ROOT]
Prints one line per reference found, then CLOSED or OPEN; exit 0 when closed, 1 when open,
2 when the check cannot run: src/data/ or src/legacy/ is missing or has no .gd script, or
src/data/ has fewer than MIN_DATA_SCRIPTS scripts (a wrong root or a lost folder, not a pass).
"""
import os
import re
import sys

CLASS_RE = re.compile(r"^class_name\s+(\w+)", re.M)
# Data scripts the story-001 move produced (data-closure.txt: 15). Fewer means files went
# missing or the root is wrong, so the check refuses to call the set closed.
MIN_DATA_SCRIPTS = 15


def _scripts(folder):
    for d, _, names in os.walk(folder):
        for n in names:
            if n.endswith(".gd"):
                yield os.path.join(d, n)


def _code(text):
    # Drop comments and string contents so a word in a doc line is not a reference.
    out = []
    for line in text.splitlines():
        line = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
        out.append(line.split("#", 1)[0])
    return "\n".join(out)


def main(root):
    legacy = os.path.join(root, "src", "legacy")
    data = os.path.join(root, "src", "data")
    for folder in (data, legacy):
        if not os.path.isdir(folder):
            print("ERROR %s is missing (root %s)" % (folder, root))
            return 2
    legacy_files = sorted(_scripts(legacy))
    if not legacy_files:
        print("ERROR no .gd scripts under %s" % legacy)
        return 2
    data_files = sorted(_scripts(data))
    if len(data_files) < MIN_DATA_SCRIPTS:
        print("ERROR %d data scripts under %s, expected at least %d" % (len(data_files), data, MIN_DATA_SCRIPTS))
        return 2
    legacy_classes = set()
    for p in legacy_files:
        with open(p, encoding="utf-8") as f:
            legacy_classes.update(CLASS_RE.findall(f.read()))
    found = 0
    for p in data_files:
        with open(p, encoding="utf-8") as f:
            text = f.read()
        rel = os.path.relpath(p, root)
        if "res://src/legacy/" in text:
            print("%s: references a res://src/legacy/ path" % rel)
            found += 1
        words = set(re.findall(r"\b[A-Z]\w*\b", _code(text)))
        for c in sorted(words & legacy_classes):
            print("%s: references legacy class %s" % (rel, c))
            found += 1
    print("%s (%d data scripts, %d legacy classes, %d references)" % (
        "CLOSED" if found == 0 else "OPEN", len(data_files), len(legacy_classes), found))
    return 0 if found == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else os.getcwd()))
