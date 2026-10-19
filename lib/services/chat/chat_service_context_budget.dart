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

  /// Records the send that produced [target] on its shown swipe. A Continue
  /// extends a reply whose prompt is already recorded, so it keeps that one.
  void _stampReplyContext(ChatMessage target, {required bool continuing}) {
    if (target.isUser) return;
    if (continuing && target.activeMetadata?[kReplyContextKey] != null) {
      return;
    }
    final send = _contextBudget.lastSend;
    if (send == null || send.isEmpty) return;
    target.activeMetadata ??= {};
    target.activeMetadata![kReplyContextKey] = send.toJson();
    trimReplyContextTexts(_messages);
  }

  /// The prompt record of the reply at [index], or null when none was kept.
  ContextViewerSnapshot? replyContextSnapshot(int index) {
    if (index < 0 || index >= _messages.length) return null;
    final m = _messages[index];
    if (m.isUser) return null;
    return replyContextOf(m);
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
      systemPrompt = g.systemPrompt.isNotEmpty
          ? g.systemPrompt
          : _observerMode
          ? observerModeSystemPrompt
          : defaultGroupSystemPrompt;
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
            '${buildSpeakerPersonaLine(name: speaker.name, personality: _growthDesk.effectivePersonality(speaker))}\n'
            '${speaker.mesExample}';
      }
    } else if (_activeCharacter != null) {
      final c = _activeCharacter!;
      systemPrompt = _resolveOneToOneBase(c);
      scenario = c.scenario;
      examples = c.mesExample;
      postHistory = c.postHistoryInstructions;
      final block = [
        if (c.description.trim().isNotEmpty) c.description.trim(),
        if (c.personality.trim().isNotEmpty) c.personality.trim(),
      ].join('\n');
      if (block.isNotEmpty) identity.writeln('${c.name}: $block');
    }

    if (_amendmentsAllowed) {
      systemPrompt = _storageService.generationSettings
          .withSystemPromptAddition(systemPrompt);
      postHistory = _storageService.generationSettings.withPostHistoryAddition(
        postHistory,
      );
    }

    // The send's own line format (think blocks stripped) and trim rules,
    // so the estimate shows what a send would carry, not the whole chat.
    final historyLines = _messages.map(_formatHistoryLine).toList();

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
        reserveTokens:
            _sessionGenSettings.resolveMaxLength(_storageService) + 50,
        trimChunk: kHistoryTrimChunk,
        overflowStart: overflowHistoryStart(_messages),
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

/// Per-chat prompt source resolution (prompt-picker SOW Phase 1). Lives
/// beside the budget estimate it must match; every ChatService prompt path
/// (generation, impersonation, estimate) reads these members.
extension ChatServicePromptSource on ChatService {
  /// Per-chat prompt source (prompt-picker SOW Phase 1). 1:1 only — groups
  /// keep the group-prompt hierarchy. `'user'` selects the global fallback
  /// as the base; null/`'card'` keeps the card-first hierarchy byte-for-byte.
  String? get _promptSourceOverride =>
      _activeGroup == null ? _sessionGenSettings.systemPromptSource : null;

  /// Whether #546's global additions append this turn. Only a 1:1 chat that
  /// switched amendments off suppresses them; null/true append as today.
  bool get _amendmentsAllowed =>
      !(_activeGroup == null &&
          _sessionGenSettings.promptAmendmentsEnabled == false);

  /// The 1:1 base chain with the per-chat source applied. Shared by the
  /// generation, impersonation, and budget-estimate paths so the live
  /// estimate always matches the sent prompt.
  String _resolveOneToOneBase(CharacterCard card) {
    if (_promptSourceOverride == 'user') {
      final fallback = _storageService.generationSettings.systemPrompt;
      return fallback.isNotEmpty ? fallback : defaultApiSystemPrompt;
    }
    if (card.systemPrompt.isNotEmpty) return card.systemPrompt;
    final fallback = _storageService.generationSettings.systemPrompt;
    return fallback.isNotEmpty ? fallback : defaultApiSystemPrompt;
  }

