// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnxruntime_v2/onnxruntime_v2.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/caption/smolvlm_preprocess.dart';
import 'package:front_porch_ai/services/caption/smolvlm_prompt.dart';
import 'package:front_porch_ai/services/onnx_runtime.dart';

/// The raw SmolVLM-500M ONNX inference pipeline: vision encode → embed →
/// feature splice → prefill → greedy KV-cache decode with a repetition
/// penalty.
///
/// The ENTIRE pipeline (image decode, preprocessing, sessions, decode loop)
/// runs inside one spawned isolate ([caption] is just an `Isolate.run`
/// wrapper), with SYNCHRONOUS native calls inside it. That one choice is the
/// speed of this engine: the plugin's `runAsync` pays two cross-isolate
/// round-trips per generated token (decoder + embed) and that overhead
/// tripled caption time in practice. In-isolate sync calls put the Dart loop
/// within ~10% of the equivalent Python/ORT pipeline. The UI isolate never
/// blocks either way.
///
/// Sessions are created per call and released before returning, so the
/// ~600MB of weights never linger between captions (they co-exist with a
/// running KoboldCpp). Two further perf-critical choices, both deliberate:
///  - the prefill is split so the big [1, N, vocab] logits tensor is never
///    materialized on the Dart side (`.value` is lazy; only [1, 1, vocab]
///    step logits ever cross the FFI boundary), and
///  - present-KV outputs are fed straight back as next-step inputs by native
///    pointer — zero host copies for the cache.
class SmolVlmEngine {
  /// Hidden width / KV layout of the pinned SmolVLM-500M decoder graph.
  static const int _hidden = 960;
  static const int _kvHeads = 5;
  static const int _headDim = 64;

  /// Caption the photo at [imagePath] using the model in [modelDir] (the
  /// three graphs + tokenizer.json; LocalCaptionService verifies presence).
  /// Runs everything in a spawned isolate; returns null on any failure —
  /// callers fall back gracefully to the generic marker.
  static Future<String?> caption({
    required String modelDirPath,
    required String imagePath,
    // 120 bounds the worst-case wait (greedy length varies a lot per image);
    // the sentence trim below keeps a cap cutoff clean.
    int maxNewTokens = 120,
    double repetitionPenalty = 1.25,
  }) {
    return Isolate.run(
      () => _captionInIsolate(
        modelDirPath,
        imagePath,
        maxNewTokens,
        repetitionPenalty,
      ),
    );
  }

  static String? _captionInIsolate(
    String modelDirPath,
    String imagePath,
    int maxNewTokens,
    double repetitionPenalty,
  ) {
    final sw = Stopwatch()..start();
    int mark() {
      final ms = sw.elapsedMilliseconds;
      sw.reset();
      return ms;
    }

    final frames = decodeAndPreprocessForSmolVlm(
      File(imagePath).readAsBytesSync(),
    );
    if (frames == null) return null;
    final vocab = SmolVlmVocabDecoder.fromTokenizerJson(
      File(p.join(modelDirPath, 'tokenizer.json')).readAsStringSync(),
    );
    final tPrep = mark();

    OrtEnv.instance.init();
    final opts = OrtSessionOptions()
      ..setIntraOpNumThreads(math.max(1, Platform.numberOfProcessors - 1));
    OrtSession? vision, embed, decoder;
    final ro = OrtRunOptions();
    try {
      vision = ortSessionFromFile(
        File(p.join(modelDirPath, 'vision_encoder_quantized.onnx')),
        opts,
      );
      embed = ortSessionFromFile(
        File(p.join(modelDirPath, 'embed_tokens_int8.onnx')),
        opts,
      );
      decoder = ortSessionFromFile(
        File(p.join(modelDirPath, 'decoder_model_merged_int8.onnx')),
        opts,
      );
      final tLoad = mark();
      final text = _run(
        vision,
        embed,
        decoder,
        ro,
        frames,
        vocab,
        maxNewTokens,
        repetitionPenalty,
      );
      // Phase timing on stderr-ish debug output — support diagnostics for
      // "captions are slow on my machine" reports.
      // ignore: avoid_print
      print(
        '[LocalCaption] phases: preprocess ${tPrep}ms | '
        'sessions ${tLoad}ms | inference ${mark()}ms',
      );
      return text;
    } finally {
      ro.release();
      vision?.release();
      embed?.release();
      decoder?.release();
      opts.release();
    }
  }

