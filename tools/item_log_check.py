"""Story 004: checks the per-PC item logs of one test dir (host.log, client*.log).

Usage: python -I tools/item_log_check.py <dir>
Prints per PC: hits, blocked hits, spins, spins without a hit, hits without a spin,
spin duration median, stone bounces at the hit, falcon misses, and cross-PC hit agreement.
"""
import re
import statistics
import sys
from pathlib import Path

LINE = re.compile(r"^\[item\] t=(-?[\d.]+) (\w+) ?(.*)$")
KV = re.compile(r"(\w+)=(\S+)")


def parse(path):
    ev = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = LINE.match(raw)
        if m:
            ev.append((float(m.group(1)), m.group(2), dict(KV.findall(m.group(3))), m.group(3)))
    return ev


def main(d):
    logs = sorted(Path(d).glob("*.log"))
    hit_sets = {}
    for p in logs:
        ev = parse(p)
        hits = [(e[2]["victim"], float(e[3].split("t=")[-1]), e[2]["blocked"], e[2].get("item", "?"), e[2]["seq"])
                for e in ev if e[1] == "HIT" and "victim" in e[2]]
        real = [h for h in hits if h[2] == "0"]
        blocked = [h for h in hits if h[2] == "1"]
        spins = [(e[2]["kart"], e[0]) for e in ev if e[1] == "SPIN"]
        durs = [float(e[2]["dur"]) for e in ev if e[1] == "SPINEND"]
        no_hit = [s for s in spins if not any(s[0] == h[0] and -0.3 <= s[1] - h[1] <= 0.8 for h in real)]
        no_spin = [h for h in real if not any(s[0] == h[0] and -0.3 <= s[1] - h[1] <= 0.8 for s in spins)]
        bounces = [int(e[2]["bounces"]) for e in ev if e[1] == "DECIDE" and e[2].get("item") == "stone"]
        misses = sum(1 for e in ev if e[1] == "END" and "falcon" in e[3] and "missed" in e[3])
        falcon_hits = sum(1 for h in hits if h[3] == "falcon")
        print(f"{p.name}: hits={len(hits)} (blocked {len(blocked)}) spins={len(spins)} "
              f"spins_without_hit={len(no_hit)} hits_without_spin={len(no_spin)} "
              f"spin_dur_median={statistics.median(durs) if durs else 'n/a'} "
              f"(min {min(durs) if durs else 'n/a'} max {max(durs) if durs else 'n/a'}) "
              f"stone_hit_bounces={sorted(set(bounces))} falcon_hits={falcon_hits} falcon_misses={misses}")
        if no_hit:
            print("   spins without hit:", no_hit[:5])
        if no_spin:
            print("   hits without spin:", no_spin[:5])
        hit_sets[p.name] = sorted((h[4], h[0], h[2]) for h in hits)
    names = list(hit_sets)
    if names:
        same = all(hit_sets[n] == hit_sets[names[0]] for n in names)
        print("cross-PC hit lists (seq, victim, blocked):", "IDENTICAL" if same else "DIFFERENT",
              {n: len(v) for n, v in hit_sets.items()})


main(sys.argv[1])
