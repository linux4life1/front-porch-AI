/**
 * In-process emotional voice DSP — browser port of
 * lib/services/emotional_voice_dsp.dart.
 *
 * Pure TypeScript STFT-domain audio effects using Float32Array.
 * Zero external dependencies.
 */

import { EMOTION_PROFILES, NEUTRAL_PROFILE } from './emotionalVoiceProfiles';

const NFFT = 1024;
const HOP = 256;
const BINS = NFFT / 2 + 1;
const PEAK = 0.95;

// ── FFT (radix-2, decimation-in-time, in-place) ──────────────────

function fft(re: Float32Array, im: Float32Array): void {
  const n = re.length;
  let j = 0;
  for (let i = 0; i < n - 1; i++) {
    if (i < j) {
      let t = re[i]; re[i] = re[j]; re[j] = t;
      t = im[i]; im[i] = im[j]; im[j] = t;
    }
    let k = n >> 1;
    while (k <= j) { j -= k; k >>= 1; }
    j += k;
  }
  for (let len = 2; len <= n; len <<= 1) {
    const half = len >> 1;
    const ang = -2 * Math.PI / len;
    for (let i = 0; i < n; i += len) {
      for (let k = 0; k < half; k++) {
        const wr = Math.cos(ang * k);
        const wi = Math.sin(ang * k);
        const tr = re[i + k + half] * wr - im[i + k + half] * wi;
        const ti = re[i + k + half] * wi + im[i + k + half] * wr;
        re[i + k + half] = re[i + k] - tr;
        im[i + k + half] = im[i + k] - ti;
        re[i + k] += tr;
        im[i + k] += ti;
      }
    }
  }
}

function ifft(re: Float32Array, im: Float32Array): void {
  const n = re.length;
  for (let i = 0; i < n; i++) im[i] = -im[i];
  fft(re, im);
  for (let i = 0; i < n; i++) {
    re[i] /= n;
    im[i] = -im[i] / n;
  }
}

// ── Hann window ──────────────────────────────────────────────────

function hann(size: number): Float32Array {
  const w = new Float32Array(size);
  for (let i = 0; i < size; i++) {
    w[i] = 0.5 * (1 - Math.cos(2 * Math.PI * i / (size - 1)));
  }
  return w;
}

// ── STFT ─────────────────────────────────────────────────────────

function stft(samples: Float32Array): { mag: Float32Array; phase: Float32Array; numFrames: number } {
  const window = hann(NFFT);
  const numFrames = Math.floor((samples.length - NFFT) / HOP) + 1;
  if (numFrames <= 0) return { mag: new Float32Array(0), phase: new Float32Array(0), numFrames: 0 };

  const mag = new Float32Array(numFrames * BINS);
  const phase = new Float32Array(numFrames * BINS);
  const re = new Float32Array(NFFT);
  const im = new Float32Array(NFFT);

  for (let t = 0; t < numFrames; t++) {
    const off = t * HOP;
    for (let i = 0; i < NFFT; i++) {
      re[i] = (off + i < samples.length ? samples[off + i] : 0) * window[i];
      im[i] = 0;
    }
    fft(re, im);
    for (let b = 0; b < BINS; b++) {
      mag[t * BINS + b] = Math.sqrt(re[b] * re[b] + im[b] * im[b]);
      phase[t * BINS + b] = Math.atan2(im[b], re[b]);
    }
  }
  return { mag, phase, numFrames };
}

// ── ISTFT (overlap-add with Hann windows) ────────────────────────

function istft(mag: Float32Array, phase: Float32Array, numFrames: number): Float32Array {
  const window = hann(NFFT);
  const outLen = (numFrames - 1) * HOP + NFFT;
  const out = new Float32Array(outLen);
  const sumWin = new Float32Array(outLen);
  const re = new Float32Array(NFFT);
  const im = new Float32Array(NFFT);

  for (let t = 0; t < numFrames; t++) {
    for (let b = 0; b < BINS; b++) {
      const m = mag[t * BINS + b];
      const p = phase[t * BINS + b];
      re[b] = m * Math.cos(p);
      im[b] = m * Math.sin(p);
    }
    for (let b = 1; b < BINS - 1; b++) {
      const m = mag[t * BINS + b];
      const p = phase[t * BINS + b];
      re[NFFT - b] = m * Math.cos(p);
      im[NFFT - b] = -m * Math.sin(p);
    }
    ifft(re, im);
    const off = t * HOP;
    for (let i = 0; i < NFFT; i++) {
      out[off + i] += re[i] * window[i];
      sumWin[off + i] += window[i] * window[i];
    }
  }
  for (let i = 0; i < outLen; i++) {
    if (sumWin[i] > 1e-10) out[i] /= sumWin[i];
  }
  return out;
}

// ── DSP effects ──────────────────────────────────────────────────

function pitchShift(mag: Float32Array, semitones: number): Float32Array {
  const shift = Math.pow(2.0, semitones / 12.0);
  const nf = mag.length / BINS;
  const out = new Float32Array(mag.length);
  for (let t = 0; t < nf; t++) {
    const off = t * BINS;
    for (let b = 0; b < BINS; b++) {
      const src = Math.round(b / shift);
      out[off + b] = (src >= 0 && src < BINS) ? mag[off + src] : 0;
    }
  }
  return out;
}

function applyPitchVariance(mag: Float32Array, scale: number): Float32Array {
  const nf = mag.length / BINS;
  const out = new Float32Array(mag.length);
  for (let t = 0; t < nf; t++) {
    const off = t * BINS;
    let energy = 0;
    for (let b = 0; b < BINS; b++) energy += Math.abs(mag[off + b]);
    energy = energy / BINS;
    const mod = 1.0 + (scale - 1.0) * energy;
    for (let b = 0; b < BINS; b++) out[off + b] = mag[off + b] * mod;
  }
  return out;
}