  static String? _run(
    OrtSession vision,
    OrtSession embed,
    OrtSession decoder,
    OrtRunOptions ro,
    SmolVlmFrames frames,
    SmolVlmVocabDecoder vocab,
    int maxNewTokens,
    double repetitionPenalty,
  ) {
    // Everything below allocates native (calloc'd / ORT-owned) tensors that
    // isolate death does NOT reclaim, so the whole pipeline runs under one
    // try whose finally releases whatever is still live — an ORT exception
    // anywhere (unsupported kernel, OOM) must not leak. Big buffers are held
    // in nullable locals nulled on eager release, so the happy-path memory
    // profile (KV cache freed every step) is unchanged and the finally never
    // double-frees.
    OrtValueTensor? pvT, pmT, chunk1, stepEmb;
    var past = <String, OrtValue>{};
    final generated = <int>[];
    try {
      // ── Vision encode: frames → [F, 64, 960] features ──────────────────
      pvT = OrtValueTensor.createTensorWithDataList(frames.pixelValues, [
        1,
        frames.frameCount,
        3,
        512,
        512,
      ]);
      pmT = OrtValueTensor.createTensorWithDataList(frames.pixelMask, [
        1,
        frames.frameCount,
        512,
        512,
      ]);
      final vOut = vision.run(ro, {
        'pixel_values': pvT,
        'pixel_attention_mask': pmT,
      });
      pvT.release();
      pvT = null;
      pmT.release();
      pmT = null;
      if (vOut.isEmpty || vOut[0] == null) return null;
      final feats = _flatten3(vOut[0]!.value as List);
      for (final v in vOut) {
        v?.release();
      }

      // ── Prompt embeddings + feature splice ────────────────────────────
      final promptIds = buildSmolVlmPromptIds(
        rows: frames.rows,
        cols: frames.cols,
      );
      final n = promptIds.length;
      final idsT = OrtValueTensor.createTensorWithDataList(
        Int64List.fromList(promptIds),
        [1, n],
      );
      final eOut = embed.run(ro, {'input_ids': idsT});
      idsT.release();
      if (eOut.isEmpty || eOut[0] == null) return null;
      final promptEmb = _flatten3(eOut[0]!.value as List);
      for (final v in eOut) {
        v?.release();
      }
      var featRow = 0;
      for (var i = 0; i < n; i++) {
        if (promptIds[i] != kSmolVlmImageToken) continue;
        promptEmb.setRange(i * _hidden, (i + 1) * _hidden, feats, featRow);
        featRow += _hidden;
      }
      if (featRow != feats.length) {
        // Grid/prompt mismatch would silently produce garbage — bail instead.
        return null;
      }

      // ── Prefill chunk 1: tokens [0, n-2] — KV only, big logits untouched ─
      final layers = (decoder.inputNames.length - 3) ~/ 2;
      past = {
        for (var i = 0; i < layers; i++) ...{
          'past_key_values.$i.key': OrtValueTensor.createTensorWithDataList(
            Float32List(0),
            [1, _kvHeads, 0, _headDim],
          ),
          'past_key_values.$i.value': OrtValueTensor.createTensorWithDataList(
            Float32List(0),
            [1, _kvHeads, 0, _headDim],
          ),
        },
      };
      chunk1 = OrtValueTensor.createTensorWithDataList(
        promptEmb.sublist(0, (n - 1) * _hidden),
        [1, n - 1, _hidden],
      );
      var outs = _step(
        decoder,
        ro,
        chunk1,
        seqLen: n - 1,
        pastLen: 0,
        past: past,
      );
      chunk1.release();
      chunk1 = null;
      _releaseAll(past.values);
      outs[0]?.release(); // prefill logits: released without materializing
      past = _presentsToPast(decoder.outputNames, outs);

      // ── Greedy loop: first fed token is the prompt's last one ──────────
      var pastLen = n - 1;
      stepEmb = OrtValueTensor.createTensorWithDataList(
        promptEmb.sublist((n - 1) * _hidden, n * _hidden),
        [1, 1, _hidden],
      );
      for (var step = 0; step <= maxNewTokens; step++) {
        outs = _step(
          decoder,
          ro,
          stepEmb!,
          seqLen: 1,
          pastLen: pastLen,
          past: past,
        );
        stepEmb.release();
        stepEmb = null;
        _releaseAll(past.values);
        past = _presentsToPast(decoder.outputNames, outs);
        pastLen += 1;

        final logits = _lastLogits(outs[0]!.value as List);
        outs[0]!.release();
        // Penalize each PREVIOUSLY GENERATED id once (set semantics — the
        // reference implementation; per-occurrence stacking over-penalizes
        // repeats and drives the model into rambling drift).
        for (final id in generated.toSet()) {
          logits[id] = logits[id] > 0
              ? logits[id] / repetitionPenalty
              : logits[id] * repetitionPenalty;
        }
        var best = 0;
        for (var i = 1; i < logits.length; i++) {
          if (logits[i] > logits[best]) best = i;
        }
        if (best == kSmolVlmEndOfUtterance || step == maxNewTokens) break;
        generated.add(best);

        // Embed the new token; its output rides directly into the next step.
        final tokT = OrtValueTensor.createTensorWithDataList(
          Int64List.fromList([best]),
          [1, 1],
        );
        final tOut = embed.run(ro, {'input_ids': tokT});
        tokT.release();
        if (tOut.isEmpty || tOut[0] == null) return null;
        stepEmb = tOut[0] as OrtValueTensor;
      }
    } finally {
      pvT?.release();
      pmT?.release();
      chunk1?.release();
      stepEmb?.release();
      _releaseAll(past.values);
    }
    if (generated.isEmpty) return null;
    var text = vocab.decode(generated).replaceAll(RegExp(r'\s+'), ' ').trim();
    // A token-cap cutoff leaves a dangling half-sentence — trim back to the
    // last completed one when there's enough caption to keep.
    if (text.isNotEmpty && !'.!?'.contains(text[text.length - 1])) {
      final lastStop = text.lastIndexOf(RegExp(r'[.!?]'));
      if (lastStop >= 40) text = text.substring(0, lastStop + 1);
    }
    return text.isEmpty ? null : text;
  }

