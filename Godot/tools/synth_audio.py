#!/usr/bin/env python3
"""Synthesises every sound in the game into Godot/audio/, from scratch.

The music is an original score in the style of early-2000s industrial-metal
chase music: 160 BPM, D phrygian, double-kick drums, palm-muted drop-D guitar,
frantic string ostinatos and a dark choir. It's split into four looping stems
that the MusicDirector fades in as the danger rises:

    drone       0.00 - 0.20   low drone, dissonant shimmer, rising swells
    percussion  0.20 - 0.50   taiko, toms, metallic clanks, shaker
    riff        0.40 - 0.70   guitar riff and drum kit
    choir       0.70 - 0.95   choir, brass stabs, string ostinato

Pure Python (no numpy), so it runs anywhere. It takes a minute or two:

    python3 Godot/tools/synth_audio.py
"""
import math
import os
import random
import struct
import wave

SR = 32000
BPM = 160
BEAT = 60.0 / BPM
SIXTEENTH = BEAT / 4
BAR = BEAT * 4
BARS = 16
LOOP = BAR * BARS  # 24 s

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
TAU = 2 * math.pi
rng = random.Random(7)


# ---------------------------------------------------------------------------
# Basics
# ---------------------------------------------------------------------------

def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def n_samples(seconds):
    return int(seconds * SR)


