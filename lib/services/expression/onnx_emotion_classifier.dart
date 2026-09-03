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

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/services.dart';
import 'onnx_emotion_engine.dart';

/// ONNX expression classifier: in-process inference (phase 2 of
/// docs/design/sidecar-retirement.md — the Python sidecar is gone).
///
/// The model auto-downloads on first use (direct HTTPS, no Python), same
/// behavior the sidecar had; until it lands, classify returns neutral.
class OnnxEmotionClassifier implements ExpressionClassifier {
  final StorageService storage;
  final void Function(OnnxDownloadProgress)? onProgress;
  final void Function()? onModelReady;

  static const String _hfBase =
      'https://huggingface.co/Cohee/distilbert-base-uncased-go-emotions-onnx/resolve/main';

  OnnxEmotionClassifier({
    required this.storage,
    this.onProgress,
    this.onModelReady,
  });

  String get _cacheDir => '${storage.rootPath}/models/emotion_classifier';

  /// Locates `(model.onnx, vocab source)` — the native flat dir first, then
  /// the HuggingFace hub cache the retired sidecar built (reused as-is, no
  /// re-download). The hub cache may lack vocab.txt (the fast tokenizer
  /// only downloads tokenizer.json); the engine's vocab loader accepts
  /// either file.
  (String, String)? _resolveModelFiles() {
    final nativeModel = File('$_cacheDir/native/model.onnx');
    final nativeVocab = File('$_cacheDir/native/vocab.txt');
    if (nativeModel.existsSync() && nativeVocab.existsSync()) {
      return (nativeModel.path, nativeVocab.path);
    }
    final root = Directory(_cacheDir);
    if (!root.existsSync()) return null;
    try {
      // followLinks matters: the hub cache the sidecar built stores every
      // snapshot file as a symlink into blobs/, so with followLinks:false
      // the scan saw only Link entities, returned null, and every classify
      // silently fell back to the Python sidecar. `.no_exist` holds
      // zero-byte hub placeholders — never model files.
      for (final e in root.listSync(recursive: true, followLinks: true)) {
        if (e is! File ||
            !e.path.endsWith('model.onnx') ||
            e.path.contains('.no_exist')) {
          continue;
        }
        // Hub layout: .../snapshots/<rev>/onnx/model.onnx with tokenizer
        // files in the snapshot root two levels up.
        final snapshot = e.parent.parent;
        for (final name in ['vocab.txt', 'tokenizer.json']) {
          final vocab = File('${snapshot.path}/$name');
          if (vocab.existsSync()) return (e.path, vocab.path);
        }
      }
    } catch (_) {}
    return null;
  }

  bool _downloadKicked = false;

  @override
  Future<EmotionResult> classify(String text) async {
    if (text.trim().isEmpty) {
      return const EmotionResult(emotion: 'neutral', confidence: 0.0);
    }
    final files = _resolveModelFiles();
    if (files == null) {
      // Model not on disk yet: start the download once (mirrors the
      // sidecar, which auto-downloaded on first use) and answer neutral
      // until it lands.
      if (!_downloadKicked) {
        _downloadKicked = true;
        debugPrint(
          '[Expr-Native] model files not found under $_cacheDir — '
          'starting download',
        );
        unawaited(
          downloadModel().catchError((Object e) {
            debugPrint('[Expr-Native] auto-download failed: $e');
          }),
        );
      }
      EngineHealth.instance.reportFailure(
        EngineHealth.expressions,
        'model not downloaded yet',
        expected: true,
      );
      return const EmotionResult(emotion: 'neutral', confidence: 0.0);
    }
    try {
      final scored = await OnnxEmotionEngine.classify(
        modelPath: files.$1,
        vocabPath: files.$2,
        text: text,
      );
      EngineHealth.instance.reportNative(EngineHealth.expressions);
      return EmotionResult(
        emotion: scored.first.$1,
        confidence: scored.first.$2,
        topCandidates: [
          for (final (label, score) in scored.take(3))
            EmotionCandidate(emotion: label, confidence: score),
        ],
      );
    } catch (e) {
      debugPrint('[Expr-Native] in-process classify failed: $e');
      EngineHealth.instance.reportFailure(
        EngineHealth.expressions,
        'in-process classify failed: $e',
      );
      return const EmotionResult(emotion: 'neutral', confidence: 0.0);
    }
  }

  /// The direct HTTPS download needs nothing installed, so the classifier
  /// is always available — [classify] answers neutral until the model
  /// finishes downloading.
  @override
  Future<bool> isAvailable() async => true;

  /// Downloads model.onnx + vocab.txt directly over HTTPS.
  Future<void> downloadModel() async {
    final dir = Directory('$_cacheDir/native');
    await dir.create(recursive: true);
    await _fetch('$_hfBase/vocab.txt', File('${dir.path}/vocab.txt'));
    await _fetch('$_hfBase/onnx/model.onnx', File('${dir.path}/model.onnx'));
    onModelReady?.call();
  }

  /// Fetches [url] to [dest] via the shared [ModelFetch] helper, mapping
  /// its per-file progress onto [onProgress].
  Future<void> _fetch(String url, File dest) {
    final name = url.split('/').last;
    return ModelFetch.fetch(
      url,
      dest,
      minBytes: name.endsWith('.onnx') ? 1024 * 1024 : 1,
      onProgress: (done, total) => onProgress?.call(
        OnnxDownloadProgress(file: name, downloaded: done, total: total),
      ),
    );
  }
}
