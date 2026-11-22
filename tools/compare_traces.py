#!/usr/bin/env python3
"""Compare two folders of golden traces (core-rebuild story 001). REGRESSION TOOL.

Usage:
    python -I tools/compare_traces.py GOLDEN_DIR NEW_DIR [--expect N] [--tol FIELD=VALUE ...]

Every *.csv in GOLDEN_DIR (written by tools/capture_traces.gd) must exist in NEW_DIR.
Rows are compared in order, field by field, as text: the recorder writes floats as the
shortest text that reads back as the same 64-bit value, so equal text means equal values.
With --tol FIELD=VALUE a float field may differ by at most VALUE (default: exact); VALUE must
be >= 0 and FIELD a measured column of the golden header (tick and kart are always exact).
With --expect N the golden folder must hold exactly N *.csv files.

A golden file with no data row, or any row (golden or new) whose column count differs from
its header, is a divergence: an empty or torn trace never passes.

Prints one line per file:
    IDENTICAL <file> (<rows> rows)
    DIVERGED <file> tick=<t> kart=<k> field=<f> golden=<a> new=<b>
    WARN <file> only in the new capture (not compared)
then a final line IDENTICAL or DIVERGED. Exit code 0 when everything is identical,
1 on any divergence or missing file, 2 on bad usage.
"""
import argparse
import csv
import math
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


def _torn_row(name, side, head, rows):
    """Message for the first row whose column count differs from the header, or None."""
    for i, r in enumerate(rows):
        if len(r) != len(head):
            return "DIVERGED %s %s row %d (file line %d) has %d columns, header has %d" % (
                name, side, i + 1, i + 2, len(r), len(head))
    return None


def compare_file(golden_path, new_path, tols):
    """Returns (ok, message) for one trace file pair."""
    name = os.path.basename(golden_path)
    g_head, g_rows = _read(golden_path)
    if not g_head or not g_rows:
        return False, "DIVERGED %s golden has no data rows (%s)" % (name, "empty file" if not g_head else "header only")
    for k in KEY_FIELDS:
        if k not in g_head:
            return False, "DIVERGED %s golden header has no %s column" % (name, k)
    torn = _torn_row(name, "golden", g_head, g_rows)
    if torn:
        return False, torn
    if not os.path.isfile(new_path):
        return False, "DIVERGED %s missing in the new capture" % name
    n_head, n_rows = _read(new_path)
    if g_head != n_head:
        return False, "DIVERGED %s header golden=%s new=%s" % (name, ",".join(g_head), ",".join(n_head))
    torn = _torn_row(name, "new", n_head, n_rows)
    if torn:
        return False, torn
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
            a, b = g[j], n[j]
            if a == b:
                continue
            if f in tols and _within(a, b, tols[f]):
                continue
            return False, "DIVERGED %s tick=%s kart=%s field=%s golden=%s new=%s" % (
                name, g[idx["tick"]], g[idx["kart"]], f, a, b)
    return True, "IDENTICAL %s (%d rows)" % (name, len(g_rows))


def main(argv):
    p = argparse.ArgumentParser(description="Compare golden trace folders.")
    p.add_argument("golden")
    p.add_argument("new")
    p.add_argument("--expect", type=int, default=None, metavar="N",
                   help="fail unless the golden folder holds exactly N *.csv files")
    p.add_argument("--tol", action="append", default=[], metavar="FIELD=VALUE",
                   help="allowed absolute difference (>= 0) for a measured float field (default exact)")
    args = p.parse_args(argv)
    tols = {}
    for t in args.tol:
        if "=" not in t:
            p.error("--tol needs FIELD=VALUE, got %r" % t)
        k, v = t.split("=", 1)
        try:
            tol = float(v)
        except ValueError:
            p.error("--tol %s: %r is not a number" % (k, v))
        if math.isnan(tol) or tol < 0.0:
            p.error("--tol %s: tolerance must be >= 0, got %r" % (k, v))
        if k in KEY_FIELDS:
            p.error("--tol %s: %s identifies a row and is always compared exactly" % (k, k))
        tols[k] = tol
    if args.expect is not None and args.expect < 1:
        p.error("--expect must be >= 1, got %d" % args.expect)
    if not os.path.isdir(args.golden):
        print("DIVERGED golden folder not found: %s" % args.golden)
        return 2
    files = sorted(f for f in os.listdir(args.golden) if f.endswith(".csv"))
    if not files:
        print("DIVERGED no *.csv traces in %s" % args.golden)
        return 1
    for k in tols:
        for f in files:
            head, _ = _read(os.path.join(args.golden, f))
            if k not in head:
                p.error("--tol %s: no such column in %s (header: %s)" % (k, f, ",".join(head)))
    all_ok = True
    if args.expect is not None and len(files) != args.expect:
        print("DIVERGED expected %d golden *.csv files in %s, found %d" % (args.expect, args.golden, len(files)))
        all_ok = False
    for f in files:
        ok, msg = compare_file(os.path.join(args.golden, f), os.path.join(args.new, f), tols)
        print(msg)
        all_ok = all_ok and ok
    if os.path.isdir(args.new):
        for f in sorted(set(x for x in os.listdir(args.new) if x.endswith(".csv")) - set(files)):
            print("WARN %s only in the new capture (not compared)" % f)
    print("IDENTICAL" if all_ok else "DIVERGED")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