  /// The character key whose new 1:1 chat is waiting on the picker, or
  /// null when nothing is pending. The arm is tied to the chat it was made
  /// for: every load, fork, import and new-chat reset replaces
  /// [_sessionGenSettings], so a picker armed for one chat and left
  /// unanswered never surfaces on the next one.
  String? get promptPickerPendingFor {
    final pending = _promptPickerPending;
    final key = _activeOneToOneKey;
    if (pending == null || key == null) return null;
    if (!identical(pending.chat, _sessionGenSettings) || pending.key != key) {
      return null;
    }
    return key;
  }

  String? get _activeOneToOneKey {
    final card = _activeGroup == null ? _activeCharacter : null;
    return card == null ? null : stableGroupIdFrom(card.imagePath, card.name);
  }

  /// Prompt-picker SOW trigger: a new 1:1 chat whose card ships its own
  /// system prompt asks the user which base wins — unless a choice was
  /// remembered for this character, which is applied instead.
  void _armPromptPickerIfDue() {
    _promptPickerPending = null;
    final card = _activeCharacter;
    if (_activeGroup != null || card == null || card.systemPrompt.isEmpty) {
      return;
    }
    final key = stableGroupIdFrom(card.imagePath, card.name);
    final remembered =
        _storageService.generationSettings.promptPickerChoices[key];
    if (remembered != null) {
      _applyPromptPreset(remembered);
      return;
    }
    _promptPickerPending = (key: key, chat: _sessionGenSettings);
  }

  /// Maps a picker preset onto the per-chat pair. 'card+amend' and 'card'
  /// keep the card chain byte-identical to the inherited default.
  void _applyPromptPreset(String preset) {
    _sessionGenSettings.systemPromptSource = preset == 'user' ? 'user' : 'card';
    _sessionGenSettings.promptAmendmentsEnabled = preset != 'card';
  }

  /// The picker's answer: write the per-chat pair, persist the remembered
  /// choice ("Remember my choice"), or forget it so the next new chat asks
  /// again ("Ask me every chat"). A null [preset] (dismissed dialog) keeps
  /// this chat on today's inherited behavior.
  Future<void> applyPromptSourceChoice({
    String? preset,
    bool remember = false,
    bool askEveryChat = false,
  }) async {
    // Always the open 1:1 card's key, never a leftover arm: an answer can
    // only describe the chat on screen. Groups have no per-chat source.
    final key = _activeOneToOneKey;
    _promptPickerPending = null;
    if (preset != null && key != null) {
      _applyPromptPreset(preset);
      if (askEveryChat) {
        await _storageService.generationSettings.clearPromptPickerChoice(key);
      } else if (remember) {
        await _storageService.generationSettings.setPromptPickerChoice(
          key,
          preset,
        );
      }
      if (_currentSessionId != null) await _saveChat();
    }
    notifyListeners();
  }

  /// Chat Settings' System prompt row from outside the picker (the web
  /// app's per-chat drawer; desktop writes [sessionGenSettings] directly).
  /// 1:1 only, like the source itself. Editing the row answers any picker
  /// still waiting on this chat.
  Future<bool> setPromptSource({String? source, bool? amendments}) async {
    if (_activeOneToOneKey == null) return false;
    _promptPickerPending = null;
    _sessionGenSettings.systemPromptSource = source;
    _sessionGenSettings.promptAmendmentsEnabled = amendments;
    if (_currentSessionId != null) await _saveChat();
    notifyListeners();
    return true;
  }

  /// The per-chat prompt source as the web app shows it: the row's state,
  /// plus the picker's prompts while a new chat is waiting on it. Null in
  /// groups and with no chat open.
  Map<String, Object?>? get promptSourceJson {
    final card = _activeGroup == null ? _activeCharacter : null;
    if (card == null) return null;
    final g = _storageService.generationSettings;
    return {
      'source': _sessionGenSettings.systemPromptSource,
      'amendments': _sessionGenSettings.promptAmendmentsEnabled,
      if (promptPickerPendingFor != null)
        'picker': {
          'characterName': card.name,
          'cardPrompt': card.systemPrompt,
          'userPrompt': g.systemPrompt,
          'amendment': g.additionalSystemPrompt,
        },
    };
  }
}
