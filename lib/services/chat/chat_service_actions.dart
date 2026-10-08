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

/// Action Suggestions — clear + LLM-generated quick-reply actions.
/// Extracted verbatim (zero behaviour change) to shrink the god file.
extension ChatServiceActions on ChatService {
  // ── Action Suggestions ────────────────────────────────────────────────

  /// True while [anchor] is still the last message — same chat, same turn.
  /// Every switch / load / fork / tail-delete path rebuilds `_messages`, so
  /// this one check is what keeps suggestions off another chat's bubble.
  bool _suggestionsStillFor(ChatMessage? anchor) =>
      anchor != null &&
      _messages.isNotEmpty &&
      identical(_messages.last, anchor);

  List<String> get _anchoredSuggestedActions =>
      _suggestionsStillFor(_suggestedActionsAnchor)
      ? _suggestedActions
      : const [];

  bool get _anchoredIsGeneratingActions =>
      _isGeneratingActions && _suggestionsStillFor(_suggestedActionsAnchor);

  /// Clear suggestions (called when user sends any message).
  void clearSuggestions() {
    if (_suggestedActions.isNotEmpty ||
        _isGeneratingActions ||
        _suggestedActionsAnchor != null) {
      _suggestedActions = [];
      _isGeneratingActions = false;
      _suggestedActionsAnchor = null;
      notifyListeners();
    }
  }

  /// Generate action suggestions on demand (called from UI button).
  Future<void> generateActions() async {
    if (_messages.isEmpty) return;
    final anchor = _messages.last;
    // A double tap on the same message is ignored; a run left behind by
    // another chat is superseded (it checks the anchor before landing).
    if (_isGeneratingActions && identical(_suggestedActionsAnchor, anchor)) {
      return;
    }

    _isGeneratingActions = true;
    _suggestedActions = [];
    _suggestedActionsAnchor = anchor;
    notifyListeners();

    try {
      if (!_mouthLlm.isReady) {
        debugPrint('[Actions] ✗ LLM not ready');
        return;
      }

      // Build context from recent messages (last 6)
      final recentMessages = _messages.length > 6
          ? _messages.sublist(_messages.length - 6)
          : _messages;

      final contextText = recentMessages
          .map((m) {
            return '${m.sender}: ${m.text}';
          })
          .join('\n');

      final userName = _userPersonaService.persona.name;

      final prompt =
          'Suggest 4 short actions $userName could do next. '
          'Each action must be a BRIEF LABEL (5-10 words max) describing what to do, NOT a full response. '
          'Think of these as button labels or menu items.\n\n'
          'Examples of GOOD actions:\n'
          '1. Kiss them and pull them closer\n'
          '2. Ask about their day at work\n'
          '3. Tease them by pulling away\n'
          '4. Suggest moving somewhere private\n\n'
          'Examples of BAD actions (too long, too detailed):\n'
          '1. *I lean in and press my lips against theirs, tasting...*\n\n'
          'Recent conversation:\n$contextText\n\n'
          'Write 4 short action labels for $userName (numbered 1-4, one per line):';

      final params = GenerationParams(
        prompt: prompt,
        maxLength: 300,
        temperature: 0.8,
        reasoningEnabled: false,
        reasoningMaxTokens: 0,
        mandatoryReasoningHeadroom: true,
        stopSequences: ['\n\n\n'],
      );

      String responseText = '';
      await for (final chunk in _mouthGenerateStream(params)) {
        responseText += chunk;
      }
      responseText = responseText.trim();

      debugPrint('[Actions] Raw response:\n$responseText');

      // Parse numbered list: "1. Action", "-", "*", or bullet
      final lines = responseText.split('\n');
      var actions = <String>[];

      for (final line in lines) {
        var cleanLine = line
            .trim()
            .replaceAll(RegExp(r'^\*+|\*+$|^_+|_+$'), '')
            .trim();
        final match = RegExp(
          r'^\s*(?:\d+[\.\)]|[-*•]|)\s*(.+)$',
        ).firstMatch(cleanLine);
        if (match != null) {
          final action = match.group(1)!.trim().replaceAll(RegExp(r'\*$'), '');
          // Ignore conversational filler lines
          if (action.isNotEmpty &&
              !action.toLowerCase().contains('here are') &&
              !action.endsWith(':')) {
            actions.add(action);
          }
        }
      }

      // Fallback if LLM just output raw lines
      if (actions.isEmpty) {
        for (final line in lines) {
          final cleanLine = line.trim();
          if (cleanLine.isNotEmpty &&
              !cleanLine.endsWith(':') &&
              !cleanLine.toLowerCase().contains('here are')) {
            actions.add(cleanLine);
          }
        }
      }

      // Superseded by a newer tap, or the chat moved on underneath us with
      // no newer tap at all — either way there is no bubble to land on.
      if (!identical(_suggestedActionsAnchor, anchor) ||
          !_suggestionsStillFor(anchor)) {
        debugPrint('[Actions] ✗ Chat moved on before suggestions landed');
        return;
      }
      if (actions.isNotEmpty) {
        _suggestedActions = actions.take(6).toList(); // cap at 6
        debugPrint(
          '[Actions] ✅ Generated ${_suggestedActions.length} suggestions',
        );
      } else {
        debugPrint('[Actions] ✗ Could not parse any actions from response');
      }
    } catch (e) {
      debugPrint('[Actions] ✗ Generation failed: $e');
    } finally {
      // A superseded run must not touch the flag the newer run now owns.
      if (identical(_suggestedActionsAnchor, anchor)) {
        _isGeneratingActions = false;
        if (_suggestionsStillFor(anchor)) {
          notifyListeners();
        } else {
          // The chat moved on: drop the orphan rather than keep it around,
          // and leave the new chat's listeners alone — nothing changed there.
          _suggestedActions = [];
          _suggestedActionsAnchor = null;
        }
      }
    }
  }
}
