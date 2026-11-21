"""Height and bank profiles for the track generators (story 008 part 4). Authoring aid, not run by
the game; imported by tools/gen_castle_circuit.py and tools/gen_dungeon_depths.py.

Heights: key points (main-loop s, meters) joined by straight lines, then box-blurred along the
control points so every change of grade is gradual. Banks: from each control point's corner radius
(BANK_GAIN / R degrees, capped), into the turn by default, with per-element overrides (off-camber
is a negative override), forced to 0 in "flat" windows (branch junctions, the grid, open edges),
then blurred. The low edge of a banked road must stay above the ground plane, so the centerline is
lifted where needed (dilate + blur keeps the lift >= what each point needs).

Sign conventions (TrackData.banks): positive bank = the TrackModel normal side (+1, the inside of a
right turn in the generators' heading convention) is HIGH, i.e. banked into a LEFT turn.
"""
import math

# Limits the generated profiles are checked against (also printed; tools/track_check.gd checks the
# built track against GRADE_MAX and BANK_MAX through TrackData).
GRADE_MAX = 0.12      # 12 % (6.8 degrees): the genre keeps drivable slopes moderate
BANK_MAX = 15.0       # degrees
BANK_GAIN = 240.0     # degrees * meters: R 16 m -> 15, R 20 -> 12, R 40 -> 6, R 145 -> 1.7
EDGE_CLEAR = 0.1      # meters the low edge (wall foot) keeps above the ground plane


def piecewise(cp_s, length, keys):
    """Height at each control point from keys [(s, h)] (s in main-loop meters, wrapped, sorted)."""
    ks = sorted(((s % length), h) for s, h in keys)
    out = []
    for s in cp_s:
        # find the surrounding keys on the loop
        prev = ks[-1]
        prev_s = prev[0] - length
        nxt = None
        for k in ks:
            if k[0] <= s:
                prev, prev_s = k, k[0]
            else:
                nxt = k
                break
        if nxt is None:
            nxt = (ks[0][0] + length, ks[0][1])
        span = nxt[0] - prev_s
        f = (s - prev_s) / span if span > 1e-9 else 0.0
        out.append(prev[1] + (nxt[1] - prev[1]) * f)
    return out


def blur(vals, radius, closed=True):
    n = len(vals)
    if radius <= 0:
        return list(vals)
    out = []
    for i in range(n):
        acc = 0.0
        cnt = 0
        for j in range(i - radius, i + radius + 1):
            if closed:
                acc += vals[j % n]
                cnt += 1
            elif 0 <= j < n:
                acc += vals[j]
                cnt += 1
        out.append(acc / cnt)
    return out


def dilate(vals, radius, closed=True):
    n = len(vals)
    out = []
    for i in range(n):
        m = -1e18
        for j in range(i - radius, i + radius + 1):
            if closed:
                m = max(m, vals[j % n])
            elif 0 <= j < n:
                m = max(m, vals[j])
        out.append(m)
    return out


def in_windows(s, windows, length):
    for a, b in windows:
        a %= length
        b %= length
        if (a <= b and a <= s <= b) or (a > b and (s >= a or s <= b)):
            return True
    return False


def banks(cp_s, length, cp_turn, flat_windows, blur_radius=2):
    """cp_turn: per control point (radius or None, angle sign +1 right / -1 left, override or None).
    override: degrees, positive = into the turn, negative = off-camber; None = BANK_GAIN / R."""
    raw = []
    for k, s in enumerate(cp_s):
        r, sign, ov = cp_turn[k]
        if r is None or in_windows(s, flat_windows, length):
            raw.append(0.0)
            continue
        mag = min(BANK_GAIN / r, BANK_MAX) if ov is None else ov
        # into a right turn (sign +1) the left (-1) side is high: negative bank in TrackData terms
        raw.append(-sign * mag)
    out = blur(raw, blur_radius)
    # keep the flat windows flat after the blur too
    return [0.0 if in_windows(s, flat_windows, length) else b for s, b in zip(cp_s, out)]


def lift_for_banks(heights, bank_deg, edge_half, radius=3):
    """Raise the centerline where a banked low edge would go under the ground plane."""
    need = [max(0.0, w * math.tan(math.radians(abs(b))) + EDGE_CLEAR - h) if abs(b) > 0.05 else 0.0
            for h, b, w in zip(heights, bank_deg, edge_half)]
    lift = blur(dilate(need, radius), radius)
    return [h + l for h, l in zip(heights, lift)], max(need)


def report(name, cp_s, heights, bank_deg, length, table=False):
    n = len(heights)
    if table:
        for k in range(0, n, 5):
            print("   s %6.1f  h %5.2f  bank %+5.1f" % (cp_s[k], heights[k], bank_deg[k]))
    worst_g = (0.0, 0.0)
    for k in range(n):
        ds = (cp_s[(k + 1) % n] - cp_s[k]) % length
        g = (heights[(k + 1) % n] - heights[k]) / ds if ds > 1e-6 else 0.0
        if abs(g) > abs(worst_g[0]):
            worst_g = (g, cp_s[k])
    kb = max(range(n), key=lambda k: abs(bank_deg[k]))
    print("%s: height %.2f..%.2f m, max grade %.1f %% at s %.0f, max bank %.1f deg at s %.0f" % (
        name, min(heights), max(heights), 100 * worst_g[0], worst_g[1], bank_deg[kb], cp_s[kb]))
    if abs(worst_g[0]) > GRADE_MAX + 1e-6:
        raise SystemExit("%s: grade %.1f %% over the %.0f %% limit" % (name, 100 * worst_g[0], 100 * GRADE_MAX))
    if abs(bank_deg[kb]) > BANK_MAX + 1e-6:
        raise SystemExit("%s: bank over the limit" % name)
    if min(heights) < 0.0:
        raise SystemExit("%s: road under the ground" % name)
