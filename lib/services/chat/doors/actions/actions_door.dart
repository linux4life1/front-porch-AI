// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/session_state.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

/// Action Suggestions: the LLM-generated quick-reply actions under the last
/// bubble, and their clear.
///
/// Suggestions belong to the message they were made for (#329). Every chat
/// switch / load / fork / tail-delete path rebuilds the session's message
/// list, so "the anchor is still the last message" is the one check that
/// keeps suggestions from leaking onto another chat's latest bubble.
class ActionsDoor extends ChangeNotifier {
  ActionsDoor({
    required ChatSessionState session,
    required UserPersonaService personas,
    required LLMService Function() mouthLlm,
    required Stream<String> Function(GenerationParams params) mouthStream,
  }) : _session = session,
       _personas = personas,
       _mouthLlm = mouthLlm,
       _mouthStream = mouthStream;

  final ChatSessionState _session;
  final UserPersonaService _personas;

  /// The spoken-reply lane, and its stream (which waits out a GPU swap).
  final LLMService Function() _mouthLlm;
  final Stream<String> Function(GenerationParams params) _mouthStream;

  List<String> _suggestedActions = [];
  bool _isGeneratingActions = false;
  // The message the suggestions (or the in-flight generation) were made for.
  ChatMessage? _suggestedActionsAnchor;

  /// True while [anchor] is still the last message — same chat, same turn.
  bool _suggestionsStillFor(ChatMessage? anchor) =>
      anchor != null &&
      _session.messages.isNotEmpty &&
      identical(_session.messages.last, anchor);

  /// The suggestions for the chat's last message; empty once it moved on.
  List<String> get suggestedActions =>
      _suggestionsStillFor(_suggestedActionsAnchor)
      ? _suggestedActions
      : const [];

  bool get isGeneratingActions =>
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
    if (_session.messages.isEmpty) return;
    final anchor = _session.messages.last;
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
      if (!_mouthLlm().isReady) {
        debugPrint('[Actions] ✗ LLM not ready');
        return;
      }

      // Build context from recent messages (last 6)
      final recentMessages = _session.messages.length > 6
          ? _session.messages.sublist(_session.messages.length - 6)
          : _session.messages;

      final contextText = recentMessages
          .map((m) {
            return '${m.sender}: ${m.text}';
          })
          .join('\n');

      final userName = _personas.persona.name;

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
      await for (final chunk in _mouthStream(params)) {
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
