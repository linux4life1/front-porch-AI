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

  /// Clear suggestions (called when user sends any message).
  void clearSuggestions() {
    if (_suggestedActions.isNotEmpty || _isGeneratingActions) {
      _suggestedActions = [];
      _isGeneratingActions = false;
      notifyListeners();
    }
  }

  /// Generate action suggestions on demand (called from UI button).
  Future<void> generateActions() async {
    if (_isGeneratingActions) return;
    if (_llmProvider == null) return;
    if (_messages.isEmpty) return;

    _isGeneratingActions = true;
    _suggestedActions = [];
    notifyListeners();

    try {
      final llmService = _llmProvider!.activeService;
      if (!llmService.isReady) {
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
          '1. Kiss her and pull her closer\n'
          '2. Ask about her day at work\n'
          '3. Tease her by pulling away\n'
          '4. Suggest moving somewhere private\n\n'
          'Examples of BAD actions (too long, too detailed):\n'
          '1. *I lean in and press my lips against hers, tasting...*\n\n'
          'Recent conversation:\n$contextText\n\n'
          'Write 4 short action labels for $userName (numbered 1-4, one per line):';

      final params = GenerationParams(
        prompt: prompt,
        maxLength: 300,
        temperature: 0.8,
        stopSequences: ['\n\n\n'],
      );

      String responseText = '';
      await for (final chunk in llmService.generateStream(params)) {
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
      _isGeneratingActions = false;
      notifyListeners();
    }
  }
}
