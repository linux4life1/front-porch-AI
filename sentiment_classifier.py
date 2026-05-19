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

"""
Sentiment classifier for Front Porch AI expression images.

Uses the distilbert-base-uncased-go-emotions-onnx model from HuggingFace
to classify text into one of 28 emotion labels.

Protocol: reads JSON from stdin, writes JSON to stdout.
  Input:  {"text": "I'm so happy right now!"}
  Output: {"emotion": "joy", "confidence": 0.92}

Download progress is emitted to stderr as JSON:
  {"status": "download_progress", "file": "...", "downloaded": N, "total": N}
  {"status": "model_ready"}
  {"error": "..."}

Flags:
  --download-only       Download/cache the model without reading from stdin.
  --cache-dir <path>    Directory to store downloaded model files.
                        Defaults to ~/.cache/front_porch_ai/emotion_classifier.
"""

import sys
import json
import os
import numpy as np

# ── CLI argument parsing ───────────────────────────────────────────────────────

def _get_arg(flag, default=None):
    for i, arg in enumerate(sys.argv):
        if arg == flag and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return default

DOWNLOAD_ONLY = '--download-only' in sys.argv

_default_cache = os.path.join(
    os.getenv('APPDATA') if os.name == 'nt'
    else os.path.join(os.path.expanduser('~'), '.cache'),
    'front_porch_ai', 'emotion_classifier',
)
MODEL_CACHE_DIR = _get_arg('--cache-dir', _default_cache)

# ── Constants ─────────────────────────────────────────────────────────────────

MODEL_REPO = 'Cohee/distilbert-base-uncased-go-emotions-onnx'

EMOTION_LABELS = [
    'admiration', 'amusement', 'anger', 'annoyance', 'approval',
    'caring', 'confusion', 'curiosity', 'desire', 'disappointment',
    'disgust', 'embarrassment', 'excitement', 'fear', 'gratitude',
    'grief', 'joy', 'love', 'nervousness', 'optimism', 'pride',
    'realization', 'remorse', 'sadness', 'surprise', 'neutral',
]

_model = None
_tokenizer = None


# ── tqdm progress patch ───────────────────────────────────────────────────────

def _patch_tqdm():
    """
    Monkey-patch tqdm so download progress is emitted as JSON to stderr.

    transformers and huggingface_hub use tqdm internally for file downloads.
    We subclass it to intercept updates and emit our JSON protocol.
    NOTE: progress_callback is NOT a valid kwarg for from_pretrained() —
    tqdm patching is the correct way to capture download progress.
    """
    try:
        import tqdm as tqdm_module

        OrigTqdm = tqdm_module.tqdm

        class _JsonTqdm(OrigTqdm):
            def update(self, n=1):
                result = super().update(n)
                try:
                    if self.total and self.total > 0:
                        msg = {
                            'status': 'download_progress',
                            'file': str(self.desc or 'unknown'),
                            'downloaded': int(self.n),
                            'total': int(self.total),
                        }
                        print(json.dumps(msg), file=sys.stderr, flush=True)
                except Exception:
                    pass
                return result

        # Patch the main tqdm class
        tqdm_module.tqdm = _JsonTqdm

        # Also patch tqdm.auto (huggingface_hub uses this)
        try:
            import tqdm.auto as tqdm_auto
            tqdm_auto.tqdm = _JsonTqdm
        except Exception:
            pass

        # Patch huggingface_hub's internal tqdm shim
        try:
            import huggingface_hub.utils._tqdm as hf_tqdm_mod
            hf_tqdm_mod.tqdm = _JsonTqdm
        except Exception:
            pass

    except Exception:
        pass  # tqdm not installed; progress won't be reported but download still works


# ── Numerically-stable softmax (numpy only, no torch) ─────────────────────────

def _softmax(logits):
    x = np.array(logits, dtype=np.float64)
    e_x = np.exp(x - np.max(x))
    return (e_x / e_x.sum()).tolist()


# ── Model loader ──────────────────────────────────────────────────────────────

def _load_model():
    global _model, _tokenizer
    if _model is not None and _tokenizer is not None:
        return _model, _tokenizer

    # Check dependencies first so the error message is helpful
    try:
        import onnxruntime as ort
        from huggingface_hub import hf_hub_download
        from transformers import AutoTokenizer
    except ImportError as e:
        _err(f'Missing dependency: {e}. Run: pip install onnxruntime huggingface_hub transformers numpy')
        sys.exit(1)

    try:
        os.makedirs(MODEL_CACHE_DIR, exist_ok=True)

        # Signal start to the Dart side
        print(json.dumps({'status': 'loading_model', 'model': MODEL_REPO}), file=sys.stderr, flush=True)

        # Patch tqdm BEFORE calling from_pretrained so downloads are tracked.
        # Do NOT pass progress_callback= — it is not a valid kwarg for these APIs.
        _patch_tqdm()

        _tokenizer = AutoTokenizer.from_pretrained(MODEL_REPO, cache_dir=MODEL_CACHE_DIR)
        model_path = hf_hub_download(repo_id=MODEL_REPO, filename="onnx/model.onnx", cache_dir=MODEL_CACHE_DIR)
        _model = ort.InferenceSession(model_path)

        print(json.dumps({'status': 'model_ready'}), file=sys.stderr, flush=True)

    except Exception as e:
        _err(f'Failed to load model: {e}')
        sys.exit(1)

    return _model, _tokenizer


def _err(msg: str):
    """Emit an error to both stderr (visible in Flutter logs) and stdout (parseable by Dart)."""
    payload = json.dumps({'error': msg})
    print(payload, file=sys.stderr, flush=True)
    print(payload, flush=True)


# ── Classification ────────────────────────────────────────────────────────────

def classify(text: str) -> dict:
    model, tokenizer = _load_model()

    inputs = tokenizer(text, return_tensors='np', truncation=True, max_length=512, padding=True)
    
    ort_inputs = {
        "input_ids": inputs["input_ids"],
        "attention_mask": inputs["attention_mask"]
    }
    outputs = model.run(None, ort_inputs)

    logits = outputs[0][0]
    scores = _softmax(logits)
    max_idx = scores.index(max(scores))

    def get_label(i):
        try:
            return EMOTION_LABELS[i]
        except IndexError:
            return 'neutral'

    return {
        'emotion': get_label(max_idx),
        'confidence': round(scores[max_idx], 4),
        'top_3': [
            {'emotion': get_label(i), 'confidence': round(scores[i], 4)}
            for i in sorted(range(len(scores)), key=lambda x: scores[x], reverse=True)[:3]
        ],
    }


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    if DOWNLOAD_ONLY:
        # Download/cache only — no stdin. Triggered by the settings button.
        _load_model()
        sys.exit(0)

    # Normal classification mode: JSON input on stdin → JSON output on stdout.
    try:
        while True:
            line = sys.stdin.readline()
            if not line:
                break
            
            line_content = line.strip()
            if not line_content:
                continue
                
            request = json.loads(line_content)
            text_input = request.get("text")
            
            # Ensure we have a string. If the app accidentally sent null, use empty string.
            text = str(text_input) if text_input is not None else ""

            if not text.strip():
                print(json.dumps({'emotion': 'neutral', 'confidence': 0.0}), flush=True)
                continue

            print(json.dumps(classify(text)), flush=True)

    except Exception as e:
        _err(str(e))
        sys.exit(1)


if __name__ == '__main__':
    main()
