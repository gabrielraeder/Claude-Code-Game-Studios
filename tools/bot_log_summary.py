"""Story 005: summarizes the [bot] and [item] lines of host.log in one test dir.

Usage: python -I tools/bot_log_summary.py <dir>
Prints per bot: personality, finish time, laps, stuck events, shortcut enters/misses, rubber mean,
AI microseconds per tick; then the field spread, bot item use by type and hits.
"""
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

KV = re.compile(r"(\w+)=(\"[^\"]*\"|\S+)")


def kv(line):
    return {k: v for k, v in KV.findall(line)}


def main(d):
    text = (Path(d) / "host.log").read_text(encoding="utf-8", errors="replace").splitlines()
    name = {}
    laps = defaultdict(list)
    fin = {}
    fin_info = {}
    stuck = Counter()
    stuck_long = {}
    enters = defaultdict(Counter)
    misses = defaultdict(Counter)
    plans = defaultdict(Counter)
    sinks = []
    for ln in text:
        if not ln.startswith("[bot]"):
            continue
        m = re.match(r"\[bot\] (\w+) kart=(\d+) name=(.+?) (\w+=.*)$", ln)
        if not m:
            continue
        ev, kart, nm, rest = m.group(1), int(m.group(2)), m.group(3), m.group(4)
        f = kv(rest)
        name[kart] = nm
        if ev == "LAP":
            laps[kart].append(float(f["time"]))
        elif ev == "FINISH":
            fin[kart] = float(f["total"])
            fin_info[kart] = f
        elif ev == "SINK":
            sinks.append((kart, nm, f))
        elif ev == "STUCK":
            stuck[kart] += 1
        elif ev == "STUCKEND":
            stuck_long[kart] = max(stuck_long.get(kart, 0.0), float(f["dur"]))
        elif ev == "BRANCH":
            if f["ev"] == "enter":
                enters[kart][f["id"]] += 1
            elif f["ev"] == "miss":
                misses[kart][f["id"]] += 1
        elif ev == "PLAN":
            for i in f.get("take", "").split(","):
                if i:
                    plans[kart][i] += 1
    print("kart name            finish   laps                       stuck(longest) enters  misses rubber ai_us")
    for k in sorted(name):
        fi = fin_info.get(k, {})
        print("%4d %-15s %7s  %-26s %d(%.1f)       %-7s %-6s %s %s" % (
            k, name[k], "%.2f" % fin[k] if k in fin else "DNF",
            " ".join("%.1f" % t for t in laps[k]), stuck[k], stuck_long.get(k, 0.0),
            sum(enters[k].values()), sum(misses[k].values()), fi.get("rubber_mean", "-"), fi.get("ai_us_per_tick", "-")))
    t = sorted(fin.values())
    if t:
        print("\nbots finished: %d/%d  first %.2f  last %.2f  spread %.1f%% of winner" % (
            len(t), len(name), t[0], t[-1], 100.0 * (t[-1] - t[0]) / t[0]))
    allstuck = max(stuck_long.values(), default=0.0)
    print("bots with a stuck event: %d, total events %d, longest stuck %.2f s" % (
        sum(1 for v in stuck.values() if v), sum(stuck.values()), allstuck))
    print("\nSINKS: %d total, %d self-caused (no bump and no hit in the last second)" % (
        len(sinks), sum(1 for _, _, f in sinks if f["bump"] == "0" and f["hit"] == "0")))
    print("  per personality:", dict(Counter(n for _, n, _ in sinks)))
    print("  per location:", dict(Counter("%s@%d" % (f["path"], int(f["s"]) // 20 * 20) for _, _, f in sinks)))
    for k, n, f in sinks:
        print("  kart %d %-15s s=%s path=%s hazard=%s speed=%s lat=%s bump=%s hit=%s t=%s" % (
            k, n, f["s"], f["path"], f["hazard"], f["speed"], f["lat"], f["bump"], f["hit"], f["t"]))
    twice = 0
    last = {}
    for k, n, f in sinks:
        t = float(f["t"])
        if k in last and t - last[k] < 5.0:
            twice += 1
        last[k] = t
    seed = next((m.group(1) for ln in text for m in [re.search(r"\[bot\] PLAN .* seed=(\d+)", ln)] if m), "?")
    print("  SEED %s; karts sinking again within 5 s: %d" % (seed, twice))
    skips = sum(1 for ln in text if "ev=skip_crowded" in ln)
    print("  shortcuts skipped because crowded:", skips)
    print("\nshortcut enters by name/branch:")
    for k in sorted(name):
        if enters[k] or misses[k] or plans[k]:
            print("  %-15s planned %s entered %s missed %s" % (name[k], dict(plans[k]), dict(enters[k]), dict(misses[k])))
    # host and the human-like reference
    for ln in text:
        if ln.startswith("[debug] finished"):
            print("\nhost autopilot:", ln)
        if ln.startswith("[net-summary]"):
            print(ln[:260])
    use = Counter()
    hits = Counter()
    uses_by_bot = Counter()
    bot_ids = set(name)
    for ln in text:
        m = re.match(r"\[item\] t=\S+ USE (\w+) seq=(\d+) owner=(\d+)", ln)
        if m and int(m.group(3)) in bot_ids:
            use[m.group(1)] += 1
            uses_by_bot[int(m.group(3))] += 1
        m = re.match(r"\[item\] t=\S+ USE horn kart=(\d+)", ln)
        if m and int(m.group(1)) in bot_ids:
            use["horn"] += 1
            uses_by_bot[int(m.group(1))] += 1
        m = re.match(r"\[item\] t=\S+ HIT seq=(\d+) item=(\w+) victim=(\d+) blocked=(\d)", ln)
        if m and int(m.group(1)) // 100000 in bot_ids:
            hits[(m.group(2), "blocked" if m.group(4) == "1" else "hit")] += 1
    print("\nbot item use:", dict(use))
    print("hits by bot items:", dict(hits))
    print("items used per bot:", {name.get(k, k): v for k, v in sorted(uses_by_bot.items())})


if __name__ == "__main__":
    main(sys.argv[1])
