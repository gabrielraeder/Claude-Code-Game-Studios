#!/usr/bin/env python3
"""Compare two folders of golden traces (core-rebuild story 001). REGRESSION TOOL.

Usage:
    python -I tools/compare_traces.py GOLDEN_DIR NEW_DIR [--tol FIELD=VALUE ...]

Every *.csv in GOLDEN_DIR (written by tools/capture_traces.gd) must exist in NEW_DIR.
Rows are compared in order, field by field, as text: the recorder writes floats as the
shortest text that reads back as the same 64-bit value, so equal text means equal values.
With --tol FIELD=VALUE a float field may differ by at most VALUE (default: exact).

Prints one line per file:
    IDENTICAL <file> (<rows> rows)
    DIVERGED <file> tick=<t> kart=<k> field=<f> golden=<a> new=<b>
then a final line IDENTICAL or DIVERGED. Exit code 0 when everything is identical,
1 on any divergence or missing file, 2 on bad usage.
"""
import argparse
import csv
import os
import sys

# Columns that identify a row rather than measure it.
KEY_FIELDS = ("tick", "kart")


def _read(path):
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))
    if not rows:
        return [], []
    return rows[0], rows[1:]


def _within(a, b, tol):
    try:
        return abs(float(a) - float(b)) <= tol
    except ValueError:
        return False


def compare_file(golden_path, new_path, tols):
    """Returns (ok, message) for one trace file pair."""
    name = os.path.basename(golden_path)
    if not os.path.isfile(new_path):
        return False, "DIVERGED %s missing in the new capture" % name
    g_head, g_rows = _read(golden_path)
    n_head, n_rows = _read(new_path)
    if g_head != n_head:
        return False, "DIVERGED %s header golden=%s new=%s" % (name, ",".join(g_head), ",".join(n_head))
    idx = {f: i for i, f in enumerate(g_head)}
    for i in range(max(len(g_rows), len(n_rows))):
        if i >= len(g_rows) or i >= len(n_rows):
            have = g_rows[i] if i < len(g_rows) else n_rows[i]
            side = "golden" if i < len(g_rows) else "new"
            return False, "DIVERGED %s tick=%s kart=%s field=row golden=%s new=%s (only %s has rows from here; %d vs %d rows)" % (
                name, have[idx["tick"]], have[idx["kart"]],
                "present" if side == "golden" else "absent", "present" if side == "new" else "absent",
                side, len(g_rows), len(n_rows))
        g, n = g_rows[i], n_rows[i]
        for f, j in idx.items():
            a = g[j] if j < len(g) else ""
            b = n[j] if j < len(n) else ""
            if a == b:
                continue
            if f in tols and f not in KEY_FIELDS and _within(a, b, tols[f]):
                continue
            return False, "DIVERGED %s tick=%s kart=%s field=%s golden=%s new=%s" % (
                name, g[idx["tick"]], g[idx["kart"]], f, a, b)
    return True, "IDENTICAL %s (%d rows)" % (name, len(g_rows))


def main(argv):
    p = argparse.ArgumentParser(description="Compare golden trace folders.")
    p.add_argument("golden")
    p.add_argument("new")
    p.add_argument("--tol", action="append", default=[], metavar="FIELD=VALUE",
                   help="allowed absolute difference for a float field (default exact)")
    args = p.parse_args(argv)
    tols = {}
    for t in args.tol:
        if "=" not in t:
            p.error("--tol needs FIELD=VALUE, got %r" % t)
        k, v = t.split("=", 1)
        tols[k] = float(v)
    if not os.path.isdir(args.golden):
        print("DIVERGED golden folder not found: %s" % args.golden)
        return 2
    files = sorted(f for f in os.listdir(args.golden) if f.endswith(".csv"))
    if not files:
        print("DIVERGED no *.csv traces in %s" % args.golden)
        return 1
    all_ok = True
    for f in files:
        ok, msg = compare_file(os.path.join(args.golden, f), os.path.join(args.new, f), tols)
        print(msg)
        all_ok = all_ok and ok
    print("IDENTICAL" if all_ok else "DIVERGED")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
