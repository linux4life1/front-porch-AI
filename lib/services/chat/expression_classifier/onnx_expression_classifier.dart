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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// ONNX expression classification for [ExpressionService]: owns the
/// classifier service, the cached ONNX label, and the debounce that keeps
/// re-classification off the per-frame path. Chat-scoped like its owner.
class OnnxExpressionClassifier {
  OnnxExpressionClassifier({
    required this.onNotify,
    required this.getStorageService,
    required this.getIsGenerating,
    required this.getCharacterEmotion,
    required this.getMessages,
    required this.getRealismEvalCancelled,
    required this.onHandleRealismEvalCancelledDuringOnnx,
  });

  final VoidCallback onNotify;
  final StorageService Function() getStorageService;
  final bool Function() getIsGenerating;
  final String Function() getCharacterEmotion;
  final List<ChatMessage> Function() getMessages;
  final bool Function() getRealismEvalCancelled;
  final Future<void> Function() onHandleRealismEvalCancelledDuringOnnx;

  ExpressionClassifierService? _service;
  String? _label;
  String? _cachedForEmotion;
  int _lastMessageCount = 0;
  String? _lastMessageText;
  bool _classifying = false;
  Timer? _debounce;

  /// The ONNX-mode label for [lower] (the active emotion, lowercased).
  /// Triggers a debounced classification when the message tip or emotion
  /// moved since the cached result.
  String? currentLabel(
    String lower, {
    required int messageCount,
    required String lastAiMsgText,
  }) {
    // ── STABILITY: Keep previous expression while generating ───────────────
    // As requested, we don't want "live" updates. We keep the current
    // face until the message is complete.
    if (getIsGenerating()) {
      return _label ?? EmotionLabels.nuancedToStandard[lower] ?? 'neutral';
    }

    // Trigger async ONNX classification if a new message arrived, text changed, or emotion changed
    if ((_cachedForEmotion != lower ||
            messageCount != _lastMessageCount ||
            lastAiMsgText != _lastMessageText) &&
        !_classifying &&
        _debounce == null) {
      // Use a small debounce to avoid rapid re-triggering during UI transitions
      _debounce = Timer(const Duration(milliseconds: 500), () {
        _debounce = null;
        classify(lower);
      });
    }

    if (_cachedForEmotion == lower && _label != null) {
      return _label;
    }
    return _label ?? EmotionLabels.nuancedToStandard[lower] ?? 'neutral';
  }

  /// Initialize the ONNX expression classifier service.
  void init() {
    _service ??= ExpressionClassifierService(getStorageService());
  }

  /// Set the ExpressionClassifierService (for ONNX).
  void setService(ExpressionClassifierService service) {
    _service = service;
  }

  void reset() {
    _label = null;
    _cachedForEmotion = null;
    _lastMessageCount = 0;
    _lastMessageText = null;
    _classifying = false;
    _debounce?.cancel();
    _debounce = null;
  }

  void invalidateForNewResponse() {
    _cachedForEmotion = null;
    _label = null;
    _lastMessageText = null;
  }

  /// Fire-and-forget: classify emotion using ONNX model.
  /// Uses the last AI message text as classification input.
  Future<void> classify(String emotion) async {
    if (_service == null) {
      init();
    }
    if (_service == null) return;

    _classifying = true;
    _lastMessageCount = getMessages().length;
    _lastMessageText = getMessages().isNotEmpty && !getMessages().last.isUser
        ? getMessages().last.text
        : '';
    stdout.writeln(
      '>>> [CHAT:ONNX] Starting classification for message count: $_lastMessageCount',
    ); // verbatim from original (for >>> marker visibility in logs; dart:io import for this only; no change for mechanical fidelity)
    try {
      // Initialize classifier with current mode
      await _service!.ensureInitialized(
        getCurrentEmotion: getCharacterEmotion,
        reclassify: (unknown) async {
          return 'neutral';
        },
      );

      // Use last AI message text for classification
      String text = '';
      for (int i = getMessages().length - 1; i >= 0; i--) {
        if (!getMessages()[i].isUser && getMessages()[i].text.isNotEmpty) {
          text = getMessages()[i].text;
          break;
        }
      }
      // Reasoning models leave their <think> block in the stored message
      // text — classify the character's prose, not the meta-reasoning.
      text = stripThinkTags(text);
      if (text.isEmpty) text = emotion;

      final result = await _service!.classify(text);
      if (result != null) {
        final label = result.emotion.toLowerCase();
        if (EmotionLabels.all.contains(label)) {
          debugPrint(
            '[Expression:ONNX] emotion=$emotion -> label=$label (confidence: ${result.confidence})',
          );
          _label = label;
          _cachedForEmotion = emotion;
          onNotify();
          return;
        }
      }
      // Fallback
      _label = 'neutral';
      _cachedForEmotion = emotion;
      onNotify();
      // cancel check only reached on fallback path due to early return on valid ONNX result (preserves original try/early-return/fallback placement); finally only clears classifying flag
      if (getRealismEvalCancelled()) {
        await onHandleRealismEvalCancelledDuringOnnx();
        return;
      }
    } catch (e) {
      debugPrint('[Expression:ONNX] classification error: $e');
      _label = 'neutral';
      _cachedForEmotion = emotion;
      onNotify();
    } finally {
      _classifying = false;
    }
  }
}
