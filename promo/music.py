"""Original soundtrack for the Doctori promo (synthesized, no samples).
Usage: python3 music.py sfx.json out.wav duration
"""
import json
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import lfilter

SR = 44100
meta = json.load(open(sys.argv[1]))
sfx = meta['sfx'] if isinstance(meta, dict) else meta
out_path = sys.argv[2]
DUR = float(sys.argv[3])
N = int(SR * DUR)
L = np.zeros(N)
R = np.zeros(N)
rng = np.random.default_rng(7)

BPM = 112
BEAT = 60 / BPM
BAR = BEAT * 4
INTRO_END = meta.get('intro_end', 11.5) if isinstance(meta, dict) else 11.5   # problem scenes
OUTRO = meta.get('outro', 57.0) if isinstance(meta, dict) else 57.0          # end card
S1_END = meta.get('s1_end', 6.5) if isinstance(meta, dict) else 6.5


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    return lfilter([1 - a], [1, -a], x)


def add(sig, t0, gain=1.0, pan=0.0):
    i = int(t0 * SR)
    if i >= N:
        return
    sig = sig[: N - i]
    L[i:i + len(sig)] += sig * gain * (1 - pan) / 1.0
    R[i:i + len(sig)] += sig * gain * (1 + pan) / 1.0


def env(n, a, d, s_level, r_len):
    e = np.ones(n) * s_level
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r_len * SR)
    a_n = min(a_n, n)
    e[:a_n] = np.linspace(0, 1, a_n)
    if a_n + d_n < n:
        e[a_n:a_n + d_n] = np.linspace(1, s_level, d_n)
    if r_n > 0 and r_n < n:
        e[-r_n:] *= np.linspace(1, 0, r_n)
    return e


def tone(freq, length, harmonics=(1.0, 0.5, 0.25), detune=0.0):
    t = np.arange(int(length * SR)) / SR
    s = np.zeros_like(t)
    for k, h in enumerate(harmonics, start=1):
        s += h * np.sin(2 * np.pi * freq * k * t * (1 + detune))
    return s


def pad(notes, t0, length, gain):
    n = int(length * SR)
    s = np.zeros(n)
    for m in notes:
        s += tone(midi(m), length, (1, .35, .12), 0.0015) + tone(midi(m), length, (1, .3), -0.0015)
    s = lowpass(s, 1400) * env(n, 0.6, 0.4, 0.8, 0.7)
    add(s / len(notes), t0, gain, 0)


def pluck(m, t0, gain, pan):
    length = 0.45
    n = int(length * SR)
    s = tone(midi(m), length, (1, .6, .3, .15)) * np.exp(-np.arange(n) / SR * 9)
    add(lowpass(s, 3500), t0, gain, pan)


def bass(m, t0, length, gain):
    n = int(length * SR)
    s = tone(midi(m), length, (1, .4)) * env(n, 0.01, 0.15, 0.6, 0.08)
    add(lowpass(s, 600), t0, gain)


def kick(t0, gain):
    n = int(0.28 * SR)
    t = np.arange(n) / SR
    f = 110 * np.exp(-t * 18) + 45
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 11)
    add(s, t0, gain)


def clap(t0, gain):
    n = int(0.18 * SR)
    s = rng.standard_normal(n) * np.exp(-np.arange(n) / SR * 26)
    s = s - lowpass(s, 900)
    add(lowpass(s, 6000), t0, gain, 0.1)


def hat(t0, gain):
    n = int(0.05 * SR)
    s = rng.standard_normal(n) * np.exp(-np.arange(n) / SR * 90)
    s = s - lowpass(s, 6000)
    add(s, t0, gain, -0.25)


def tick(t0, gain):
    n = int(0.03 * SR)
    s = np.sin(2 * np.pi * 2500 * np.arange(n) / SR) * np.exp(-np.arange(n) / SR * 200)
    add(s, t0, gain, 0.3)


def pop(t0):
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    f = 1400 * np.exp(-t * 14) + 500
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 30)
    add(s, t0, 0.22)