  /// One decoder run: [seqLen] embedded tokens against [pastLen] cached ones.
  static List<OrtValue?> _step(
    OrtSession decoder,
    OrtRunOptions ro,
    OrtValueTensor inputsEmbeds, {
    required int seqLen,
    required int pastLen,
    required Map<String, OrtValue> past,
  }) {
    final total = pastLen + seqLen;
    final attnT = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(List.filled(total, 1)),
      [1, total],
    );
    final posT = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList([for (var i = pastLen; i < total; i++) i]),
      [1, seqLen],
    );
    try {
      return decoder.run(ro, {
        'inputs_embeds': inputsEmbeds,
        'attention_mask': attnT,
        'position_ids': posT,
        ...past,
      });
    } finally {
      attnT.release();
      posT.release();
    }
  }

  /// Rewrap `present.*` outputs (index 1+) as the next `past_key_values.*`
  /// inputs — by native pointer, no host copy.
  static Map<String, OrtValue> _presentsToPast(
    List<String> outputNames,
    List<OrtValue?> outs,
  ) {
    final past = <String, OrtValue>{};
    for (var i = 1; i < outputNames.length; i++) {
      final out = outs[i];
      if (out == null) continue;
      past[outputNames[i].replaceFirst('present', 'past_key_values')] = out;
    }
    return past;
  }

  static void _releaseAll(Iterable<OrtValue> values) {
    for (final v in values) {
      v.release();
    }
  }

  /// Flatten the plugin's nested-list tensor value ([a][b][hidden] or
  /// [1][b][hidden]) into a Float32List.
  static Float32List _flatten3(List nested) {
    final out = <double>[];
    void walk(List l) {
      for (final e in l) {
        if (e is List) {
          walk(e);
        } else {
          out.add((e as num).toDouble());
        }
      }
    }

    walk(nested);
    return Float32List.fromList(out);
  }

  /// Extract the last position's logits row from a [1][s][vocab] value.
  static Float32List _lastLogits(List nested) {
    final batch = nested[0] as List;
    final row = batch[batch.length - 1] as List;
    return Float32List.fromList([for (final v in row) (v as num).toDouble()]);
  }
}
