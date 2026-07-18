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

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/expression_pack_service.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';

/// Fires one multimodal eval and returns the raw reply text, or null on
/// failure. Production wires this to vision_eval.dart's fireVisionEval with
/// the active LLM captured in the closure; tests substitute a fake.
typedef VisionEvalFn =
    Future<String?> Function({
      required String prompt,
      required List<String> imagesB64,
    });

/// Runs advisory Vision QC over a finished expression pack: for each done
/// slot the vision model compares the generated image against the base
/// portrait ("same person? expression reads? visual flaws?") and the parsed
/// verdict is stamped on the slot for the grid to badge. Verdicts never
/// block anything — keeping or discarding a flagged image stays the user's
/// call. Mirrors [ExpressionPackSession]'s sequential run/cancel/dispose
/// idioms.
class ExpressionPackQc extends ChangeNotifier {
  ExpressionPackQc({
    required List<ExpressionSlot> slots,
    required String baseImageB64,
    required VisionEvalFn fire,
  }) : _slots = slots,
       _baseImageB64 = baseImageB64,
       _fire = fire;

  final List<ExpressionSlot> _slots;
  final String _baseImageB64;
  final VisionEvalFn _fire;

  bool _running = false;
  bool _cancelRequested = false;
  bool _disposed = false;
  int _checkedCount = 0;
  int _totalToCheck = 0;
  int _unparsedCount = 0;

  bool get isRunning => _running;

  /// Slots whose QC finished during this run (parsed or not).
  int get checkedCount => _checkedCount;

  /// Done slots that were eligible for QC when [run] started.
  int get totalToCheck => _totalToCheck;

  /// Slots currently carrying a failing verdict.
  int get flaggedCount =>
      _slots.where((s) => s.qc != null && !s.qc!.pass).length;

  /// Replies this run that couldn't be parsed (their slots keep qc == null).
  int get unparsedCount => _unparsedCount;

  /// Sequentially QC every done slot; no-op if already running. Each check
  /// sends the base portrait first and the slot image second. An in-flight
  /// eval can't be aborted from here, so — like the pack session — the
  /// cancel flag is only consulted between slots.
  Future<void> run() async {
    if (_running) return;
    final targets = _slots
        .where((s) => s.state == ExpressionSlotState.done && s.bytes != null)
        .toList();
    _running = true;
    _cancelRequested = false;
    _checkedCount = 0;
    _unparsedCount = 0;
    _totalToCheck = targets.length;
    notifyListeners();
    for (final slot in targets) {
      if (_cancelRequested) break;
      final checkedBytes = slot.bytes!;
      final reply = await _fire(
        prompt: _qcPrompt(),
        imagesB64: [_baseImageB64, base64Encode(checkedBytes)],
      );
      if (_disposed) return;
      // A re-roll may have replaced the image while this check was in
      // flight (the session doesn't lock during QC) — never stamp a verdict
      // for bytes the slot no longer holds.
      if (identical(slot.bytes, checkedBytes)) {
        final verdict = reply == null
            ? null
            : _parseVerdict(reply, slot.emotion);
        if (verdict != null) {
          slot.qc = verdict;
        } else {
          _unparsedCount++;
        }
      }
      _checkedCount++;
      notifyListeners();
    }
    _running = false;
    notifyListeners();
  }

  /// Finish the in-flight slot's eval, then stop; the rest stay unchecked.
  void cancel() {
    _cancelRequested = true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The target emotion is deliberately NOT revealed: the model must NAME the
/// expression it sees and the app compares that word itself. A yes/no
/// "does it match «anger»?" invited sycophancy — and a blind setup (a server
/// that accepts image content but quietly drops it for text-only models)
/// could rubber-stamp every slot. Naming one emotion out of dozens is not
/// guessable blind, so identical packs get flagged instead of blessed.
String _qcPrompt() =>
    'Image 1 is the reference portrait of a character. Image 2 is a variant '
    'of the same portrait. Reply with ONLY this JSON: '
    '{"same_person": true/false, "expression": "one or two words naming the '
    'facial expression shown in Image 2", "flaw": "none" or a very short '
    'description of any visual defect (warped face, extra limbs, artifacts)}';

/// Regex-fishes the verdict fields out of the reply — the same brittle-JSON
/// posture as LlmEvalEngine's extractors, because vision models wrap the
/// JSON in prose more often than not. same_person + a non-empty named
/// expression → a verdict; anything else → null (unparsed).
PackQcVerdict? _parseVerdict(String reply, String targetEmotion) {
  final m = RegExp(
    r'"same_person"\s*:\s*(true|false)',
  ).firstMatch(reply);
  final samePerson = m != null ? (m.group(1) == 'true') : null;
  final observed =
      RegExp(r'"expression"\s*:\s*"([^"]*)"')
          .firstMatch(reply)
          ?.group(1)
          ?.trim()
          .toLowerCase() ??
      '';
  if (samePerson == null || observed.isEmpty) return null;

  final matches = _observedMatchesTarget(observed, targetEmotion);
  final flawRaw =
      RegExp(r'"flaw"\s*:\s*"([^"]*)"').firstMatch(reply)?.group(1)?.trim() ??
      '';
  final flaw = flawRaw.toLowerCase() == 'none' ? '' : flawRaw;
  return PackQcVerdict(
    samePerson: samePerson,
    expressionMatches: matches,
    // Tooltip context only — never flips pass. On a mismatch, say what the
    // model actually saw; a reported flaw rides along either way.
    note: [
      if (!matches) 'reads as "$observed"',
      if (flaw.isNotEmpty) flaw,
    ].join('; '),
  );
}

/// Does the model's named [observed] expression denote [target] (a standard
/// EmotionLabels value)? Direct hit, the shared nuanced→standard vocabulary
/// (e.g. "furious"→anger, "happy"→joy), or a shared word stem ("amused" /
/// "amusement") all count.
bool _observedMatchesTarget(String observed, String target) {
  if (observed.contains(target)) return true;
  for (final word in observed.split(RegExp(r'[^a-z]+'))) {
    if (word.isEmpty) continue;
    if (word == target) return true;
    if (EmotionLabels.nuancedToStandard[word] == target) return true;
    // Stem heuristic for morphology the map lacks: "embarrassed" vs
    // "embarrassment". Require a substantial shared prefix.
    final n = word.length < target.length ? word.length : target.length;
    if (n >= 5 && word.substring(0, 5) == target.substring(0, 5)) return true;
  }
  return false;
}
