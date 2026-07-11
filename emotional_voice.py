"""
EmotionalVoice — STFT-based emotional voice conversion for Front Porch AI.

Modifies speech spectrogram + pitch contour + timing based on emotion label.
Uses only numpy + scipy (both already present from Kokoro's dependencies).

Protocol (JSON lines over stdin/stdout):
  Request:  {"id": 42, "audio_path": "/tmp/input.wav", "emotion": "joy",
             "output_path": "/tmp/output.wav"}
  Success:  {"id": 42, "ok": true}
  Error:    {"id": 42, "error": "..."}
"""

import json
import sys
import traceback

import numpy as np
import soundfile as sf

HAS_SCIPY = False
try:
    import scipy.signal as signal
    from scipy.ndimage import gaussian_filter1d
    HAS_SCIPY = True
except ImportError:
    pass


# ── Emotion → parameter profiles ──
# Each profile: (pitch_shift_semitones, pitch_variance_scale, brightness_db,
#                tension_scale, breathiness, speed_ratio)
# pitch_variance_scale: 0=monotone, 1=unchanged, >1=more expressive
# breathiness: 0=clear, >0=breathy (aperiodic noise mix)
PROFILES = {
    "admiration":     ( 1.5,  1.3,  2.0, 0.2, 0.10, 1.00),
    "amusement":      ( 3.0,  1.6,  3.0, 0.0, 0.00, 1.08),
    "anger":          ( 2.0,  1.8,  6.0, 0.5, 0.00, 1.10),
    "annoyance":      ( 1.0,  1.3,  3.0, 0.3, 0.00, 1.05),
    "approval":       ( 0.5,  1.1,  1.5, 0.1, 0.00, 1.00),
    "caring":         (-1.0,  0.8, -1.0, 0.1, 0.20, 0.95),
    "confusion":      ( 0.0,  1.2,  0.0, 0.1, 0.08, 0.98),
    "curiosity":      ( 2.0,  1.4,  1.0, 0.0, 0.00, 1.03),
    "desire":         (-1.5,  0.7, -2.0, 0.2, 0.30, 0.90),
    "disappointment": (-2.0,  0.6, -3.0, 0.1, 0.20, 0.92),
    "disgust":        (-0.5,  0.9,  0.0, 0.3, 0.05, 0.95),
    "embarrassment":  (-2.0,  0.7, -1.0, 0.0, 0.20, 0.93),
    "excitement":     ( 4.0,  1.8,  5.0, 0.0, 0.00, 1.12),
    "fear":           ( 3.0,  1.5,  1.0, 0.2, 0.20, 1.06),
    "gratitude":      ( 1.0,  1.1,  1.0, 0.1, 0.10, 0.98),
    "grief":          (-4.0,  0.4, -4.0, 0.0, 0.30, 0.85),
    "joy":            ( 3.0,  1.6,  4.0, 0.0, 0.00, 1.08),
    "love":           (-1.5,  0.6, -1.0, 0.2, 0.30, 0.88),
    "nervousness":    ( 2.0,  1.3,  0.0, 0.2, 0.15, 1.04),
    "optimism":       ( 1.5,  1.3,  2.0, 0.0, 0.00, 1.03),
    "pride":          ( 2.0,  1.4,  3.0, 0.1, 0.00, 1.03),
    "realization":    ( 2.5,  1.5,  1.0, 0.0, 0.00, 1.00),
    "relief":         (-0.5,  0.9,  0.0, 0.0, 0.15, 0.97),
    "remorse":        (-3.0,  0.5, -2.0, 0.1, 0.25, 0.88),
    "sadness":        (-4.0,  0.4, -5.0, 0.0, 0.35, 0.82),
    "surprise":       ( 5.0,  1.8,  5.0, 0.2, 0.00, 1.08),
    "neutral":        ( 0.0,  1.0,  0.0, 0.0, 0.00, 1.00),
}


