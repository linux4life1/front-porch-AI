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

/// Prompt-block builders: the Author's Note (setter + strength-modulated
/// wrapper), the user-persona block, and the time-skip anchor and bridge
/// context. All read state only; identical in 1:1 and group modes.
extension ChatServicePromptBlocks on ChatService {
  void setAuthorNote(String note, {int? strength}) {
    _authorNote = note;
    if (strength != null) _authorNoteStrength = strength;
    _saveChat();
    notifyListeners();
  }

  /// Build the Author's Note block with strength-modulated wrapper text.
  /// Strength 1–3: subtle suggestion, 4–7: standard, 8–10: urgent directive.
  String _buildAuthorNoteBlock() {
    if (_authorNote.isEmpty) return '';
    if (_authorNoteStrength <= 3) {
      return '[Author\'s Note (gentle suggestion): $_authorNote]\n';
    } else if (_authorNoteStrength <= 7) {
      return '[Author\'s Note: $_authorNote]\n';
    } else {
      return '[Author\'s Note (IMPORTANT — apply immediately): $_authorNote]\n';
    }
  }

  /// Build the user persona block for the generation prompt.
  /// The user's self-description is ground truth. (What the character has
  /// *learned* about the user now lives in their per-chat Journal cards —
  /// injected separately via journal_injection — not here.)
  Future<String> _buildUserPersonaBlock(String userName) async {
    final persona = _userPersonaService.persona;
    final personaText = persona.persona.trim();
    final safeUserName = userName.replaceAll(RegExp(r'[\n\r"]'), ' ').trim();

    final buf = StringBuffer();
    // ALWAYS establish the user's identity by NAME — even with no persona text.
    // Otherwise the model only sees "$userName:" history labels and invents a
    // generic descriptor ("the boy"/"the girl") for the human. (Previously this
    // returned '' entirely when the persona had no description.)
    if (personaText.isNotEmpty) {
      final safePersonaText = personaText
          .replaceAll(RegExp(r'[\n\r"]'), ' ')
          .trim();
      buf.writeln("$safeUserName's Persona: $safePersonaText");
    } else {
      buf.writeln('$safeUserName is the human you are talking with.');
    }
    // The model HAS the name above — nudge it to actually use it instead of
    // reaching for a generic epithet for the human.
    buf.writeln(
      'Always refer to $safeUserName by name; never substitute a generic '
      'descriptor like "the boy", "the girl", or "the user".',
    );
    buf.writeln();
    return buf.toString();
  }

  /// The time-skip anchor for this reply prompt: '' unless the clock runs
  /// and a skip of hours or more is this turn's or a recent one
  /// (time_skip_anchor.dart).
  String _timeSkipAnchorBlock() {
    if (!_clockRunning) return '';
    final meta = _pendingRealismMetadata;
    final pending =
        (meta?[kSkipMinutesMeta] ?? meta?[kLongSkipMinutesMeta]) as num?;
    return buildTimeSkipAnchor(
      latestLongSkip(
        messages: _session.messages,
        clock: _timeService.clock,
        pendingMinutes: pending?.toInt(),
      ),
    );
  }

  /// What the bridge narrator should know beyond the last lines: who the
  /// cast are, their bond with the user, the place, the recap and the
  /// promises still open. Same fields in 1:1 and group.
  TimeSkipBridgeContext _timeSkipBridgeContext() {
    final cast = _activeGroup != null
        ? _groupCharacters.toList()
        : [?_session.activeCharacter];
    final user = _userPersonaService.persona.name;
    String tone(CharacterCard c) {
      if (!_realismEnabled) return '';
      final tier = _activeGroup != null
          ? _groupRealism[_getCharacterIdFromCard(c)]?.longTermTier
          : _relationshipService.longTermTier;
      if (tier == null) return '';
      return 'with $user: ${RelationshipService.longTermTierLabel(tier)}';
    }

    final sessionId = _session.currentSessionId;
    final threads = <String>[
      if (sessionId != null)
        for (final c in cast)
          for (final p
              in _promiseDebtService.cachedOpen(
                    sessionId,
                    _getCharacterIdFromCard(c),
                  ) ??
                  const <OpenPromise>[])
            p.party == 'user'
                ? '$user promised ${c.name}: ${p.text}'
                : '${c.name} promised $user: ${p.text}',
    ];
    final primaryId = _chatPlaceSlots.primaryId;
    final world = primaryId == null
        ? null
        : _worldRepository.resolveWorld(primaryId);
    final place = world == null
        ? ''
        : clipGuestCite('${world.name}. ${world.description}', max: 240);
    return TimeSkipBridgeContext(
      castNotes: [for (final c in cast) bridgeCastNote(c, tone: tone(c))],
      place: place,
      recap: _storageService.memorySettings.journalEnabled ? _summary : '',
      openThreads: threads.take(4).toList(),
    );
  }
}

/// The chat's macro context and the realism state block the prompt reads.
extension ChatServicePromptContext on ChatService {
  /// Full chat-context MacroContext for prompt builds: card fields, group
  /// roster, last messages, idle clock, and the macro variable stores
  /// (locals ride _loreTimedEffects per chat; globals live in settings).
  /// Shared by generation, impersonation, and lore-key resolution.
  MacroContext _buildChatMacroContext(
    CharacterCard speaking, {
    String? scenario,
  }) {
    ChatMessage? lastUser;
    ChatMessage? lastChar;
    for (final m in _session.messages.reversed) {
      if (m.characterId == '__director__') continue;
      lastUser ??= m.isUser ? m : null;
      lastChar ??= !m.isUser ? m : null;
      if (lastUser != null && lastChar != null) break;
    }
    return MacroContext(
      userName: _userPersonaService.persona.name,
      characterName: speaking.name,
      chatId: _session.currentSessionId,
      characterId: speaking.dbId,
      description: speaking.description,
      personality: _growthDesk.effectivePersonality(speaking),
      scenario: scenario ?? speaking.scenario,
      userPersona: _userPersonaService.persona.persona,
      groupMemberNames: _activeGroup != null
          ? [for (final c in _groupCharacters) c.name]
          : null,
      lastMessage: _session.messages.isNotEmpty
          ? _session.messages.last.displayText
          : null,
      lastUserMessage: lastUser?.displayText,
      lastCharMessage: lastChar?.displayText,
      idleDuration: _lastUserMessageAt == null
          ? null
          : DateTime.now().difference(_lastUserMessageAt!),
      getLocalVar: (n) => _loreTimedEffects.localMacroVars[n],
      setLocalVar: (n, v) => _loreTimedEffects.localMacroVars[n] = v,
      getGlobalVar: _storageService.lorebookSettings.getGlobalMacroVar,
      setGlobalVar: _storageService.lorebookSettings.setGlobalMacroVar,
    );
  }

  /// The words-only state composer — the single source of the
  /// "[How <Name> is right now: …]" block the model receives (salience-gated
  /// natural language, no simulation scalars; see
  /// docs/design/prompt-state-injection.md §3).
  String _getRealismStateInjection() =>
      _realismStateInjection.buildRealismStateInjection();
}
