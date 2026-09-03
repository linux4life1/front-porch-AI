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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/expression/onnx_emotion_classifier.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Result of emotion classification.
class EmotionResult {
  final String emotion;
  final double confidence;
  final List<EmotionCandidate> topCandidates;

  const EmotionResult({
    required this.emotion,
    required this.confidence,
    this.topCandidates = const [],
  });

  factory EmotionResult.fromJson(Map<String, dynamic> json) {
    final candidates =
        (json['top_3'] as List<dynamic>?)?.map((e) {
          final m = e as Map<String, dynamic>;
          return EmotionCandidate(
            emotion: m['emotion'] as String? ?? 'unknown',
            confidence: (m['confidence'] as num?)?.toDouble() ?? 0.0,
          );
        }).toList() ??
        [];

    return EmotionResult(
      emotion: json['emotion'] as String? ?? 'neutral',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      topCandidates: candidates,
    );
  }
}

/// A candidate emotion with its confidence score.
class EmotionCandidate {
  final String emotion;
  final double confidence;

  const EmotionCandidate({required this.emotion, required this.confidence});
}

/// Abstract base for expression emotion classifiers.
abstract class ExpressionClassifier {
  /// Classify the emotion of [text].
  Future<EmotionResult> classify(String text);

  /// Returns true if this classifier is available on the current system.
  Future<bool> isAvailable();
}

/// LLM-based classifier that uses the ChatService's existing emotion tracking.
///
/// This is the default classifier when Realism Engine is enabled. It reuses
/// the nuanced emotion word produced by the LLM and maps it to a standard
/// label via [EmotionLabels.nuancedToStandard].
class LLMExpressionClassifier implements ExpressionClassifier {
  final String Function() getCurrentEmotion;
  final Future<String> Function(String unknownEmotion) reclassify;

  LLMExpressionClassifier({
    required this.getCurrentEmotion,
    required this.reclassify,
  });

  @override
  Future<EmotionResult> classify(String text) async {
    final emotion = getCurrentEmotion().toLowerCase();
    if (emotion.isEmpty) {
      return const EmotionResult(emotion: 'neutral', confidence: 1.0);
    }

    // Direct match
    if (EmotionLabels.all.contains(emotion)) {
      return EmotionResult(emotion: emotion, confidence: 1.0);
    }

    // Nuanced mapping
    final mapped = EmotionLabels.nuancedToStandard[emotion];
    if (mapped != null) {
      return EmotionResult(emotion: mapped, confidence: 0.9);
    }

    // Unmapped — trigger LLM re-classification
    try {
      final result = await reclassify(emotion);
      final normalized = result.toLowerCase().trim();
      final label = EmotionLabels.all.contains(normalized)
          ? normalized
          : 'neutral';
      return EmotionResult(emotion: label, confidence: 0.8);
    } catch (_) {
      return const EmotionResult(emotion: 'neutral', confidence: 0.5);
    }
  }

  @override
  Future<bool> isAvailable() async => true;
}

/// Download progress state for the ONNX model.
class OnnxDownloadProgress {
  final String file;
  final int downloaded;
  final int total;

  OnnxDownloadProgress({
    required this.file,
    required this.downloaded,
    required this.total,
  });

  double get fraction => total > 0 ? downloaded / total : 0.0;
}

/// Service that manages expression classification.
///
/// Selects the appropriate classifier based on [StorageService] settings
/// and provides a unified [classify] method.
class ExpressionClassifierService extends ChangeNotifier {
  final StorageService _storage;
  ExpressionClassifier? _activeClassifier;
  String _activeMode = 'llm';

  // Download progress tracking
  bool _isDownloading = false;
  OnnxDownloadProgress? _downloadProgress;
  bool _modelReady = false;

  ExpressionClassifierService(this._storage);

  String get activeMode => _activeMode;
  bool get isDownloading => _isDownloading;
  OnnxDownloadProgress? get downloadProgress => _downloadProgress;
  bool get modelReady => _modelReady;

  /// Returns true when the model cache directory has content.
  bool get isModelCached {
    final dir = Directory('${_storage.rootPath}/models/emotion_classifier');
    try {
      return dir.existsSync() && dir.listSync().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Initialize or re-initialize the classifier based on current settings.
  Future<void> ensureInitialized({
    required String Function() getCurrentEmotion,
    required Future<String> Function(String unknownEmotion) reclassify,
  }) async {
    final mode = _storage.expressionSettings.expressionClassificationMode;
    if (mode == _activeMode && _activeClassifier != null) return;

    debugPrint(
      '[ExpressionClassifierService] Switching from $_activeMode to $mode',
    );

    _activeMode = mode;

    switch (mode) {
      case 'llm':
        _activeClassifier = LLMExpressionClassifier(
          getCurrentEmotion: getCurrentEmotion,
          reclassify: reclassify,
        );
        break;
      case 'onnx':
        // In-process ONNX; the model auto-downloads on first classify.
        _activeClassifier = OnnxEmotionClassifier(
          storage: _storage,
          onProgress: (progress) {
            _isDownloading = true;
            _downloadProgress = progress;
            notifyListeners();
          },
          onModelReady: () {
            _isDownloading = false;
            _modelReady = true;
            notifyListeners();
          },
        );
        break;
      case 'manual':
        _activeClassifier = null;
        break;
      default:
        _activeClassifier = null;
    }

    notifyListeners();
  }

  /// Classify the emotion of [text] using the active classifier.
  ///
  /// Returns null if classification is disabled or in manual mode.
  Future<EmotionResult?> classify(String text) async {
    if (_activeClassifier == null) return null;
    return _activeClassifier!.classify(text);
  }

  /// Triggers a background download of the ONNX model.
  ///
  /// Creates a dedicated [OnnxEmotionClassifier] that fetches the model
  /// directly over HTTPS, cached to
  /// [storage.rootPath]/models/emotion_classifier.
  /// Progress is broadcast via [isDownloading] and [downloadProgress].
  /// Returns false if a download is already in progress, or if the
  /// fetch fails (truncated / tiny body / network). The settings button
  /// nags and the user can tap again.
  Future<bool> triggerOnnxDownload() async {
    if (_isDownloading) return false;

    debugPrint('[ExpressionClassifierService] triggerOnnxDownload called');

    _isDownloading = true;
    _downloadProgress = null;
    notifyListeners();

    final classifier = OnnxEmotionClassifier(
      storage: _storage,
      onProgress: (progress) {
        _downloadProgress = progress;
        notifyListeners();
      },
      onModelReady: () {
        _isDownloading = false;
        _modelReady = true;
        notifyListeners();
      },
    );

    try {
      await classifier.downloadModel();
      // Guard: if onModelReady was never fired (already cached), finalize here
      if (_isDownloading) {
        _isDownloading = false;
        _modelReady = true;
        notifyListeners();
      }
      return true;
    } catch (e) {
      debugPrint('[ExpressionClassifierService] Download error: $e');
      _isDownloading = false;
      notifyListeners();
      return false;
    }
  }
}