def _modify_speech(data: np.ndarray, sr: int, profile: tuple) -> np.ndarray:
    """Apply emotion profile to speech using STFT + pitch manipulation."""
    pitch_st, pitch_var, bright_db, tension, breath, speed = profile

    if not HAS_SCIPY:
        # No scipy — crude resample-only fallback
        ratio = 2.0 ** (pitch_st / 12.0) * speed
        if abs(ratio - 1.0) < 0.02:
            return data
        new_len = int(len(data) / ratio)
        stretched = np.interp(
            np.linspace(0, len(data), new_len),
            np.arange(len(data)),
            data,
        )
        return stretched.astype(np.float32)

    # STFT parameters
    n_fft = 2048
    hop = 512
    win = np.hanning(n_fft)

    # Analysis
    f, t, Zxx = signal.stft(data, fs=sr, window=win, nperseg=n_fft,
                             noverlap=n_fft - hop)
    mag = np.abs(Zxx)
    phase = np.angle(Zxx)

    # ── Pitch modification via frequency bin shift ──
    if abs(pitch_st) >= 0.5:
        shift_bins = int(round(pitch_st / 12.0 * mag.shape[0] / 2))
        if shift_bins > 0:
            mag = np.roll(mag, shift_bins, axis=0)
            mag[:shift_bins] = 0
        elif shift_bins < 0:
            mag = np.roll(mag, shift_bins, axis=0)
            mag[shift_bins:] = 0

    # ── Pitch variance (expressiveness) via spectral centroid modulation ──
    if abs(pitch_var - 1.0) > 0.05:
        # Modulate higher-frequency content frame by frame based on energy
        frame_energy = np.sum(mag, axis=0)
        energy_norm = frame_energy / (np.max(frame_energy) + 1e-10)
        # Raise/lower the dynamic range of spectral tilt per frame
        modulation = 1.0 + (energy_norm - 0.5) * (pitch_var - 1.0) * 2
        for i in range(mag.shape[1]):
            freq_axis = np.arange(mag.shape[0]) / mag.shape[0]
            tilt = 1.0 + (freq_axis - 0.5) * (modulation[i] - 1.0) * 2
            mag[:, i] = np.clip(mag[:, i] * tilt, 0, None)

    # ── Brightness (spectral tilt) ──
    if abs(bright_db) >= 0.5:
        n_freq = mag.shape[0]
        tilt_linear = 10.0 ** (bright_db / 20.0)
        freq_weights = np.linspace(1.0, tilt_linear, n_freq)
        mag = mag * freq_weights[:, np.newaxis]

    # ── Tension (emphasize formant peaks) ──
    if tension > 0.05:
        # Smooth across frequency to get spectral envelope
        smoothed = mag.copy()
        for i in range(mag.shape[1]):
            smoothed[:, i] = np.convolve(mag[:, i],
                                          np.ones(5) / 5, mode='same')
        mag = mag + (mag - smoothed) * tension
        mag = np.clip(mag, 1e-10, None)

    # ── Breathiness (add noise to upper frequencies) ──
    if breath > 0.01:
        noise = np.random.randn(*mag.shape) * breath * np.max(mag) * 0.05
        # Add noise only to upper half of frequencies
        noise[:mag.shape[0] // 4] = 0
        mag = mag + np.abs(noise)

    # ── Speed change via resampling time axis ──
    if abs(speed - 1.0) > 0.02:
        n_t = mag.shape[1]
        new_n = max(1, int(n_t / speed))
        old_idx = np.arange(n_t)
        new_idx = np.linspace(0, n_t - 1, new_n)
        mag = np.array([np.interp(new_idx, old_idx, mag[i, :])
                        for i in range(mag.shape[0])])
        # Also resample phase, then reconstruct
        phase = np.array([np.interp(new_idx, old_idx, phase[i, :])
                          for i in range(phase.shape[0])])

    # Synthesis
    Zxx_mod = mag * np.exp(1j * phase)
    _, y = signal.istft(Zxx_mod, fs=sr, window=win, nperseg=n_fft,
                         noverlap=n_fft - hop)

    # Trim to original length to avoid clicks
    if len(y) > len(data):
        y = y[:len(data)]
    elif len(y) < len(data):
        y = np.pad(y, (0, len(data) - len(y)), 'constant')

    # Normalize
    peak = np.max(np.abs(y))
    if peak > 0.95:
        y = y / peak * 0.95

    return y.astype(np.float32)


def _apply_emotion(audio_path: str, emotion: str, output_path: str) -> None:
    """Apply emotional voice conversion."""
    data, sr = sf.read(audio_path)
    if data.ndim > 1:
        data = data.mean(axis=1)

    profile = PROFILES.get(emotion, PROFILES["neutral"])
    y = _modify_speech(data, sr, profile)

    sf.write(output_path, y, sr)


def main():
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip()
        if not line:
            continue

        req_id = None
        try:
            req = json.loads(line)
            req_id = req.get("id")
            audio_path = req.get("audio_path", "")
            emotion = req.get("emotion", "neutral")
            output_path = req.get("output_path")
            if not audio_path or not output_path:
                raise ValueError("Missing required fields: audio_path, output_path")
            _apply_emotion(audio_path, emotion, output_path)
            print(json.dumps({"id": req_id, "ok": True}), flush=True)
        except Exception as e:
            print(
                json.dumps({"id": req_id, "error": f"{e}\n{traceback.format_exc()}"}),
                flush=True,
            )


if __name__ == "__main__":
    main()
