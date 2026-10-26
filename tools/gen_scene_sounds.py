#!/usr/bin/env python3
# Copyright (C) 2026 Front Porch AI
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# This file is part of Front Porch AI.
#
# Front Porch AI is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Front Porch AI is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.
"""Synthesises the Ambient Stage's scene sounds (docs/design/ambient-stage.md §5).

Every sound is made here from seeded noise and sine waves; nothing is
downloaded or sampled, so the set carries no third-party material and the
project dedicates it to the public domain (assets/audio/scene/LICENSE.md).

    python3 tools/gen_scene_sounds.py            # writes assets/audio/scene/*.mp3
    python3 tools/gen_scene_sounds.py --out DIR  # somewhere else

Needs numpy and an ffmpeg with libmp3lame on PATH. Mono, 22.05 kHz, 40 kbps
CBR MP3: the one compressed format audioplayers plays on every desktop
(Windows Media Foundation has no Vorbis or Opus, macOS AVPlayer no Vorbis)
and every browser plays in <audio>. The same seed and the same ffmpeg give
the same files.

Loops are built a second longer than they play and the extra second is
crossfaded (equal power) over their start, so the last sample runs into
the first with no click. One-shots (thunder) fade to silence.
"""

import argparse
import io
import os
import subprocess
import sys
import wave

import numpy as np

SR = 22050
XFADE = 1.0  # seconds of overlap folded over a loop's start
BITRATE = '40k'
SEED = 20261026


def rng(name):
    """One generator per sound, so editing one sound never shifts another."""
    return np.random.default_rng([SEED, sum(ord(c) * 31 ** i for i, c in enumerate(name)) % (2 ** 32)])


def band(signal, low=None, high=None, order=2):
    """Butterworth-shaped band-pass by FFT magnitude (circular, zero phase)."""
    spec = np.fft.rfft(signal)
    f = np.fft.rfftfreq(len(signal), 1 / SR)
    gain = np.ones_like(f)
    if high:
        gain /= np.sqrt(1 + (f / high) ** (2 * order))
    if low:
        with np.errstate(divide='ignore'):
            gain /= np.sqrt(1 + (low / np.maximum(f, 1e-6)) ** (2 * order))
        gain[0] = 0
    return np.fft.irfft(spec * gain, len(signal))


def brown(r, n):
    """Brown (random-walk) noise with its drift taken out."""
    x = np.cumsum(r.standard_normal(n))
    x = band(x, low=25)
    return x / (np.max(np.abs(x)) + 1e-12)