def whoosh(t0):
    n = int(0.55 * SR)
    s = rng.standard_normal(n)
    e = np.sin(np.linspace(0, np.pi, n)) ** 2
    s = lowpass(s, 2500) * e
    add(s, t0 - 0.15, 0.10)


def chime(t0):
    for i, m in enumerate([84, 88, 91, 96]):
        n = int(2.2 * SR)
        s = tone(midi(m), 2.2, (1, .2, .08)) * np.exp(-np.arange(n) / SR * 2.2)
        add(s, t0 + i * 0.07, 0.07, -0.3 + i * 0.2)


def riser(t0, length):
    n = int(length * SR)
    s = rng.standard_normal(n)
    cut = np.linspace(300, 6000, n)
    out = np.zeros(n)
    y = 0.0
    for k in range(0, n, 256):  # time-varying low-pass in blocks
        a = np.exp(-2 * np.pi * cut[k] / SR)
        blk = s[k:k + 256]
        o, _ = lfilter([1 - a], [1, -a], blk, zi=[y * a])
        out[k:k + 256] = o
        y = o[-1] if len(o) else y
    out *= np.linspace(0, 1, n) ** 2
    add(out, t0, 0.12)


# ---------- intro: calm, a bit tense (problem scenes) ----------
intro_chords = [[57, 60, 64], [53, 57, 60]]  # Am, F
t = 0.0
k = 0
while t < INTRO_END - 0.2:
    pad(intro_chords[k % 2], t, BAR * 1.05, 0.16)
    bass(intro_chords[k % 2][0] - 12, t, BAR * 0.9, 0.18)
    k += 1
    t += BAR
for b in range(int(S1_END / BEAT)):
    tick(b * BEAT, 0.12)                       # clock ticking in the waiting room
for b in range(int(S1_END / BEAT), int(INTRO_END / BEAT)):
    kick(b * BEAT, 0.25 if b % 2 == 0 else 0.0)  # pulse while papers fly
riser(INTRO_END - 1.4, 1.4)

# ---------- main: bright and upbeat (Doctori) ----------
prog = [[48, 52, 55, 60], [43, 47, 50, 55], [45, 48, 52, 57], [41, 45, 48, 53]]  # C G Am F
arp = [0, 2, 1, 3, 2, 1, 3, 2]
t = INTRO_END
bar = 0
while t < OUTRO - 0.05:
    ch = prog[bar % 4]
    pad([n + 12 for n in ch[1:]], t, BAR * 1.02, 0.11)
    for i in range(8):
        pluck(ch[arp[i]] + 24, t + i * BEAT / 2, 0.12, -0.35 if i % 2 else 0.35)
    for beat in range(4):
        bt = t + beat * BEAT
        bass(ch[0] - 12 if beat % 2 == 0 else ch[0], bt, BEAT * 0.9, 0.22)
        kick(bt, 0.55 if beat in (0, 2) else 0.35)
        if beat in (1, 3):
            clap(bt, 0.16)
        hat(bt + BEAT / 2, 0.05)
    bar += 1
    t += BAR

# ---------- outro ----------
pad([60, 64, 67, 72], OUTRO, DUR - OUTRO, 0.18)
bass(36, OUTRO, DUR - OUTRO - 0.5, 0.2)
for i, m in enumerate([72, 76, 79, 84, 79, 76]):
    pluck(m, OUTRO + 0.6 + i * BEAT / 2, 0.1, -0.3 + 0.12 * i)

# ---------- effects synced to the picture ----------
for when, kind in sfx:
    {"pop": pop, "whoosh": whoosh, "chime": chime}[kind](when)

mix = np.stack([L, R], axis=1)
fade_in = int(0.3 * SR)
mix[:fade_in] *= np.linspace(0, 1, fade_in)[:, None]
fade_out = int(3.0 * SR)
mix[-fade_out:] *= np.linspace(1, 0, fade_out)[:, None] ** 1.5
mix /= np.max(np.abs(mix)) / 0.89
wavfile.write(out_path, SR, (mix * 32767).astype(np.int16))
print("wrote", out_path)
