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

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:front_porch_ai/services/caption/local_caption_service.dart';
import 'package:front_porch_ai/services/services.dart';

/// The desktop's Classification / Display / Fallback choices
/// (`expression_section.dart`). A value outside these is ignored on write.
const Set<String> kExpressionModes = {'llm', 'onnx', 'manual'};
const Set<String> kExpressionDisplays = {'sidebar', 'background', 'both'};
const Set<String> kExpressionFallbacks = {'neutral', 'prime', 'none', 'emoji'};

/// Settings → Voice & Media host keys the web shows beside the TTS/STT
/// switches: Auto-send transcription, the Expression Images controls, the
/// Image Generation switch, the ONNX expression model and the Photo
/// Understanding helper. Reads ride `GET /api/voice/status` (additive keys);
/// writes go through the same storage setters the desktop tab calls, so the
/// desktop repaints and `settings_changed` reaches every web session.
class VoiceMediaWire {
  VoiceMediaWire(this._storage, {this.expressions, this.caption});

  final StorageService _storage;

  /// Null on a host that has not wired it: the ONNX block reads null.
  final ExpressionClassifierService? expressions;

  /// Null on a host that has not wired it: the photo block reads null.
  final LocalCaptionService? caption;

  /// The last ONNX download the web asked for came back without a model —
  /// the desktop's "Download failed" snackbar, as a flag the page can show.
  bool _onnxFailed = false;

  Map<String, dynamic> read() {
    final e = _storage.expressionSettings;
    return {
      'autoSendTranscription': _storage.sttSettings.autoSendTranscription,
      'imageGenEnabled': _storage.imageGenSettings.imageGenEnabled,
      'expressionEnabled': e.expressionEnabled,
      'expressionMode': e.expressionClassificationMode,
      'expressionDisplay': e.expressionDisplayMode,
      'expressionRerollSame': e.expressionRerollSame,
      'expressionEmojiBurst': e.expressionEmojiBurst,
      'expressionEmojiBurstSize': e.expressionEmojiBurstSize,
      'expressionFallback': e.expressionFallback,
      'onnxModel': _onnx(),
      'photoHelper': _photo(),
    };
  }

  /// `ready` mirrors the desktop's green check (`modelReady || isModelCached`),
  /// `downloading` its spinner, `missing` its download button.
  Map<String, dynamic>? _onnx() {
    final s = expressions;
    if (s == null) return null;
    final ready = s.modelReady || s.isModelCached;
    final progress = s.downloadProgress;
    return {
      'state': ready
          ? 'ready'
          : s.isDownloading
          ? 'downloading'
          : 'missing',
      'progress': s.isDownloading && progress != null
          ? progress.fraction
          : null,
      'failed': !ready && !s.isDownloading && _onnxFailed,
    };
  }

  /// The card renders nothing while `state` is `absent` (the desktop's
  /// self-hiding PhotoUnderstandingCard).
  Map<String, dynamic>? _photo() {
    final c = caption;
    if (c == null) return null;
    return {
      'state': c.isDownloading
          ? 'downloading'
          : c.isInstalled
          ? 'installed'
          : 'absent',
      'progress': c.downloadProgress,
      'sizeLabel': LocalCaptionService.downloadSizeLabel,
      'captioning': c.isCaptioning,
    };
  }

  /// Applies the keys this class owns. Wrong types and values outside the
  /// desktop's choices are ignored (the settings house rule), never a 400.
  Future<void> write(Map<String, dynamic> body) async {
    final autoSend = body['autoSendTranscription'];
    if (autoSend is bool) {
      await _storage.sttSettings.setAutoSendTranscription(autoSend);
    }
    final imageGen = body['imageGenEnabled'];
    if (imageGen is bool) {
      await _storage.imageGenSettings.setImageGenEnabled(imageGen);
    }
    final e = _storage.expressionSettings;
    final enabled = body['expressionEnabled'];
    if (enabled is bool) await e.setExpressionEnabled(enabled);
    final mode = body['expressionMode'];
    if (mode is String && kExpressionModes.contains(mode)) {
      await e.setExpressionClassificationMode(mode);
    }
    final display = body['expressionDisplay'];
    if (display is String && kExpressionDisplays.contains(display)) {
      await e.setExpressionDisplayMode(display);
    }
    final reroll = body['expressionRerollSame'];
    if (reroll is bool) await e.setExpressionRerollSame(reroll);
    final burst = body['expressionEmojiBurst'];
    if (burst is bool) await e.setExpressionEmojiBurst(burst);
    final size = body['expressionEmojiBurstSize'];
    if (size is num && size.isFinite) {
      await e.setExpressionEmojiBurstSize(burstSizeStep(size.toDouble()));
    }
    final fallback = body['expressionFallback'];
    if (fallback is String && kExpressionFallbacks.contains(fallback)) {
      await e.setExpressionFallback(fallback);
    }
  }

  /// The desktop slider's stops: 12 to 60 in steps of 4 (12 divisions).
  static double burstSizeStep(double v) {
    final clamped = v.clamp(12.0, 60.0);
    return 12.0 + ((clamped - 12.0) / 4.0).round() * 4.0;
  }

  /// Starts the ONNX download the desktop button starts, without waiting for
  /// it: the page polls the status for progress. False when the host has no
  /// classifier service.
  bool startOnnxDownload() {
    final s = expressions;
    if (s == null) return false;
    if (s.isDownloading) return true;
    _onnxFailed = false;
    unawaited(
      s.triggerOnnxDownload().then(
        (ok) {
          if (!ok && !s.isDownloading) _onnxFailed = true;
        },
        onError: (Object err) {
          debugPrint('[VoiceMediaWire] ONNX download failed: $err');
          _onnxFailed = true;
        },
      ),
    );
    return true;
  }

  /// The photo card's Cancel. False when the host has no caption service.
  bool cancelPhotoDownload() {
    final c = caption;
    if (c == null) return false;
    c.cancelDownload();
    return true;
  }

  /// The photo card's Remove; refused (null) while a caption is running,
  /// exactly when the desktop greys the button.
  Future<bool?> removePhotoHelper() async {
    final c = caption;
    if (c == null) return false;
    if (c.isCaptioning) return null;
    await c.deleteModel();
    return true;
  }
}
