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

part of '../chat_service.dart';

/// Greeting + baseline-eval subsystem: the once-per-session post-greeting
/// baseline eval, the retroactive baseline scan (Realism toggled on mid-chat),
/// alternate-greeting cycling, and first-message macro resolution. Extracted
/// verbatim from the god file (zero behaviour change) — these run on the active
/// character's scalars via the normal eval path (no `_groupRealism` load/save),
/// so 1:1 and group baseline behaviour is unchanged.
extension ChatServiceGreeting on ChatService {
  /// Evaluates emotion + relationship baseline from the greeting message only.
  /// Runs once per new session, silently in the background.
  Future<void> _runPostGreetingEval() async {
    if (!_realismEnabled || _activeCharacter == null) return;
    _greetingEvalPending = false; // consume the pending flag
    debugPrint('[Realism] Running post-greeting baseline eval...');
    _isProcessingGreeting = true;
    notifyListeners();
    try {
      await Future.wait([
        // delegates to _llmEvalEngine (step 9 thins; full bodies excised)
        _evaluateEmotionalStateCall(),
        Future.delayed(
          ChatService._kEvalDispatchStagger,
          () => _evaluateRelationshipCall(),
        ),
      ]);

      if (_realismEvalCancelled) {
        debugPrint('[Realism] Post-greeting eval cancelled');
        _realismEvalCancelled = false;
        return;
      }

      // Check for cancellation after each eval
      if (_realismEvalCancelled) {
        debugPrint('[Realism] Post-greeting eval cancelled');
        _realismEvalCancelled =
            false; // Reset the flag so future messages can proceed
        return;
      }

      // Store initial emotion in metadata on the greeting message itself
      if (_messages.isNotEmpty) {
        _messages.first.activeMetadata ??= {};
        if (_characterEmotion.isNotEmpty) {
          _messages.first.activeMetadata!['emotion_label'] = _characterEmotion;
          _messages.first.activeMetadata!['realism_state'] =
              _captureRealismState();
        }
      }
      await _saveChat();
      notifyListeners();
      debugPrint(
        '[Realism] Post-greeting baseline: emotion=$_characterEmotion, bond=${_relationshipService.affectionScore}, trust=${_relationshipService.trustLevel}',
      );
    } catch (e) {
      debugPrint('[Realism] Post-greeting eval failed: $e');
    } finally {
      _isProcessingGreeting = false;
      notifyListeners();
    }
  }

  /// Retroactive baseline eval — fires when Realism is enabled mid-conversation
  /// with no prior state captured. Evaluates the full visible message history
  /// so the engine catches up on emotion, bond, and scene state.
  Future<void> _runRetroactiveBaselineEval() async {
    if (!_realismEnabled || _activeCharacter == null) return;
    debugPrint(
      '[Realism] Running retroactive baseline scan (${_messages.length} messages)...',
    );
    _isProcessingGreeting = true; // reuse the greeting overlay
    notifyListeners();
    try {
      if (_storageService.realismSettings.realismOneShotEval) {
        await _evaluateOneShotCall(); // step 10 thin (full in realism_evals)

        // Check for cancellation after one-shot eval
        if (_realismEvalCancelled) {
          debugPrint('[Realism] Retroactive scan cancelled');
          _realismEvalCancelled =
              false; // Reset the flag so future messages can proceed
          return;
        }
      } else {
        await Future.wait([
          _evaluateRelationshipCall(),
          Future.delayed(
            ChatService._kEvalDispatchStagger,
            () => _evaluateEmotionalStateCall(),
          ),
          Future.delayed(
            ChatService._kEvalDispatchStagger * 2,
            () => _evaluatePhysicalStateCall(),
          ),
          Future.delayed(
            ChatService._kEvalDispatchStagger * 3,
            () => _evaluateNarrativeCall(),
          ),
        ]);

        if (_realismEvalCancelled) {
          debugPrint('[Realism] Retroactive scan cancelled');
          _realismEvalCancelled = false;
          return;
        }
      }

      // Stamp the baseline on the most recent message so it persists
      if (_messages.isNotEmpty) {
        _messages.last.activeMetadata ??= {};
        _messages.last.activeMetadata!['emotion_label'] = _characterEmotion;
        _messages.last.activeMetadata!['realism_state'] =
            _captureRealismState();
      }
      await _saveChat();
      notifyListeners();
      debugPrint(
        '[Realism] Retroactive scan complete: emotion=$_characterEmotion, bond=${_relationshipService.affectionScore}, trust=${_relationshipService.trustLevel}',
      );
    } catch (e) {
      debugPrint('[Realism] Retroactive baseline scan failed: $e');
    } finally {
      _isProcessingGreeting = false;
      notifyListeners();
    }
  }

  /// Cycle the first message through alternate greetings
  Future<void> cycleGreeting(int direction) async {
    if (_activeCharacter == null || _messages.isEmpty) return;
    final allGreetings = _activeCharacter!.allGreetings;
    if (allGreetings.length <= 1) return;

    _greetingIndex = (_greetingIndex + direction) % allGreetings.length;
    if (_greetingIndex < 0) _greetingIndex += allGreetings.length;

    // Replace the first message text
    final greeting = allGreetings[_greetingIndex];
    _messages[0] = ChatMessage(
      text: _buildFirstMessage(_activeCharacter!, greetingText: greeting),
      sender: _activeCharacter!.name,
      isUser: false,
    );

    await _saveChat();
    notifyListeners();

    // Re-run baseline eval for the new greeting (skip pre-seeded V2.5 cards)
    if (_realismActiveThisMode &&
        _activeCharacter!.frontPorchExtensions == null) {
      _runPostGreetingEval();
    }
  }

  String _buildFirstMessage(CharacterCard character, {String? greetingText}) {
    String msg = greetingText ?? character.firstMessage;
    return _macroResolver.resolve(
      msg,
      MacroContext(
        userName: _userPersonaService.persona.name,
        characterName: character.name,
      ),
      section: 'firstMessage',
    );
  }
}