function applyBrightness(mag: Float32Array, db: number, sampleRate: number): Float32Array {
  const nf = mag.length / BINS;
  const nyquist = sampleRate / 2.0;
  const gain = new Float32Array(BINS);
  for (let b = 0; b < BINS; b++) {
    const frac = (b * nyquist / (BINS - 1)) / nyquist;
    gain[b] = Math.pow(10.0, db * frac / 20.0);
  }
  const out = new Float32Array(mag.length);
  for (let t = 0; t < nf; t++) {
    const off = t * BINS;
    for (let b = 0; b < BINS; b++) out[off + b] = mag[off + b] * gain[b];
  }
  return out;
}

function applyTension(mag: Float32Array, amount: number): Float32Array {
  const nf = mag.length / BINS;
  const out = new Float32Array(mag.length);
  for (let t = 0; t < nf; t++) {
    const off = t * BINS;
    const smooth = new Float32Array(BINS);
    for (let b = 2; b < BINS - 2; b++) {
      smooth[b] = (mag[off + b - 2] + mag[off + b - 1] + mag[off + b] +
        mag[off + b + 1] + mag[off + b + 2]) / 5.0;
    }
    smooth[0] = mag[off];
    smooth[1] = BINS > 1 ? mag[off + 1] : 0;
    if (BINS > 2) smooth[BINS - 2] = mag[off + BINS - 2];
    if (BINS > 1) smooth[BINS - 1] = mag[off + BINS - 1];
    for (let b = 0; b < BINS; b++) {
      const diff = mag[off + b] - smooth[b];
      out[off + b] = smooth[b] + diff * (1.0 + amount);
    }
  }
  return out;
}

function applyBreathiness(mag: Float32Array, amount: number): Float32Array {
  const nf = mag.length / BINS;
  const lowBin = Math.floor(BINS / 4);
  // Seeded PRNG (Mulberry32) matching Dart's Random(42)
  let seed = 42;
  const nextRandom = (): number => {
    seed |= 0; seed = seed + 0x6D2B79F5 | 0;
    let t = Math.imul(seed ^ seed >>> 15, 1 | seed);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
  const out = new Float32Array(mag.length);
  for (let t = 0; t < nf; t++) {
    const off = t * BINS;
    let energy = 0;
    for (let b = lowBin; b < BINS; b++) energy += Math.abs(mag[off + b]);
    energy = (energy / (BINS - lowBin)) * amount;
    for (let b = 0; b < BINS; b++) {
      if (b < lowBin) {
        out[off + b] = mag[off + b];
      } else {
        out[off + b] = mag[off + b] + (nextRandom() * 2 - 1) * energy;
      }
    }
  }
  return out;
}

function timeStretch(
  mag: Float32Array, phase: Float32Array, numFrames: number, ratio: number,
): { mag: Float32Array; phase: Float32Array; numFrames: number } {
  const newFrames = Math.round(numFrames / ratio);
  if (newFrames < 1) return { mag, phase, numFrames };
  const outMag = new Float32Array(newFrames * BINS);
  const outPhase = new Float32Array(newFrames * BINS);
  for (let t = 0; t < newFrames; t++) {
    const src = Math.floor(t * ratio);
    const frac = (t * ratio) - src;
    const nxt = Math.min(src + 1, numFrames - 1);
    const clp = Math.max(src, 0);
    for (let b = 0; b < BINS; b++) {
      const m1 = mag[clp * BINS + b];
      const m2 = mag[nxt * BINS + b];
      outMag[t * BINS + b] = m1 + (m2 - m1) * frac;
      outPhase[t * BINS + b] = phase[clp * BINS + b];
    }
  }
  return { mag: outMag, phase: outPhase, numFrames: newFrames };
}

// ── Main pipeline ────────────────────────────────────────────────

function processSamples(
  samples: Float32Array, sampleRate: number, profile: readonly number[],
): Float32Array {
  const pitchSt = profile[0];
  const pitchVar = profile[1];
  const brightnessDb = profile[2];
  const tension = profile[3];
  const breathiness = profile[4];
  const speedRatio = profile[5];

  const { mag, phase, numFrames } = stft(samples);
  if (numFrames === 0) return samples;

  let m = mag;
  let p = phase;
  let nf = numFrames;

  if (Math.abs(pitchSt) >= 0.5) m = pitchShift(m, pitchSt);
  if (pitchVar !== 1.0) m = applyPitchVariance(m, pitchVar);
  if (brightnessDb !== 0.0) m = applyBrightness(m, brightnessDb, sampleRate);
  if (tension > 0.0) m = applyTension(m, tension);
  if (breathiness > 0.0) m = applyBreathiness(m, breathiness);
  if (speedRatio !== 1.0) {
    const s = timeStretch(m, p, nf, speedRatio);
    m = s.mag; p = s.phase; nf = s.numFrames;
  }

  const result = istft(m, p, nf);

  // Peak normalize
  let maxVal = 0;
  for (const s of result) { if (Math.abs(s) > maxVal) maxVal = Math.abs(s); }
  if (maxVal > 0) {
    const scale = PEAK / maxVal;
    for (let i = 0; i < result.length; i++) result[i] *= scale;
  }
  return result;
}

// ── Public API ───────────────────────────────────────────────────

/** Process mono samples with the given emotion. Returns new Float32Array. */
export function emotionalVoiceDsp(
  samples: Float32Array, sampleRate: number, emotion: string,
): Float32Array {
  const profile = EMOTION_PROFILES[emotion] ?? NEUTRAL_PROFILE;
  return processSamples(samples, sampleRate, profile);
}
