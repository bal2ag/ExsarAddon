#!/usr/bin/env python3
"""Procedurally synthesize a blade-whoosh (pure stdlib) -> 16-bit mono WAV.

Not an AI model — plain DSP: white noise through a resonant state-variable
bandpass whose center frequency sweeps up then down (the doppler-ish 'whoosh'),
shaped by a fast-attack / smooth-decay amplitude envelope.
"""
import math, random, struct, wave

SR   = 44100
DUR  = 0.55
N    = int(SR * DUR)
random.seed(7)

# --- amplitude envelope: quick swell to a peak ~35% in, then smooth decay ----
def env(i):
    t = i / N
    attack = 0.12
    if t < attack:
        a = (t / attack) ** 0.6           # fast-ish swell
    else:
        a = math.exp(-3.2 * (t - attack)) # exponential tail
    # short click-guards at both ends
    edge = 0.02
    if t < edge:     a *= t / edge
    if t > 1 - edge: a *= (1 - t) / edge
    return a

# --- center-frequency sweep: rise then fall (the 'wsh' arc) -------------------
def cutoff(i):
    t = i / N
    # up to a peak around t=0.45, then back down
    arc = math.sin(min(t / 0.9, 1.0) * math.pi)   # 0->1->0 over the sweep
    return 350 + 2600 * arc                         # Hz

# --- Chamberlin state-variable filter, bandpass out, swept fc ----------------
Q = 1.9
q = 1.0 / Q
low = band = 0.0
samples = []
peak = 1e-9
for i in range(N):
    x = random.uniform(-1.0, 1.0)          # white noise
    fc = cutoff(i)
    f = 2.0 * math.sin(math.pi * min(fc / SR, 0.24))
    low += f * band
    high = x - low - q * band
    band += f * high
    y = band * env(i)
    samples.append(y)
    peak = max(peak, abs(y))

# normalize to -1.5 dBFS
norm = (10 ** (-1.5 / 20)) / peak
with wave.open("/Users/alexlandau/projects/ExsarAddon/Sounds/windfury.wav", "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    frames = bytearray()
    for y in samples:
        v = int(max(-1.0, min(1.0, y * norm)) * 32767)
        frames += struct.pack("<h", v)
    w.writeframes(bytes(frames))

print(f"wrote Sounds/windfury.wav  ({DUR}s, {SR}Hz, mono 16-bit, {N} frames)")
