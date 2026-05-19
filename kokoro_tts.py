"""
Kokoro TTS persistent worker for Front Porch AI.

Usage: python kokoro_tts.py   (or the PyInstaller one-dir bundle)

Protocol (JSON lines over stdin/stdout):
  Request:  {"id": 42, "text": "...", "voice": "af_heart", "speed": 1.0, "lang": "en-us",
             "output": "/tmp/out.wav", "model": ".../kokoro-v1.0.onnx", "voices": ".../voices-v1.0.bin"}
  Success:  {"id": 42, "ok": true}
  Error:    {"id": 42, "error": "phonemization failed: ..."}

The worker stays alive and reuses the loaded Kokoro model for subsequent requests.
"""

import sys
import json

try:
    import soundfile as sf
    from kokoro_onnx import Kokoro
except ImportError as e:
    print(json.dumps({"error": f"Missing dependency: {e}"}), flush=True)
    sys.exit(1)


# Module-level cache so the heavy ONNX model is loaded only once per worker process.
_kokoro = None
_current_model_path = None
_current_voices_path = None


def _get_kokoro(model_path: str, voices_path: str):
    """Return a cached Kokoro instance, (re)loading only when the paths change."""
    global _kokoro, _current_model_path, _current_voices_path
    if (
        _kokoro is not None
        and _current_model_path == model_path
        and _current_voices_path == voices_path
    ):
        return _kokoro

    _kokoro = Kokoro(model_path, voices_path)
    _current_model_path = model_path
    _current_voices_path = voices_path
    return _kokoro


def main():
    while True:
        line = sys.stdin.readline()
        if not line:
            # Parent process closed stdin — time to exit cleanly.
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
            # Never die on a bad request — report the error and keep serving.
            print(json.dumps({"id": req_id, "error": str(e)}), flush=True)

            # Force the model to be reloaded on the next request.
            # This can recover from certain internal errors in kokoro-onnx / ONNX Runtime.
            global _kokoro, _current_model_path, _current_voices_path
            _kokoro = None
            _current_model_path = None
            _current_voices_path = None

            # If the error looks like it came from a very long or weird input,
            # we can add extra logging here in the future for debugging.


if __name__ == "__main__":
    main()
