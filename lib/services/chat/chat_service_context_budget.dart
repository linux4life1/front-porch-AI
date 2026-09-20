// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

/// Context Budget load/save/estimate — kept out of the god file body.
extension ChatServiceContextBudget on ChatService {
  void _clearContextBudget() => _contextBudget.clear();

  Future<void> _loadContextBudgetForSession(String sessionId) async {
    final json = await _db.getContextBudgetJson(sessionId);
    _contextBudget.loadFromJson(json);
  }

  Future<void> _persistContextBudgetForSession(String sessionId) async {
    final json = _contextBudget.persistJson(contextLimit: contextSize);
    await _db.setContextBudgetJson(sessionId, json);
  }

  /// Live estimate from the open chat (no model call). Context Viewer refresh.
  Future<void> _estimateContextBudgetNow() async {
    if (_activeCharacter == null && _activeGroup == null) return;

    final identity = StringBuffer();
    var systemPrompt = '';
    var scenario = '';
    var examples = '';
    var postHistory = '';

    var personaBlock = '';
    var speakerCard = '';
    if (_activeGroup != null) {
      final g = _activeGroup!;
      systemPrompt = g.systemPrompt;
      scenario = g.scenario.isNotEmpty
          ? g.scenario
          : (_groupCharacters.isNotEmpty
                ? _groupCharacters.first.scenario
                : '');
      personaBlock = buildGroupRosterLine(
        memberNames: [for (final c in _groupCharacters) c.name],
        userName: _userPersonaService.persona.name,
        observerMode: _observerMode,
      );
      final speaker =
          _groupManager?.nextSpeaker ??
          (_groupCharacters.isNotEmpty ? _groupCharacters.first : null);
      if (speaker != null) {
        final others = [
          for (final c in _groupCharacters)
            if (c.name != speaker.name) c.name,
        ];
        speakerCard =
            '${(speaker.isLite ? buildLiteGroupTurnNote : buildSpeakerTurnNote)(speakerName: speaker.name, otherMemberNames: others, userName: _userPersonaService.persona.name, observerMode: _observerMode)}'
            '${buildSpeakerPersonaLine(name: speaker.name, personality: _getEffectivePersonality(speaker))}\n'
            '${speaker.mesExample}';
      }
    } else if (_activeCharacter != null) {
      final c = _activeCharacter!;
      systemPrompt = c.systemPrompt;
      scenario = c.scenario;
      examples = c.mesExample;
      postHistory = c.postHistoryInstructions;
      final block = [
        if (c.description.trim().isNotEmpty) c.description.trim(),
        if (c.personality.trim().isNotEmpty) c.personality.trim(),
      ].join('\n');
      if (block.isNotEmpty) identity.writeln('${c.name}: $block');
    }

    final historyLines = <String>[];
    for (final m in _messages) {
      if (m.characterId == '__director__') {
        historyLines.add('[Director: ${m.text}]');
      } else {
        historyLines.add('${m.sender}: ${m.text}');
      }
    }

    final snap = buildContextBudgetEstimate(
      ContextBudgetEstimateInput(
        userName: _userPersonaService.persona.name,
        userPersonaText: _userPersonaService.persona.persona,
        systemPrompt: systemPrompt,
        identityBlock: identity.toString(),
        personaBlock: personaBlock,
        speakerCard: speakerCard,
        scenario: scenario,
        examples: examples,
        postHistory: postHistory,
        authorNote: _authorNote,
        historyLines: historyLines,
        contextLimit: contextSize,
      ),
    );

    if (snap.isEmpty) {
      // Keep sticky last-send in the store; only clear the on-screen view if
      // we had nothing else — load sticky back for display if present.
      final stickyJson = _contextBudget.persistJson(contextLimit: contextSize);
      if (stickyJson != null) {
        _contextBudget.loadFromJson(stickyJson);
      } else {
        _contextBudget.clear();
      }
      notifyListeners();
      return;
    }

    _contextBudget.apply(snap);
    notifyListeners();
  }
}
