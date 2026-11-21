"""Bugfix 2026-11-20: checks that every item box a kart drives through vanishes, on every PC.

Usage: python -I tools/box_log_check.py <dir with *.log>
Per log: boxes taken with an item, boxes broken with no item (item=none), SEEN (a kart drove
through and the box vanished) and PASSED_FREE (a kart drove through and the box stayed up; must
be 0). Across logs: the BOX lines (box, kart, item, host race time) must be identical on every PC.
Needs the --autopilot debug_box_check lines from ItemManager.
"""
import re
import sys
from pathlib import Path

BOX = re.compile(r"^\[item\] t=\S+ BOX (\d+) kart=(\d+) item=(\w+) at=(-?[\d.]+)")
SEEN = re.compile(r"^\[item\] t=\S+ SEEN box=(\d+) kart=(\d+)")
MISS = re.compile(r"^\[item\] t=(\S+) PASSED_FREE box=(\d+) kart=(\d+)")


def main(d):
    sets = {}
    for p in sorted(Path(d).glob("*.log")):
        boxes, seen, miss = [], [], []
        for raw in p.read_text(encoding="utf-8", errors="replace").splitlines():
            if m := BOX.match(raw):
                boxes.append(m.groups())
            elif m := SEEN.match(raw):
                seen.append(m.groups())
            elif m := MISS.match(raw):
                miss.append(m.groups())
        got = [b for b in boxes if b[2] != "none"]
        broke = [b for b in boxes if b[2] == "none"]
        karts = sorted({int(b[1]) for b in boxes})
        errors = sum(1 for raw in p.read_text(encoding="utf-8", errors="replace").splitlines()
                     if "SCRIPT ERROR" in raw or raw.startswith("ERROR"))
        print(f"{p.name}: box_events={len(boxes)} with_item={len(got)} broken_no_item={len(broke)} "
              f"karts={karts} seen={len(seen)} PASSED_FREE={len(miss)} errors={errors}")
        for m in miss[:10]:
            print("   PASSED_FREE t=%s box=%s kart=%s" % m)
        sets[p.name] = sorted(boxes)
    names = list(sets)
    if len(names) > 1:
        same = all(sets[n] == sets[names[0]] for n in names)
        print("cross-PC BOX lists (box, kart, item, at):", "IDENTICAL" if same else "DIFFERENT",
              {n: len(v) for n, v in sets.items()})
        if not same:
            base = set(sets[names[0]])
            for n in names[1:]:
                print(f"   only in {names[0]} vs {n}:", sorted(base - set(sets[n]))[:10],
                      " only in", n, ":", sorted(set(sets[n]) - base)[:10])


main(sys.argv[1])