class Mix:
    """A buffer that sounds are added into. With wrap=True, anything running
    past the end comes back in at the start, so loops are seamless."""

    def __init__(self, seconds, stereo=True):
        self.n = n_samples(seconds)
        self.L = [0.0] * self.n
        self.R = [0.0] * self.n if stereo else None

    def add(self, t, samples, gain=1.0, pan=0.0, wrap=True):
        i0 = int(t * SR)
        n = self.n
        if self.R is None:
            gl, gr = gain, 0.0
        else:
            a = (pan + 1) * math.pi / 4
            gl, gr = gain * math.cos(a) * 1.414, gain * math.sin(a) * 1.414
        L, R = self.L, self.R
        for k, s in enumerate(samples):
            j = i0 + k
            if j >= n:
                if not wrap:
                    break
                j %= n
            L[j] += s * gl
            if R is not None:
                R[j] += s * gr

    def add_stereo(self, t, left, right, gain=1.0):
        i0 = int(t * SR)
        for k in range(len(left)):
            j = (i0 + k) % self.n
            self.L[j] += left[k] * gain
            self.R[j] += right[k] * gain

    def normalize(self, peak=0.85):
        m = max(max(abs(v) for v in self.L), max(abs(v) for v in self.R) if self.R else 0.0, 1e-9)
        g = peak / m
        self.L = [v * g for v in self.L]
        if self.R:
            self.R = [v * g for v in self.R]

    def save(self, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with wave.open(path, "wb") as w:
            w.setnchannels(2 if self.R else 1)
            w.setsampwidth(2)
            w.setframerate(SR)
            frames = bytearray()
            if self.R:
                for l, r in zip(self.L, self.R):
                    frames += struct.pack("<hh", _clip16(l), _clip16(r))
            else:
                for v in self.L:
                    frames += struct.pack("<h", _clip16(v))
            w.writeframes(bytes(frames))
        print("wrote", os.path.relpath(path, os.path.join(OUT, "..")))


def _clip16(v):
    return max(-32767, min(32767, int(v * 32767)))


def loop_crossfade(x, loop_len, fade):
    """x has loop_len + fade samples; fold the tail into the head so it loops."""
    out = x[:loop_len]
    for i in range(fade):
        w = i / fade
        out[i] = x[i] * w + x[loop_len + i] * (1 - w)
    return out


# ---------------------------------------------------------------------------
# Oscillators, envelopes, filters
# ---------------------------------------------------------------------------

def saw(freq, n, phase=0.0, vib_rate=0.0, vib_depth=0.0):
    out = [0.0] * n
    p = phase
    for i in range(n):
        f = freq * (1 + vib_depth * math.sin(TAU * vib_rate * i / SR)) if vib_depth else freq
        p += f / SR
        p -= int(p)
        out[i] = 2 * p - 1
    return out


def sine(freq, n, phase=0.0):
    w = TAU * freq / SR
    return [math.sin(phase + w * i) for i in range(n)]


def sweep_sine(f0, f1, n, curve=6.0):
    """Sine gliding from f0 to f1 (exponential-ish)."""
    out = [0.0] * n
    p = 0.0
    for i in range(n):
        t = i / max(n - 1, 1)
        f = f1 + (f0 - f1) * math.exp(-curve * t)
        p += TAU * f / SR
        out[i] = math.sin(p)
    return out


def noise(n):
    return [rng.uniform(-1, 1) for _ in range(n)]


def env_ad(n, attack, decay_tau):
    a = max(1, n_samples(attack))
    out = [0.0] * n
    for i in range(n):
        if i < a:
            out[i] = i / a
        else:
            out[i] = math.exp(-(i - a) / (decay_tau * SR))
    return out


def env_asr(n, attack, release):
    a = max(1, n_samples(attack))
    r = max(1, n_samples(release))
    out = [1.0] * n
    for i in range(min(a, n)):
        out[i] = i / a
    for i in range(max(0, n - r), n):
        out[i] *= (n - i) / r
    return out


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def add(*sigs):
    n = min(len(s) for s in sigs)
    return [sum(s[i] for s in sigs) for i in range(n)]


def scale(a, g):
    return [x * g for x in a]


def drive(a, amount):
    k = math.tanh(amount)
    return [math.tanh(x * amount) / k for x in a]


def onepole_lp(x, cutoff):
    a = math.exp(-TAU * cutoff / SR)
    y = 0.0
    out = [0.0] * len(x)
    for i, v in enumerate(x):
        y = (1 - a) * v + a * y
        out[i] = y
    return out


def onepole_hp(x, cutoff):
    lp = onepole_lp(x, cutoff)
    return [a - b for a, b in zip(x, lp)]


def biquad(x, kind, freq, q=0.707, freq_env=None):
    """RBJ biquad. freq_env, if given, is a per-sample cutoff list."""
    out = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    coeffs = None
    last_f = None
    for i, v in enumerate(x):
        f = freq_env[i] if freq_env else freq
        if f != last_f and (freq_env is None or i % 16 == 0 or coeffs is None):
            f = max(20.0, min(f, SR * 0.45))
            w = TAU * f / SR
            cw, sw = math.cos(w), math.sin(w)
            alpha = sw / (2 * q)
            if kind == "lp":
                b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
            elif kind == "hp":
                b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
            else:  # bandpass, constant peak gain
                b0, b1, b2 = alpha, 0.0, -alpha
            a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
            coeffs = (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
            last_f = f
        b0, b1, b2, a1, a2 = coeffs
        y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, y
        out[i] = y
    return out


# ---------------------------------------------------------------------------
# Instruments
# ---------------------------------------------------------------------------

def kick(dur=0.35):
    n = n_samples(dur)
    body = mul(sweep_sine(140, 42, n, 9), env_ad(n, 0.001, 0.12))
    click = mul(onepole_hp(noise(n), 2000), env_ad(n, 0.0005, 0.004))
    return drive(add(body, scale(click, 0.5)), 1.8)


def snare(dur=0.3):
    n = n_samples(dur)
    tone = mul(sweep_sine(240, 180, n, 8), env_ad(n, 0.001, 0.06))
    rattle = mul(biquad(noise(n), "bp", 2200, 0.6), env_ad(n, 0.001, 0.09))
    return drive(add(scale(tone, 0.6), scale(rattle, 1.6)), 1.5)


def crash(dur=1.6):
    n = n_samples(dur)
    x = onepole_hp(noise(n), 4000)
    return mul(x, env_ad(n, 0.002, 0.5))


def taiko(dur=0.9, pitch=62):
    n = n_samples(dur)
    body = mul(sweep_sine(pitch * 1.6, pitch, n, 10), env_ad(n, 0.002, 0.28))
    skin = mul(onepole_lp(noise(n), 500), env_ad(n, 0.001, 0.05))
    return drive(add(body, scale(skin, 0.7)), 2.0)


def tom(pitch, dur=0.5):
    n = n_samples(dur)
    return drive(mul(sweep_sine(pitch * 1.3, pitch, n, 12), env_ad(n, 0.001, 0.16)), 1.4)


def clank(dur=0.6):
    n = n_samples(dur)
    parts = [(523, 1.0), (1187, 0.7), (1795, 0.5), (2753, 0.35), (3911, 0.2)]
    x = [0.0] * n
    for f, a in parts:
        s = sine(f * rng.uniform(0.98, 1.02), n, rng.uniform(0, TAU))
        for i in range(n):
            x[i] += s[i] * a
    x = mul(x, env_ad(n, 0.0005, 0.12))
    hit = mul(biquad(noise(n), "bp", 3000, 1.0), env_ad(n, 0.0005, 0.015))
    return add(scale(x, 0.35), hit)


def shaker(dur=0.08):
    n = n_samples(dur)
    return mul(onepole_hp(noise(n), 6000), env_ad(n, 0.004, 0.02))


def guitar(midi, dur, mute=True, power=True):
    """Drop-D distorted guitar: root, fifth and octave saws into a fuzz."""
    n = n_samples(dur + 0.05)
    f = mtof(midi)
    x = saw(f * 1.002, n)
    x = add(x, saw(f * 0.998, n, 0.3))
    if power:
        x = add(x, scale(saw(f * 1.4983, n, 0.6), 0.8), scale(saw(f * 2.003, n, 0.1), 0.5))
    x = onepole_lp(x, 900 if mute else 2600)
    x = drive(x, 9.0)
    x = biquad(x, "lp", 3800 if not mute else 2400, 0.9)
    x = onepole_hp(x, 90)
    if mute:
        e = env_ad(n, 0.002, 0.07)
    else:
        e = mul(env_asr(n, 0.003, 0.05), env_ad(n, 0.0, 1.2))
    return mul(x, e)


def string_note(midi, dur):
    n = n_samples(dur)
    x = add(saw(mtof(midi) * 1.003, n, 0, 6.0, 0.004), saw(mtof(midi) * 0.997, n, 0.5, 5.5, 0.004))
    x = biquad(x, "lp", 3500, 0.8)
    x = onepole_hp(x, 300)
    return mul(x, env_ad(n, 0.004, dur * 0.6))


def brass_stab(midis, dur=0.5):
    n = n_samples(dur)
    x = [0.0] * n
    for m in midis:
        for d in (0.997, 1.003):
            s = saw(mtof(m) * d, n, rng.random())
            for i in range(n):
                x[i] += s[i]
    cut = [300 + 3200 * math.exp(-i / (0.08 * SR)) for i in range(n)]
    x = biquad(x, "lp", 0, 1.2, cut)
    return drive(mul(x, env_ad(n, 0.01, 0.25)), 1.5)


def choir_chord(midis, dur):
    """Saw voices with vibrato, shaped into an 'aah' by two formant filters."""
    n = n_samples(dur)
    x = [0.0] * n
    for m in midis:
        for d, rate in ((0.996, 5.1), (1.004, 4.7), (1.0, 5.6)):
            s = saw(mtof(m) * d, n, rng.random(), rate, 0.006)
            for i in range(n):
                x[i] += s[i]
    f1 = biquad(x, "bp", 750, 4.0)
    f2 = biquad(x, "bp", 1150, 5.0)
    f3 = biquad(x, "bp", 2600, 6.0)
    y = [a + 0.6 * b + 0.25 * c for a, b, c in zip(f1, f2, f3)]
    return mul(y, env_asr(n, 0.7, 0.9))


# ---------------------------------------------------------------------------
# The score: 16 bars of D phrygian, chord per 4 bars
# ---------------------------------------------------------------------------

# (guitar root, choir voicing, string ostinato notes)
CHORDS = [
    (38, [50, 53, 57, 62], [74, 75, 74, 72]),   # Dm, with the Eb (b2) bite
    (46, [46, 50, 53, 58], [74, 77, 74, 70]),   # Bb
    (43, [43, 50, 55, 58], [74, 75, 79, 74]),   # Gm
    (45, [45, 52, 57, 61], [73, 76, 73, 69]),   # A (major: pulls back to D)
]

# Riff per bar in sixteenths: x = palm-muted root, A = open accent,
# b = flat second, t = tritone, . = rest
RIFF = ["x.xxA..xx.xxb.x.", "x.xxA..xx.xxt.A.", "x.xxA..xx.xxb.x.", "xxxxA.A.AxxxAxAx"]


def chord_at(bar):
    return CHORDS[(bar // 4) % 4]


def stem_drone():
    fade = n_samples(2.0)
    total = n_samples(LOOP) + fade
    L = [0.0] * total
    R = [0.0] * total
    for bar in range(BARS + 1):
        root = chord_at(bar % BARS)[0] - 12
        t0 = n_samples(bar * BAR)
        n = n_samples(BAR + 0.5)
        tone = add(saw(mtof(root) * 0.997, n), saw(mtof(root) * 1.003, n, 0.4), scale(saw(mtof(root + 7), n, 0.2), 0.5))
        tone = biquad(tone, "lp", 180 + 60 * math.sin(bar), 1.3)
        e = env_asr(n, 0.25, 0.5)
        for i in range(n):
            j = t0 + i
            if j < total:
                v = tone[i] * e[i] * 0.6
                L[j] += v
                R[j] += v
    # Dissonant shimmer: D and Eb a semitone apart, slowly beating, wide.
    shimmer_l = add(sine(mtof(74), total), scale(sine(mtof(75), total, 1.0), 0.8))
    shimmer_r = add(sine(mtof(74) * 1.002, total, 0.5), scale(sine(mtof(75) * 0.998, total, 2.0), 0.8))
    trem = [0.5 + 0.5 * math.sin(TAU * 0.11 * i / SR) for i in range(total)]
    for i in range(total):
        L[i] += shimmer_l[i] * trem[i] * 0.05
        R[i] += shimmer_r[i] * trem[i] * 0.05
    # Rumble.
    rumble = onepole_lp(onepole_lp(noise(total), 60), 60)
    for i in range(total):
        L[i] += rumble[i] * 6
        R[i] += rumble[i] * 6
    L = loop_crossfade(L, n_samples(LOOP), fade)
    R = loop_crossfade(R, n_samples(LOOP), fade)
    m = Mix(LOOP)
    m.L, m.R = L, R
    # Rising noise swell into each chord change.
    for k in range(4):
        n = n_samples(BAR * 2)
        cut = [200 + 5000 * (i / n) ** 3 for i in range(n)]
        sw = mul(biquad(noise(n), "lp", 0, 1.5, cut), [(i / n) ** 2 for i in range(n)])
        m.add((k * 4 + 2) * BAR, sw, 0.35, -0.4 + 0.8 * (k % 2))
    m.normalize(0.85)
    return m


def stem_percussion():
    m = Mix(LOOP)
    tk = taiko()
    tk_hi = taiko(0.6, 95)
    lo, mid = tom(85), tom(120)
    cl = clank()
    for bar in range(BARS):
        t = bar * BAR
        m.add(t, tk, 0.9)
        m.add(t + 3 * SIXTEENTH, tk, 0.5)
        m.add(t + 2 * BEAT + 2 * SIXTEENTH, tk_hi, 0.6, 0.3)
        m.add(t + BEAT, cl, 0.5, -0.5)
        m.add(t + 3 * BEAT, cl, 0.5, 0.5)
        for s in range(16):
            m.add(t + s * SIXTEENTH, shaker(), 0.25 if s % 2 else 0.12, 0.6)
        if bar % 4 == 3:  # tom fill into the next phrase
            for s, tm in zip(range(8, 16), [mid, mid, lo, mid, lo, lo, mid, lo]):
                m.add(t + s * SIXTEENTH, tm, 0.7, 0.4 if tm is mid else -0.4)
        if bar % 2 == 1:
            m.add(t + 2 * BEAT, tk, 0.6)
    m.normalize(0.85)
    return m


def stem_riff():
    m = Mix(LOOP)
    k, sn, cr = kick(), snare(), crash()
    cache = {}

    def gtr(midi, dur, mute):
        key = (midi, round(dur, 3), mute)
        if key not in cache:
            cache[key] = guitar(midi, dur, mute)
        return cache[key]

    for bar in range(BARS):
        t = bar * BAR
        root = chord_at(bar)[0]
        pattern = RIFF[bar % 4]
        for s, c in enumerate(pattern):
            if c == ".":
                continue
            ts = t + s * SIXTEENTH
            if c == "A":
                note, mute, dur = root, False, SIXTEENTH * 2.5
            else:
                note = root + {"x": 0, "b": 1, "t": 6}[c]
                mute, dur = True, SIXTEENTH * 0.95
            g = gtr(note, dur, mute)
            # Double-tracked: two takes panned apart, slightly late on the right.
            m.add(ts, g, 0.45, -0.7)
            m.add(ts + 0.006, g, 0.45, 0.7)
            m.add(ts, k, 0.7)
        m.add(t + 2 * BEAT, sn, 0.75, 0.1)  # half-time snare on 3
        if bar % 4 == 0:
            m.add(t, cr, 0.4, -0.3)
        if bar % 4 == 3:
            m.add(t + 3 * BEAT, sn, 0.5)
            m.add(t + 3 * BEAT + 2 * SIXTEENTH, sn, 0.6)
    m.normalize(0.85)
    return m


def stem_choir():
    m = Mix(LOOP)
    for k in range(4):
        root, voicing, ost = CHORDS[k]
        m.add(k * 4 * BAR, choir_chord(voicing, 4 * BAR + 0.6), 0.5)
        # Brass stabs on the downbeat and a syncopated push.
        m.add(k * 4 * BAR, brass_stab([root, root + 7, root + 12]), 0.35)
        m.add((k * 4 + 3) * BAR + 2.5 * BEAT, brass_stab([root + 1, root + 8, root + 13], 0.35), 0.3)
        # Frantic string ostinato in sixteenths, two violins panned apart.
        notes = {}
        for bar in range(4):
            for s in range(16):
                midi = ost[s % 4]
                if midi not in notes:
                    notes[midi] = string_note(midi, SIXTEENTH * 1.1)
                t = (k * 4 + bar) * BAR + s * SIXTEENTH
                accent = 1.0 if s % 4 == 0 else 0.6
                m.add(t, notes[midi], 0.16 * accent, -0.6)
                m.add(t + 0.004, notes[midi], 0.12 * accent, 0.6)
    m.normalize(0.85)
    return m


# ---------------------------------------------------------------------------
# Ambience and effects
# ---------------------------------------------------------------------------

def heartbeat():
    m = Mix(1.0, stereo=False)
    for t, g in ((0.0, 1.0), (0.26, 0.7)):
        n = n_samples(0.25)
        beat = mul(sweep_sine(70, 38, n, 8), env_ad(n, 0.004, 0.06))
        m.add(t, onepole_lp(beat, 200), g)
    m.normalize(0.9)
    return m


def creak(dur=1.2, base=180):
    """Stick-slip: a resonator excited by irregular pulses."""
    n = n_samples(dur)
    x = [0.0] * n
    p = 0.0
    for i in range(n):
        t = i / n
        rate = base * (1 + 0.6 * math.sin(TAU * 0.7 * t) + rng.uniform(-0.3, 0.3))
        p += rate / SR
        if p >= 1.0:
            p -= 1.0
            x[i] = rng.uniform(0.5, 1.0)
    y = add(biquad(x, "bp", 700, 6), scale(biquad(x, "bp", 1500, 8), 0.6))
    return mul(drive(y, 3), env_asr(n, 0.1, 0.3))


def drip():
    n = n_samples(0.15)
    return mul(sweep_sine(2400, 900, n, 5), env_ad(n, 0.001, 0.03))


def ambience_building():
    dur = 20.0
    fade = n_samples(1.0)
    total = n_samples(dur) + fade
    hum = add(sine(50, total), scale(sine(100, total), 0.5), scale(sine(150.5, total), 0.15))
    air = onepole_lp(onepole_lp(noise(total), 400), 400)
    base = [h * 0.05 + a * 1.2 for h, a in zip(hum, air)]
    m = Mix(dur, stereo=False)
    m.L = loop_crossfade(base, n_samples(dur), fade)
    for t in (2.5, 9.0, 15.5):
        m.add(t + rng.uniform(-0.5, 0.5), creak(rng.uniform(0.8, 1.6), rng.uniform(120, 260)), 0.25)
    for _ in range(9):
        m.add(rng.uniform(0, dur), drip(), 0.2)
    m.add(12.0, clank(), 0.1)
    m.normalize(0.6)
    return m


def ambience_jungle():
    dur = 20.0
    fade = n_samples(1.0)
    total = n_samples(dur) + fade
    wind = biquad(noise(total), "lp", 500, 0.7)
    lfo = [0.6 + 0.4 * math.sin(TAU * 0.07 * i / SR) for i in range(total)]
    base = [w * l * 0.5 for w, l in zip(wind, lfo)]
    m = Mix(dur)
    m.L = loop_crossfade(base, n_samples(dur), fade)
    m.R = list(m.L)
    # Crickets: short bursts of a high tone, each insect with its own rhythm.
    for _ in range(7):
        f = rng.uniform(4200, 5600)
        pan = rng.uniform(-0.9, 0.9)
        chirp_n = n_samples(0.018)
        chirp = mul(sine(f, chirp_n), env_ad(chirp_n, 0.002, 0.006))
        t = rng.uniform(0, 1)
        period = rng.uniform(0.45, 0.9)
        pulses = rng.choice([2, 3, 4])
        g = rng.uniform(0.05, 0.12)
        while t < dur:
            for p in range(pulses):
                m.add(t + p * 0.032, chirp, g, pan)
            t += period * rng.uniform(0.9, 1.1)
    # Frogs: low, throaty croaks.
    for _ in range(10):
        n = n_samples(rng.uniform(0.18, 0.3))
        f = rng.uniform(140, 260)
        x = biquad(saw(f, n), "bp", f * 3, 3)
        am = [0.5 + 0.5 * math.sin(TAU * 28 * i / SR) for i in range(n)]
        m.add(rng.uniform(0, dur), mul(mul(x, am), env_asr(n, 0.02, 0.08)), 0.12, rng.uniform(-0.8, 0.8))
    # A distant night bird.
    for t in (6.0, 14.5):
        n = n_samples(0.5)
        call = mul(sweep_sine(1900, 1300, n, 3), env_asr(n, 0.05, 0.2))
        m.add(t, call, 0.05, 0.7)
        m.add(t + 0.6, call, 0.04, 0.7)
    m.normalize(0.6)
    return m


def water_loop():
    dur = 6.0
    fade = n_samples(1.0)
    total = n_samples(dur) + fade
    a = biquad(noise(total), "lp", 1800, 0.5)
    b = onepole_hp(a, 200)
    m = Mix(dur, stereo=False)
    m.L = loop_crossfade(b, n_samples(dur), fade)
    m.normalize(0.7)
    return m


def roar():
    dur = 1.8
    n = n_samples(dur)
    x = [0.0] * n
    p = 0.0
    for i in range(n):
        t = i / n
        f = 85 - 35 * t + 6 * math.sin(TAU * 7 * i / SR)
        p += f / SR
        p -= int(p)
        x[i] = (2 * p - 1) * (0.6 + 0.4 * math.sin(TAU * 31 * i / SR))
    breath = biquad(noise(n), "bp", 900, 0.8)
    y = add(drive(onepole_lp(x, 1200), 4.0), scale(breath, 0.5))
    y = add(y, scale(biquad(y, "bp", 420, 4), 1.5))
    return mul(y, env_asr(n, 0.08, 0.9))


def screech():
    dur = 1.1
    n = n_samples(dur)
    x = [0.0] * n
    p = 0.0
    for i in range(n):
        t = i / n
        f = 1400 + 900 * math.sin(math.pi * t) + 120 * math.sin(TAU * 40 * i / SR)
        p += f / SR
        p -= int(p)
        x[i] = 2 * p - 1
    y = add(biquad(x, "bp", 2400, 2), scale(biquad(noise(n), "bp", 3200, 1), 0.6))
    return mul(drive(y, 3), env_asr(n, 0.02, 0.5))


def footstep():
    n = n_samples(0.35)
    thud = mul(sweep_sine(90, 40, n, 10), env_ad(n, 0.002, 0.07))
    grit = mul(onepole_lp(noise(n), 1200), env_ad(n, 0.001, 0.03))
    return drive(add(thud, scale(grit, 0.4)), 1.5)


def wood_hit(dur=0.6, bright=1.0):
    n = n_samples(dur)
    body = mul(sweep_sine(160, 90, n, 10), env_ad(n, 0.001, 0.09))
    crack = mul(biquad(noise(n), "bp", 1100 * bright, 1.2), env_ad(n, 0.0005, 0.05))
    ring = mul(add(sine(310, n), scale(sine(457, n), 0.6)), env_ad(n, 0.001, 0.12))
    return drive(add(body, crack, scale(ring, 0.3)), 2.0)


def door_break():
    m = Mix(1.6, stereo=False)
    m.add(0.0, wood_hit(0.8, 1.4), 1.0, wrap=False)
    for _ in range(9):
        n = n_samples(rng.uniform(0.05, 0.15))
        sp = mul(biquad(noise(n), "bp", rng.uniform(1500, 4000), 2), env_ad(n, 0.001, 0.03))
        m.add(rng.uniform(0.02, 0.9), sp, rng.uniform(0.2, 0.5), wrap=False)
    m.add(0.5, wood_hit(0.6, 0.7), 0.5, wrap=False)
    m.normalize(0.9)
    return m


def click():
    n = n_samples(0.05)
    return mul(biquad(noise(n), "bp", 3500, 3), env_ad(n, 0.0005, 0.006))


def pickup():
    m = Mix(0.5, stereo=False)
    for k, midi in enumerate((76, 81, 88)):
        n = n_samples(0.3)
        m.add(k * 0.06, mul(sine(mtof(midi), n), env_ad(n, 0.003, 0.08)), 0.4, wrap=False)
    return m


def death():
    n = n_samples(2.5)
    boom = mul(sweep_sine(70, 28, n, 4), env_ad(n, 0.005, 0.6))
    ring = mul(add(sine(mtof(74), n), sine(mtof(75), n)), env_ad(n, 0.3, 0.8))
    return add(drive(boom, 2.5), scale(ring, 0.15))


def stinger():
    m = Mix(2.5)
    m.add(0.0, taiko(1.2, 50), 0.9, wrap=False)
    m.add(0.0, brass_stab([38, 45, 50, 51], 1.2), 0.6, wrap=False)
    m.add(0.0, choir_chord([50, 51, 57], 2.2), 0.4, wrap=False)
    m.add(0.0, crash(2.0), 0.4, wrap=False)
    m.normalize(0.9)
    return m


def rope_snap():
    n = n_samples(0.5)
    whip = mul(biquad(noise(n), "hp", 2500, 0.7), env_ad(n, 0.0005, 0.03))
    twang = mul(sweep_sine(500, 150, n, 6), env_ad(n, 0.001, 0.12))
    return add(scale(whip, 1.2), scale(twang, 0.5))


def bridge_collapse():
    m = Mix(3.0, stereo=False)
    m.add(0.0, rope_snap(), 1.0, wrap=False)
    m.add(0.15, rope_snap(), 0.9, wrap=False)
    for _ in range(14):
        m.add(rng.uniform(0.2, 2.2), wood_hit(0.4, rng.uniform(0.6, 1.4)), rng.uniform(0.15, 0.45), wrap=False)
    n = n_samples(2.5)
    rumble = mul(onepole_lp(noise(n), 300), env_asr(n, 0.2, 1.5))
    m.add(0.2, rumble, 1.5, wrap=False)
    m.normalize(0.9)
    return m


def rustle():
    n = n_samples(0.7)
    x = biquad(noise(n), "bp", 2800, 0.6)
    am = [abs(math.sin(TAU * rng.uniform(9, 11) * i / SR)) ** 2 for i in range(n)]
    return mul(mul(x, am), env_asr(n, 0.05, 0.35))


def whoosh():
    n = n_samples(1.2)
    cut = [300 + 2500 * math.sin(math.pi * i / n) for i in range(n)]
    x = biquad(noise(n), "bp", 0, 2, cut)
    low = mul(sweep_sine(120, 50, n, 3), env_asr(n, 0.3, 0.6))
    return add(mul(x, env_asr(n, 0.4, 0.6)), scale(low, 0.5))


def mono(samples, peak=0.9):
    m = Mix(len(samples) / SR + 0.01, stereo=False)
    m.add(0, samples, 1.0, wrap=False)
    m.normalize(peak)
    return m


def main():
    music = os.path.join(OUT, "music")
    amb = os.path.join(OUT, "ambience")
    sfx = os.path.join(OUT, "sfx")
    stem_drone().save(os.path.join(music, "chase_drone.wav"))
    stem_percussion().save(os.path.join(music, "chase_percussion.wav"))
    stem_riff().save(os.path.join(music, "chase_riff.wav"))
    stem_choir().save(os.path.join(music, "chase_choir.wav"))
    heartbeat().save(os.path.join(music, "heartbeat.wav"))
    ambience_building().save(os.path.join(amb, "building.wav"))
    ambience_jungle().save(os.path.join(amb, "jungle.wav"))
    water_loop().save(os.path.join(amb, "water.wav"))
    for name, gen in [
        ("roar", roar), ("screech", screech), ("footstep", footstep),
        ("bash", lambda: wood_hit(0.6, 1.0)), ("door_slam", lambda: wood_hit(0.7, 0.8)),
        ("creak", lambda: creak(1.4, 140)), ("click", click), ("death", death),
        ("rope_snap", rope_snap), ("rustle", rustle), ("whoosh", whoosh),
    ]:
        mono(gen()).save(os.path.join(sfx, name + ".wav"))
    door_break().save(os.path.join(sfx, "door_break.wav"))
    pickup().save(os.path.join(sfx, "pickup.wav"))
    stinger().save(os.path.join(sfx, "stinger.wav"))
    bridge_collapse().save(os.path.join(sfx, "bridge_collapse.wav"))


if __name__ == "__main__":
    main()
