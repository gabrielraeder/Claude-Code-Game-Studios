#!/usr/bin/env python3
"""Deterministic placeholder audio synthesiser for Dogworks Racing (story 007, sound).

Regenerates every .wav in assets/audio/ (22.05 kHz, 16-bit mono). Original, procedurally
generated sounds; no external assets. Needs numpy. Run: python tools/synth_audio.py
Same seed + same numpy => byte-identical output.
"""
import os
import sys
import wave
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
rng = np.random.default_rng(7007)


def t_arr(dur):
    return np.arange(int(SR * dur)) / SR


def env_ad(n, a, d_pow=3.0):
    """Attack (seconds) then power decay over the rest of n samples."""
    x = np.arange(n) / SR
    atk = np.minimum(1.0, x / max(a, 1e-4))
    dec = (1.0 - np.arange(n) / n) ** d_pow
    return atk * dec


def noise(n):
    return rng.standard_normal(n)


def fft_filter(x, lo, hi):
    """Zero-phase band-pass via FFT (lo/hi in Hz; hi<=0 means no upper limit)."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    mask = (f >= lo) & ((f <= hi) if hi > 0 else True)
    return np.fft.irfft(spec * mask, len(x))


def periodic_noise(n, lo, hi):
    """Noise that is exactly periodic over n samples (random phases), so it loops."""
    f = np.fft.rfftfreq(n, 1.0 / SR)
    mag = ((f >= lo) & ((f <= hi) if hi > 0 else True)).astype(float)
    ph = rng.uniform(0, 2 * np.pi, len(f))
    spec = mag * np.exp(1j * ph)
    spec[0] = 0
    return np.fft.irfft(spec, n)


def lowpass_var(x, cutoff):
    """One-pole low-pass with per-sample cutoff array (Hz)."""
    a = 1.0 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros(len(x))
    s = 0.0
    for i in range(len(x)):
        s += a[i] * (x[i] - s)
        y[i] = s
    return y


def sweep_sine(f0, f1, dur, power=1.0):
    t = t_arr(dur)
    k = (t / dur) ** power
    f = f0 + (f1 - f0) * k
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def brass(freq, dur, vib=5.0, bright=1.0):
    t = t_arr(dur)
    f = freq * (1 + 0.006 * np.sin(2 * np.pi * vib * t) * np.minimum(1, t / 0.2))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.zeros(len(t))
    for h in range(1, 10):
        y += np.sin(h * ph) / h ** (0.9 / bright)
    e = np.minimum(1, t / 0.07) * np.minimum(1, (dur - t) / 0.08)
    return y * e


def pluck(freq, dur, decay=4.0):
    t = t_arr(dur)
    y = np.zeros(len(t))
    for h, a in enumerate([1.0, 0.5, 0.3, 0.18, 0.1, 0.06], 1):
        y += a * np.sin(2 * np.pi * freq * h * t) * np.exp(-t * decay * (0.6 + 0.4 * h))
    return y * np.minimum(1, t / 0.003)


def flute(freq, dur):
    t = t_arr(dur)
    f = freq * (1 + 0.004 * np.sin(2 * np.pi * 5.2 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) + 0.25 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    y += 0.03 * np.convolve(noise(len(t)), np.ones(4) / 4, "same")
    e = np.minimum(1, t / 0.06) * np.minimum(1, (dur - t) / 0.1)
    return y * e


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def fades(x, ms=4.0):
    n = int(SR * ms / 1000)
    x = x.copy()
    ramp = np.linspace(0, 1, n)
    x[:n] *= ramp
    x[-n:] *= ramp[::-1]
    return x


def norm(x, peak=0.89):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def seq(parts, total):
    out = np.zeros(int(SR * total))
    for start, y in parts:
        i = int(SR * start)
        j = min(len(out), i + len(y))
        out[i:j] += y[: j - i]
    return out


# ---------------------------------------------------------------- sounds
def engine_loop():
    n = SR  # 1.0 s, integer cycles of everything below
    t = np.arange(n) / SR
    base = 55.0
    y = np.zeros(n)
    for h, a in enumerate([1.0, 0.7, 0.55, 0.4, 0.3, 0.2, 0.12, 0.08], 1):
        y += a * np.sin(2 * np.pi * base * h * t + h * 0.7)
    y *= 1 + 0.25 * np.sin(2 * np.pi * 11 * t)  # putter, integer Hz
    y = np.tanh(y * 0.9)
    y += 0.25 * periodic_noise(n, 40, 400) / 3
    return norm(y, 0.8)


def drift_loop():
    n = SR
    t = np.arange(n) / SR
    y = periodic_noise(n, 2500, 9000)
    y = y / np.max(np.abs(y))
    y = y * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t) * np.sin(2 * np.pi * 13 * t + 1.0))
    for k in range(18):  # sparks: short crackles, wrapped so the loop stays seamless
        i = int(rng.integers(0, n))
        idx = (np.arange(300) + i) % n
        y[idx] += rng.standard_normal(300) * np.exp(-np.arange(300) / 40) * 0.8
    return norm(y, 0.7)


def boost():
    dur = 0.8
    n = int(SR * dur)
    t = t_arr(dur)
    cut = 300 + 5000 * np.sin(np.pi * np.minimum(1, t / dur)) ** 1.5
    y = lowpass_var(noise(n), cut) * 3
    y *= np.minimum(1, t / 0.08) * (1 - t / dur) ** 1.2
    y += 0.4 * sweep_sine(120, 420, dur) * (1 - t / dur)
    return fades(norm(y))


def bump():
    dur = 0.28
    n = int(SR * dur)
    y = sweep_sine(110, 45, dur, 0.5) * env_ad(n, 0.002, 2.5)
    y += 0.6 * lowpass_var(noise(n), np.full(n, 600.0)) * env_ad(n, 0.001, 6) * 3
    return fades(norm(y))


def wall():
    dur = 0.45
    n = int(SR * dur)
    t = t_arr(dur)
    scrape = fft_filter(noise(n), 700, 3500) * (1 + 0.5 * np.sin(2 * np.pi * 38 * t))
    scrape *= env_ad(n, 0.01, 1.5)
    thud = sweep_sine(150, 60, dur, 0.4) * env_ad(n, 0.002, 7)
    return fades(norm(scrape / np.max(np.abs(scrape)) * 0.6 + thud))


def spin():
    dur = 0.9
    t = t_arr(dur)
    f = 500 + 250 * np.sin(2 * np.pi * 5 * t) - 300 * t
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) + 0.3 * np.sin(2 * ph)
    return fades(norm(y * np.minimum(1, t / 0.03) * (1 - t / dur) ** 0.8))


def chime(notes, step, note_dur):
    parts = []
    for i, m in enumerate(notes):
        tt = t_arr(note_dur)
        f = midi(m)
        y = (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(2 * np.pi * f * 2.01 * tt)
             + 0.1 * np.sin(2 * np.pi * f * 3.97 * tt)) * np.exp(-tt * 6)
        parts.append((i * step, y))
    return seq(parts, step * (len(notes) - 1) + note_dur)


def item_pickup():
    return fades(norm(chime([79, 84, 88], 0.07, 0.4)))


def item_horn():
    return fades(norm(brass(220.0, 0.7)), 15)


def horn_go():
    a = brass(330.0, 0.35, 4.0)
    b = brass(440.0, 0.9, 5.5, 1.3)
    return fades(norm(seq([(0, a), (0.3, b)], 1.2)), 15)


def stone_launch():
    dur = 0.5
    n = int(SR * dur)
    t = t_arr(dur)
    y = sweep_sine(90, 50, dur, 0.5) * env_ad(n, 0.003, 3)
    w = lowpass_var(noise(n), 200 + 2500 * (t / dur) ** 2) * 2 * np.minimum(1, t / 0.2) * (1 - t / dur)
    return fades(norm(y + 0.6 * w))


def spill_splash():
    dur = 0.6
    n = int(SR * dur)
    y = fft_filter(noise(n), 500, 5000) * env_ad(n, 0.01, 2.5)
    amp = np.max(np.abs(y))
    for k in range(7):
        s = float(rng.uniform(0.05, 0.4))
        f = float(rng.uniform(500, 1200))
        tt = t_arr(0.07)
        b = np.sin(2 * np.pi * np.cumsum(f * (1 + 6 * tt)) / SR) * np.exp(-tt * 40)
        i = int(s * SR)
        y[i:i + len(b)] += 0.5 * b * amp
    return fades(norm(y))


def falcon_screech():
    dur = 0.75
    t = t_arr(dur)
    f = 1700 + 1100 * np.sin(np.pi * np.minimum(1, t / 0.5)) + 90 * np.sin(2 * np.pi * 28 * t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.3 * np.sin(3 * ph)
    y += 0.25 * fft_filter(noise(len(t)), 2000, 6000)
    y *= np.minimum(1, t / 0.04) * (1 - t / dur) ** 0.7
    return fades(norm(y), 8)


def shield_up():
    parts = []
    for i, m in enumerate([72, 76, 79, 84]):
        tt = t_arr(0.35)
        f = midi(m)
        y = np.sin(2 * np.pi * f * tt + 2 * np.sin(2 * np.pi * 6 * tt)) * np.exp(-tt * 5)
        parts.append((i * 0.06, y))
    return fades(norm(seq(parts, 0.6)))


def shield_break():
    dur = 0.55
    n = int(SR * dur)
    y = fft_filter(noise(n), 3000, 0) * env_ad(n, 0.001, 4)
    y += 0.5 * sweep_sine(1200, 200, dur, 0.6) * env_ad(n, 0.002, 3)
    amp = np.max(np.abs(y))
    for k in range(5):
        tt = t_arr(0.12)
        f = float(rng.uniform(2500, 5000))
        i = int(rng.uniform(0.02, 0.3) * SR)
        y[i:i + len(tt)] += 0.35 * np.sin(2 * np.pi * f * tt) * np.exp(-tt * 30) * amp
    return fades(norm(y))


def item_hit():
    dur = 0.45
    n = int(SR * dur)
    t = t_arr(dur)
    f = 180 + 500 * np.exp(-t * 9) * (1 + 0.4 * np.sin(2 * np.pi * 14 * t))
    boing = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(n, 0.003, 1.8)
    pop = lowpass_var(noise(n), np.full(n, 2500.0)) * env_ad(n, 0.001, 20) * 3
    return fades(norm(boing + 0.7 * pop))


def splash():
    dur = 0.7
    n = int(SR * dur)
    t = t_arr(dur)
    cut = 3500 * np.exp(-t * 4) + 300
    y = lowpass_var(noise(n), cut) * 3 * np.minimum(1, t / 0.02) * (1 - t / dur) ** 1.5
    y += 0.4 * sweep_sine(200, 70, dur, 0.4) * env_ad(n, 0.003, 5)
    return fades(norm(y))


def lava_sizzle():
    dur = 0.9
    n = int(SR * dur)
    t = t_arr(dur)
    y = fft_filter(noise(n), 3500, 0) * 0.5
    for k in range(60):
        i = int(rng.integers(0, n - 200))
        y[i:i + 160] += rng.standard_normal(160) * np.exp(-np.arange(160) / 22) * 1.5
    y += 0.35 * lowpass_var(noise(n), np.full(n, 250.0)) * 4
    y *= np.minimum(1, t / 0.05) * (1 - t / dur) ** 0.8
    return fades(norm(y), 10)


def lap():
    parts = [(0.0, brass(392.0, 0.18, 0)), (0.18, brass(523.25, 0.18, 0)),
             (0.36, brass(659.25, 0.6, 5.5, 1.3))]
    return fades(norm(seq(parts, 1.0)), 10)


def finish():
    notes = [(0.0, 392.0, 0.2), (0.22, 392.0, 0.2), (0.44, 523.25, 0.25), (0.72, 659.25, 0.25),
             (1.0, 783.99, 0.9)]
    parts = [(s, brass(f, d, 5.5, 1.2) + 0.5 * brass(f / 2, d, 5.5, 1.0)) for s, f, d in notes]
    parts.append((1.0, 0.4 * brass(523.25, 0.9, 5.5, 1.0)))
    return fades(norm(seq(parts, 2.0)), 15)


def ui_move():
    tt = t_arr(0.06)
    return fades(norm(np.sin(2 * np.pi * 900 * tt) * np.exp(-tt * 50)), 2) * 0.6


def ui_accept():
    return fades(norm(chime([76, 83], 0.07, 0.2)), 3) * 0.8


def ui_back():
    return fades(norm(chime([83, 76], 0.06, 0.18)), 3) * 0.7


def music_loop():
    bpm = 120
    beat = 60.0 / bpm
    bars = 12
    total = bars * 4 * beat  # 24 s
    n = int(SR * total)
    out = np.zeros(n)

    def add(start, y):
        i = int(round(start * SR))
        idx = (np.arange(len(y)) + i) % n  # wraps: seamless loop
        np.add.at(out, idx, y)

    # drone: frequencies are multiples of 1/24 Hz so the loop closes exactly
    t = np.arange(n) / SR
    for f, a in [(65.4166667, 0.22), (98.0, 0.12), (130.8333333, 0.06)]:
        f = round(f * total) / total
        out += a * np.sin(2 * np.pi * f * t) * (0.85 + 0.15 * np.sin(2 * np.pi * (1 / total) * 6 * t))
    chords = [(48, 52, 55), (43, 47, 50), (45, 48, 52), (41, 45, 48),
              (48, 52, 55), (43, 47, 50), (41, 45, 48), (43, 47, 50),
              (48, 52, 55), (45, 48, 52), (41, 45, 48), (43, 47, 50)]
    pat = [0, 1, 2, 1, 0, 1, 2, 1]
    for b, ch in enumerate(chords):
        for k in range(8):
            m = ch[pat[k]] + 12
            add((b * 4 + k * 0.5) * beat, 0.30 * pluck(midi(m), beat * 2))
        add(b * 4 * beat, 0.25 * pluck(midi(ch[0] - 12), 1.8, 2.0))
    scale = [60, 62, 64, 67, 69, 72, 74, 76, 79]  # C major pentatonic
    r = np.random.default_rng(31)
    idx = 4
    for b in range(bars):
        if b % 4 == 3 and b != 11:
            continue  # breathing bar
        pos = 0.0
        rhythm = [1, 1, 2] if b % 2 == 0 else [2, 1, 1]
        for d in rhythm:
            idx = int(np.clip(idx + r.integers(-2, 3), 1, len(scale) - 1))
            if pos == 0.0 and b % 4 == 0:
                idx = 5
            add((b * 4 + pos) * beat, 0.35 * flute(midi(scale[idx]), d * beat * 0.95))
            pos += d
    for b in range(bars * 4):  # soft off-beat tick
        tt = t_arr(0.05)
        add((b + 0.5) * beat, 0.04 * noise(len(tt)) * np.exp(-tt * 80))
    return norm(out, 0.45)


SOUNDS = {
    "engine_loop": engine_loop, "drift_loop": drift_loop, "boost": boost, "bump": bump,
    "wall": wall, "spin": spin, "item_pickup": item_pickup, "item_horn": item_horn,
    "horn_go": horn_go, "stone_launch": stone_launch, "spill_splash": spill_splash,
    "falcon_screech": falcon_screech, "shield_up": shield_up, "shield_break": shield_break,
    "item_hit": item_hit, "splash": splash, "lava_sizzle": lava_sizzle, "lap": lap,
    "finish": finish, "ui_move": ui_move, "ui_accept": ui_accept, "ui_back": ui_back,
    "music_loop": music_loop,
}


def write_wav(path, x):
    pcm = np.round(np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    out = os.path.normpath(OUT)
    os.makedirs(out, exist_ok=True)
    for name, fn in SOUNDS.items():  # fixed order => deterministic rng stream
        write_wav(os.path.join(out, name + ".wav"), fn())
        print("wrote", name + ".wav")


if __name__ == "__main__":
    sys.exit(main())
