"""
Kokoro TTS / Emotional Voice persistent worker for Front Porch AI.

Usage:
  python kokoro_tts.py              # TTS worker (stdin/stdout JSON protocol)
  python kokoro_tts.py --emotional   # Emotional voice DSP worker

TTS Protocol (JSON lines over stdin/stdout):
  Request:  {"id": 42, "text": "...", "voice": "af_heart", "speed": 1.0, "lang": "en-us",
             "output": "/tmp/out.wav", "model": ".../kokoro-v1.0.onnx", "voices": ".../voices-v1.0.bin"}
  Success:  {"id": 42, "ok": true}
  Error:    {"id": 42, "error": "phonemization failed: ..."}

Emotional Protocol (JSON lines over stdin/stdout):
  Request:  {"id": 1, "audio_path": "/tmp/input.wav", "emotion": "joy",
             "output_path": "/tmp/output.wav"}
  Success:  {"id": 1, "ok": true}
  Error:    {"id": 1, "error": "..."}

The worker stays alive and reuses the loaded model for subsequent requests.
"""

import json
import sys
import traceback

try:
    import soundfile as sf
except ImportError as e:
    print(json.dumps({"error": f"Missing dependency: {e}"}), flush=True)
    sys.exit(1)


# ═══════════════════════════════════════════════════════════════════
# TTS mode
# ═══════════════════════════════════════════════════════════════════

try:
    from kokoro_onnx import Kokoro
    _HAS_KOKORO = True
except ImportError:
    _HAS_KOKORO = False

_kokoro = None
_current_model_path = None
_current_voices_path = None


def _get_kokoro(model_path: str, voices_path: str):
    global _kokoro, _current_model_path, _current_voices_path
    if (
        _kokoro is not None
        and _current_model_path == model_path
        and _current_voices_path == voices_path
    ):
        return _kokoro
    if not _HAS_KOKORO:
        raise ImportError("kokoro_onnx is not installed")
    _kokoro = Kokoro(model_path, voices_path)
    _current_model_path = model_path
    _current_voices_path = voices_path
    return _kokoro


def _run_tts_worker():
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

            text = req.get("text", "")
            voice = req.get("voice", "af_heart")
            speed = req.get("speed", 1.0)
            lang = req.get("lang", "en-us")
            output_path = req.get("output")
            model_path = req.get("model")
            voices_path = req.get("voices")

            if not output_path or not model_path or not voices_path:
                raise ValueError("Missing required path fields (output, model, voices)")

            kokoro = _get_kokoro(model_path, voices_path)
            samples, sample_rate = kokoro.create(text, voice=voice, speed=speed, lang=lang)
            sf.write(output_path, samples, sample_rate)

            print(json.dumps({"id": req_id, "ok": True}), flush=True)

        except Exception as e:
            print(json.dumps({"id": req_id, "error": str(e)}), flush=True)

            global _kokoro, _current_model_path, _current_voices_path
            _kokoro = None
            _current_model_path = None
            _current_voices_path = None


# ═══════════════════════════════════════════════════════════════════
# Emotional voice mode  (numpy/scipy imported inside to avoid
# affecting the TTS code path)
# ═══════════════════════════════════════════════════════════════════

# Emotion profiles: (pitch_shift_semitones, pitch_variance_scale,
#                    brightness_db, tension_scale, breathiness, speed_ratio)
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


def _modify_speech(data, sr, profile):
    """Apply emotion profile to speech using STFT + pitch manipulation."""
    import numpy as np

    pitch_st, pitch_var, bright_db, tension, breath, speed = profile

    try:
        import scipy.signal as signal
        from scipy.ndimage import gaussian_filter1d
        has_scipy = True
    except ImportError:
        has_scipy = False

    if not has_scipy:
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

    n_fft = 2048
    hop = 512
    win = np.hanning(n_fft)

    f, t, Zxx = signal.stft(data, fs=sr, window=win, nperseg=n_fft,
                             noverlap=n_fft - hop)
    mag = np.abs(Zxx)
    phase = np.angle(Zxx)

    if abs(pitch_st) >= 0.5:
        shift_bins = int(round(pitch_st / 12.0 * mag.shape[0] / 2))
        if shift_bins > 0:
            mag = np.roll(mag, shift_bins, axis=0)
            mag[:shift_bins] = 0
        elif shift_bins < 0:
            mag = np.roll(mag, shift_bins, axis=0)
            mag[shift_bins:] = 0

    if abs(pitch_var - 1.0) > 0.05:
        frame_energy = np.sum(mag, axis=0)
        energy_norm = frame_energy / (np.max(frame_energy) + 1e-10)
        modulation = 1.0 + (energy_norm - 0.5) * (pitch_var - 1.0) * 2
        for i in range(mag.shape[1]):
            freq_axis = np.arange(mag.shape[0]) / mag.shape[0]
            tilt = 1.0 + (freq_axis - 0.5) * (modulation[i] - 1.0) * 2
            mag[:, i] = np.clip(mag[:, i] * tilt, 0, None)

    if abs(bright_db) >= 0.5:
        n_freq = mag.shape[0]
        tilt_linear = 10.0 ** (bright_db / 20.0)
        freq_weights = np.linspace(1.0, tilt_linear, n_freq)
        mag = mag * freq_weights[:, np.newaxis]

    if tension > 0.05:
        smoothed = mag.copy()
        for i in range(mag.shape[1]):
            smoothed[:, i] = np.convolve(mag[:, i],
                                          np.ones(5) / 5, mode='same')
        mag = mag + (mag - smoothed) * tension
        mag = np.clip(mag, 1e-10, None)

    if breath > 0.01:
        noise = np.random.randn(*mag.shape) * breath * np.max(mag) * 0.05
        noise[:mag.shape[0] // 4] = 0
        mag = mag + np.abs(noise)

    if abs(speed - 1.0) > 0.02:
        n_t = mag.shape[1]
        new_n = max(1, int(n_t / speed))
        old_idx = np.arange(n_t)
        new_idx = np.linspace(0, n_t - 1, new_n)
        mag = np.array([np.interp(new_idx, old_idx, mag[i, :])
                        for i in range(mag.shape[0])])
        phase = np.array([np.interp(new_idx, old_idx, phase[i, :])
                          for i in range(phase.shape[0])])

    Zxx_mod = mag * np.exp(1j * phase)
    _, y = signal.istft(Zxx_mod, fs=sr, window=win, nperseg=n_fft,
                         noverlap=n_fft - hop)

    if len(y) > len(data):
        y = y[:len(data)]
    elif len(y) < len(data):
        y = np.pad(y, (0, len(data) - len(y)), 'constant')

    peak = np.max(np.abs(y))
    if peak > 0.95:
        y = y / peak * 0.95

    return y.astype(np.float32)


def _apply_emotion(audio_path, emotion, output_path):
    data, sr = sf.read(audio_path)
    if data.ndim > 1:
        data = data.mean(axis=1)

    import numpy as np
    profile = PROFILES.get(emotion, PROFILES["neutral"])
    y = _modify_speech(data, sr, profile)
    sf.write(output_path, y, sr)


def _run_emotional_worker():
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


# ═══════════════════════════════════════════════════════════════════
# Entry point
# ═══════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    if "--emotional" in sys.argv:
        _run_emotional_worker()
    else:
        _run_tts_worker()
