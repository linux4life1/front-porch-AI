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
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/caption/smolvlm_engine.dart';

/// Photo Understanding — the fully-offline caption floor for chat photo
/// attachments when the active text model can't see images: SmolVLM-500M
/// (Apache-2.0) running in-process via ONNX Runtime. An optional ~515MB
/// one-tap download; nothing is bundled with the installer.
///
/// Process-wide singleton (mirrors VisionSupportResolver): ChatService asks
/// [captionImage] during the send flow and the Settings card drives
/// [download]/[deleteModel], all observing the same state. Model weights are
/// loaded per caption and released right after (see SmolVlmEngine) so idle
/// RAM cost is zero next to a running KoboldCpp.
class LocalCaptionService extends ChangeNotifier {
  LocalCaptionService._();
  static final LocalCaptionService instance = LocalCaptionService._();

  static const String _repoBase =
      'https://huggingface.co/HuggingFaceTB/SmolVLM-500M-Instruct/resolve/main';

  /// Required artifacts with their approximate sizes (progress weighting).
  /// The vision encoder uses the `quantized` (u8) export, NOT `int8`: the
  /// int8 one needs a ConvInteger kernel the plugin's bundled ONNX Runtime
  /// (1.22 on Linux) doesn't implement — verified against a real photo.
  static const Map<String, int> _artifacts = {
    'onnx/vision_encoder_quantized.onnx': 98600000,
    'onnx/embed_tokens_int8.onnx': 47300000,
    'onnx/decoder_model_merged_int8.onnx': 365000000,
    'tokenizer.json': 3500000,
  };

  /// User-facing size for the download button label.
  static const String downloadSizeLabel = '~515 MB';

  Directory? _dir;
  bool _downloading = false;
  bool _captioning = false;
  double _downloadProgress = 0;
  String? _lastError;
  bool _cancelRequested = false;

  bool get isDownloading => _downloading;
  bool get isCaptioning => _captioning;
  double get downloadProgress => _downloadProgress;
  String? get lastError => _lastError;

  /// Point the service at the app data root (idempotent; safe to call from
  /// every consumer — mirrors how the resolver is used ad hoc).
  void configure(String? rootPath) {
    if (rootPath == null || rootPath.isEmpty) return;
    final dir = Directory(p.join(rootPath, 'caption_model'));
    if (_dir?.path == dir.path) return;
    _dir = dir;
  }

  File _fileFor(String artifact) =>
      File(p.join(_dir!.path, p.basename(artifact)));

  /// All artifacts present and non-empty.
  bool get isInstalled {
    if (_dir == null) return false;
    for (final a in _artifacts.keys) {
      final f = _fileFor(a);
      if (!f.existsSync() || f.lengthSync() == 0) return false;
    }
    return true;
  }

  /// Download all artifacts sequentially (streamed to .part files, renamed on
  /// completion — a killed app never leaves a truncated file looking valid).
  /// Returns true when everything landed.
  Future<bool> download() async {
    if (_dir == null || _downloading) return false;
    _downloading = true;
    _cancelRequested = false;
    _downloadProgress = 0;
    _lastError = null;
    notifyListeners();
    final totalBytes = _artifacts.values.reduce((a, b) => a + b);
    var doneBytes = 0;
    try {
      await _dir!.create(recursive: true);
      for (final entry in _artifacts.entries) {
        final target = _fileFor(entry.key);
        if (target.existsSync() && target.lengthSync() > 0) {
          doneBytes += entry.value;
          _downloadProgress = doneBytes / totalBytes;
          notifyListeners();
          continue;
        }
        final part = File('${target.path}.part');
        final client = http.Client();
        try {
          final response = await client.send(
            http.Request('GET', Uri.parse('$_repoBase/${entry.key}')),
          );
          if (response.statusCode != 200) {
            throw HttpException('HTTP ${response.statusCode} for ${entry.key}');
          }
          final sink = part.openWrite();
          var received = 0;
          try {
            await for (final chunk in response.stream) {
              if (_cancelRequested) {
                throw const HttpException('cancelled');
              }
              sink.add(chunk);
              received += chunk.length;
              final newProgress = (doneBytes + received) / totalBytes;
              // Throttle UI churn to ~1% steps.
              if (newProgress - _downloadProgress > 0.01) {
                _downloadProgress = newProgress;
                notifyListeners();
              }
            }
          } finally {
            await sink.close();
          }
          await part.rename(target.path);
          doneBytes += entry.value;
        } finally {
          client.close();
          if (part.existsSync()) {
            try {
              part.deleteSync();
            } catch (_) {}
          }
        }
      }
      _downloadProgress = 1;
      return true;
    } catch (e) {
      _lastError = _cancelRequested ? null : e.toString();
      debugPrint('[LocalCaption] download failed: $e');
      return false;
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  /// Ask an in-flight download to stop after the current chunk.
  void cancelDownload() => _cancelRequested = true;

  /// Remove the downloaded model entirely (frees the ~515MB).
  Future<void> deleteModel() async {
    if (_dir == null) return;
    try {
      if (_dir!.existsSync()) await _dir!.delete(recursive: true);
    } catch (e) {
      debugPrint('[LocalCaption] delete failed: $e');
    }
    notifyListeners();
  }

  /// Caption a photo on disk. Returns detailed prose, or null when the model
  /// isn't installed / the file is unreadable / inference fails — callers
  /// treat null as "no caption available" and degrade to the generic marker.
  Future<String?> captionImage(String imagePath) async {
    if (!isInstalled || _captioning) return null;
    _captioning = true;
    notifyListeners();
    try {
      final sw = Stopwatch()..start();
      // The engine spawns its own isolate and does everything there (image
      // decode, preprocessing, sessions, decode loop) with synchronous
      // native calls — see SmolVlmEngine for why that's the fast shape.
      final text = await SmolVlmEngine.caption(
        modelDirPath: _dir!.path,
        imagePath: imagePath,
      );
      debugPrint(
        '[LocalCaption] captioned in ${sw.elapsedMilliseconds}ms: '
        '${text == null ? '(failed)' : '"${text.length > 80 ? '${text.substring(0, 80)}…' : text}"'}',
      );
      return text;
    } catch (e) {
      debugPrint('[LocalCaption] caption failed: $e');
      return null;
    } finally {
      _captioning = false;
      notifyListeners();
    }
  }
}