def pink(r, n):
    """Pink noise: white noise with a 1/sqrt(f) slope."""
    spec = np.fft.rfft(r.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    spec[1:] /= np.sqrt(f[1:])
    spec[0] = 0
    x = np.fft.irfft(spec, n)
    return x / (np.max(np.abs(x)) + 1e-12)


def rms_to(x, dbfs):
    rms = np.sqrt(np.mean(x ** 2)) + 1e-12
    return x * (10 ** (dbfs / 20) / rms)


def peak_to(x, dbfs):
    return x * (10 ** (dbfs / 20) / (np.max(np.abs(x)) + 1e-12))


def seamless(build, seconds):
    """Builds [seconds + XFADE] of sound and folds the tail over the head."""
    n = int(seconds * SR)
    m = int(XFADE * SR)
    y = build(n + m)
    out = y[:n].copy()
    t = np.linspace(0, 1, m, endpoint=False)
    fade_in = np.sin(t * np.pi / 2)
    fade_out = np.cos(t * np.pi / 2)
    out[:m] = y[:m] * fade_in + y[n:n + m] * fade_out
    return out


def scatter(r, n, per_second, length, make):
    """Adds events at random times; each is make(r) -> samples."""
    out = np.zeros(n + length)
    count = r.poisson(per_second * n / SR)
    for start in r.integers(0, n, count):
        ev = make(r)
        out[start:start + len(ev)] += ev
    return out[:n]


def droplet(r, low=1800, high=5200):
    """A tiny decaying tone: one drop on a leaf or a sill."""
    dur = r.uniform(0.004, 0.018)
    k = int(dur * SR)
    t = np.arange(k) / SR
    f0 = r.uniform(low, high)
    env = np.exp(-t / (dur / 4))
    return np.sin(2 * np.pi * f0 * t * (1 - 0.3 * t / dur)) * env * r.uniform(0.1, 1.0)


def rain(n, heavy=False):
    r = rng('storm_rain' if heavy else 'rain')
    bed = pink(r, n)
    if heavy:
        bed = band(bed, low=120, high=3800)
        gust = 1 + 0.35 * np.sin(2 * np.pi * np.arange(n) / SR / 3.7 + r.uniform(0, 6))
        bed = bed * gust
        rumble = band(brown(r, n), high=140) * 0.9
        drops = scatter(r, n, 140, 600, lambda q: droplet(q, 900, 3200))
        mix = rms_to(bed, -21) + rms_to(rumble, -26) + rms_to(drops, -27)
        return rms_to(mix, -19)
    bed = band(bed, low=350, high=7000)
    drops = scatter(r, n, 70, 600, droplet)
    mix = rms_to(bed, -25) + rms_to(drops, -27)
    return rms_to(mix, -22)


def wind(n):
    r = rng('wind')
    t = np.arange(n) / SR
    white = r.standard_normal(n)
    low = band(white, low=180, high=520, order=3)
    high = band(white, low=480, high=1300, order=3)
    swell = 0.55 + 0.45 * np.sin(2 * np.pi * t / 6.1 + r.uniform(0, 6))
    whistle = 0.5 + 0.5 * np.sin(2 * np.pi * t / 3.9 + r.uniform(0, 6))
    mix = rms_to(low, -24) * swell + rms_to(high, -30) * swell * whistle
    return rms_to(mix, -23)


def chirp(r):
    """A short song: a few rising-then-falling sweeps in quick succession."""
    notes = r.integers(2, 6)
    base = r.uniform(2600, 4200)
    parts = []
    for _ in range(notes):
        dur = r.uniform(0.05, 0.11)
        k = int(dur * SR)
        t = np.arange(k) / SR
        sweep = base * (1 + r.uniform(0.15, 0.4) * np.sin(np.pi * t / dur))
        phase = 2 * np.pi * np.cumsum(sweep) / SR
        env = np.hanning(k)
        parts.append(np.sin(phase) * env)
        parts.append(np.zeros(int(r.uniform(0.02, 0.07) * SR)))
        base *= r.uniform(0.92, 1.08)
    return np.concatenate(parts) * r.uniform(0.3, 1.0)


def birds(n):
    r = rng('birds')
    song = scatter(r, n, 0.9, int(1.2 * SR), chirp)
    air = band(pink(r, n), low=300, high=3000)
    return peak_to(song, -11) + rms_to(air, -42)


def crickets(n):
    r = rng('crickets')
    t = np.arange(n) / SR
    out = np.zeros(n)
    # Two crickets at a slightly different pitch and pace, so they drift.
    for pitch, period, offset, level in ((4400, 0.62, 0.0, 1.0), (4750, 0.71, 0.27, 0.6)):
        pulses = np.zeros(n)
        start = offset
        while start < n / SR:
            for p in range(3):
                s = int((start + p * 0.035) * SR)
                k = int(0.022 * SR)
                if s + k < n:
                    pulses[s:s + k] += np.hanning(k)
            start += period * r.uniform(0.96, 1.04)
        out += np.sin(2 * np.pi * pitch * t) * pulses * level
    air = band(pink(r, n), low=200, high=2500)
    return peak_to(out, -14) + rms_to(air, -44)


def fog(n):
    r = rng('fog')
    t = np.arange(n) / SR
    drone = np.zeros(n)
    for f, a in ((55.0, 1.0), (82.6, 0.6), (110.3, 0.35)):
        drone += a * np.sin(2 * np.pi * f * t + r.uniform(0, 6))
    drone *= 0.7 + 0.3 * np.sin(2 * np.pi * t / 7.3)
    hush = band(brown(r, n), high=260)
    return rms_to(rms_to(drone, -32) + rms_to(hush, -33), -29)


def thunder(name, seconds):
    r = rng(name)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    noise = brown(r, n) + 0.25 * pink(r, n)
    attack = r.uniform(0.03, 0.09)
    env = np.minimum(t / attack, 1) * np.exp(-t / (seconds / 4.2))
    # A few later rolls, as the sound comes back off the hills.
    for _ in range(r.integers(2, 4)):
        at = r.uniform(0.25, seconds * 0.55)
        env += 0.55 * np.exp(-np.maximum(t - at, 0) / 0.5) * (t >= at) * np.exp(-at / seconds)
    # The lowpass closes as it decays: bright crack, then a low roll.
    cutoff = 90 + 2200 * np.exp(-t / (seconds / 6))
    a = np.exp(-2 * np.pi * cutoff / SR)
    x = noise * env
    y = np.zeros(n)
    acc = 0.0
    for i in range(n):
        acc = (1 - a[i]) * x[i] + a[i] * acc
        y[i] = acc
    tail = int(0.4 * SR)
    y[-tail:] *= np.linspace(1, 0, tail)
    return peak_to(y, -3)


LOOPS = {
    'rain': (9.0, lambda n: rain(n)),
    'storm_rain': (9.0, lambda n: rain(n, heavy=True)),
    'wind': (12.0, wind),
    'birds': (10.0, birds),
    'crickets': (8.0, crickets),
    'fog': (12.0, fog),
}
ONE_SHOTS = {'thunder_1': 3.4, 'thunder_2': 4.1, 'thunder_3': 4.8}


def wav_bytes(x):
    pcm = np.clip(x, -1, 1)
    data = (pcm * 32767).astype('<i2').tobytes()
    buf = io.BytesIO()
    with wave.open(buf, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    return buf.getvalue()


def encode(x, path):
    cmd = [
        'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
        '-f', 'wav', '-i', 'pipe:0',
        '-ac', '1', '-ar', str(SR), '-c:a', 'libmp3lame', '-b:a', BITRATE,
        '-map_metadata', '-1', '-fflags', '+bitexact', '-flags:a', '+bitexact',
        path,
    ]
    subprocess.run(cmd, input=wav_bytes(x), check=True)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--out', default=os.path.join(here, '..', 'assets', 'audio', 'scene'))
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    total = 0
    for name, (seconds, build) in LOOPS.items():
        path = os.path.join(args.out, name + '.mp3')
        encode(seamless(build, seconds), path)
        total += os.path.getsize(path)
        print(f'{name}.mp3  {seconds:.1f} s loop  {os.path.getsize(path)} bytes')
    for name, seconds in ONE_SHOTS.items():
        path = os.path.join(args.out, name + '.mp3')
        encode(thunder(name, seconds), path)
        total += os.path.getsize(path)
        print(f'{name}.mp3  {seconds:.1f} s one-shot  {os.path.getsize(path)} bytes')
    print(f'total {total} bytes')
    return 0


if __name__ == '__main__':
    sys.exit(main())
