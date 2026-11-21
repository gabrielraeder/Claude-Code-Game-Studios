#!/usr/bin/env python3
"""Story 009: compares the once-per-race-second "[hazard] t=..." lines (--hazard-log) of several PCs.

Usage: python -I tools/hazard_compare.py host.log client1.log [client2.log ...]

For every race second and mover logged by the first file and another, it compares the phase, the
blocked flag, the gate angle and, for rolling bodies, the distance and the world position. Each PC
logs at its own first tick of the second, so the race times differ by up to a tick; the report gives
the largest differences and the race-time difference they came with. Observations only.
"""
import re
import sys

LINE = re.compile(r"^\[hazard\] t=(-?[0-9.]+) mover=(\S+) phase=(\S+) progress=([0-9.-]+) angle=([0-9.-]+) "
                  r"blocked=(\d)(?: d=([0-9.-]+) x=([0-9.-]+) y=([0-9.-]+) z=([0-9.-]+))?")


def load(path):
    out = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for ln in f:
            m = LINE.match(ln.strip())
            if not m:
                continue
            t = float(m.group(1))
            key = (int(t + 1e-6) if t >= 0 else -1, m.group(2))
            out.setdefault(key, (t, m.group(3), float(m.group(4)), float(m.group(5)), int(m.group(6)),
                                 None if m.group(7) is None else tuple(float(m.group(k)) for k in range(7, 11))))
    return out


def main(paths):
    base = load(paths[0])
    print("%s: %d hazard lines" % (paths[0], len(base)))
    for p in paths[1:]:
        other = load(p)
        common = sorted(set(base) & set(other))
        phase_mis = 0
        blocked_mis = 0
        max_angle = (0.0, 0.0)
        max_pos = (0.0, 0.0, "")
        movers = set()
        for k in common:
            a = base[k]
            b = other[k]
            movers.add(k[1])
            dt = abs(a[0] - b[0])
            if a[1] != b[1]:
                phase_mis += 1
            if a[4] != b[4]:
                blocked_mis += 1
            if abs(a[3] - b[3]) > max_angle[0]:
                max_angle = (abs(a[3] - b[3]), dt)
            if a[5] is not None and b[5] is not None and a[1] == "active" and b[1] == "active":
                dp = sum((a[5][i] - b[5][i]) ** 2 for i in (1, 2, 3)) ** 0.5
                if dp > max_pos[0]:
                    max_pos = (dp, dt, "%s t=%d" % (k[1], k[0]))
        secs = sorted(set(k[0] for k in common))
        print("%s vs %s: %d lines (%d movers, seconds %s..%s), phase mismatches %d, blocked mismatches %d, "
              "max angle diff %.2f deg (race-time diff %.3f s), max rolling-body position diff %.3f m "
              "(race-time diff %.3f s, %s)" % (
                  paths[0], p, len(common), len(movers), secs[0] if secs else "-", secs[-1] if secs else "-",
                  phase_mis, blocked_mis, max_angle[0], max_angle[1], max_pos[0], max_pos[1], max_pos[2]))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    main(sys.argv[1:])
