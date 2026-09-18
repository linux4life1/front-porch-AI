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

/// Lore/world helpers for prompt injection: lorebook scanner/injector
/// builders, the group lore enumerator, world/biome reload + attach, and
/// the chat macro-context builder. Leaf builders live on
/// `chat_service_wiring_injection_leaves.dart`.
extension ChatServiceWiringInjection on ChatService {
  /// Returns all currently active lorebook entries (enabled + (triggered or constant))
  /// for the active group context. Includes:
  /// - Group-level lorebook
  /// - Lorebooks from worlds attached to the group
  /// - Per-character lorebooks (and their worlds) if `inheritCharacterLorebooks` is true
  ///
  /// This is intended for UI display (e.g. sidebar) to show what lore is currently "in play".
  List<LorebookEntry> getActiveGroupLoreEntries() {
    if (_activeGroup == null) return const [];
    // Post-group-filter truth (what actually injects), deduplicated by
    // content to avoid showing the exact same lore text twice.
    final seen = <String>{};
    return [
      for (final e in _lorebookInjector.activeEntries(
        sessionSeed: _currentSessionId ?? '',
      ))
        if (seen.add(e.content)) e,
    ];
  }

  // ── Lorebook scanner (extracted to LorebookScanner) ────────────────────────
  // Keyword scan (set isTriggered + remaining=sticky), decrement (post-AI
  // pre-set only), and reset of non-const trigger state live in
  // _lorebookScanner (plain class). ChatService owns via late final + thin
  // delegations at *all* call sites.
  // The entry universe comes from ONE enumerator: _collectLoreRefs →
  // collectLoreEntryRefs (group book + group worlds + member/1:1 books +
  // attached worlds). Scanning always covers everything (inherit=true);
  // the group's inheritCharacterLorebooks flag only filters injection and
  // the sidebar (getActiveGroupLoreEntries), matching prior behavior.
  // 1:1 vs group parity: scanner processes whatever the enumerator yields.
  // Reset hygiene: resetLorebookTriggerState() called from every keep-sync
  // site (startNewChat 1:1+group/ext+non-ext, setActive*, _load empty/
  // 0-session, setActiveGroup defensive+post, etc).
  LorebookScanner _buildLorebookScanner() {
    return LorebookScanner(
      onNotify: notifyListeners,
      getEntryRefs: () => _collectLoreRefs(inheritOverride: true),
      getRecentMessages: (count) {
        // Scan think-stripped prose (promptText), not raw .text — reasoning
        // that names a lore key used to false-trigger entries into the next
        // prompt (prompt-assembly audit 2026-08-11).
        final includeNames = _storageService.lorebookSettings.includeNames;
        final start = _messages.length > count ? _messages.length - count : 0;
        return [
          for (final m in _messages.sublist(start))
            m.characterId == '__director__'
                ? '[Director: ${m.text}]'
                : (includeNames ? m.toPromptHistoryLine() : m.promptText),
        ];
      },
      getGlobalScanDepth: () => _storageService.lorebookSettings.scanDepth,
      getRecursiveScan: () => _storageService.lorebookSettings.recursiveScan,
      getMaxRecursionSteps: () =>
          _storageService.lorebookSettings.maxRecursionSteps,
      timedEffects: _loreTimedEffects,
      getChatLength: () => _messages.length,
      resolveKeyMacros: (key) {
        final ch =
            _activeCharacter ??
            (_groupCharacters.isNotEmpty ? _groupCharacters.first : null);
        if (ch == null) return key;
        return _macroResolver.resolve(
          key,
          _buildChatMacroContext(ch),
          section: 'lorekeys',
        );
      },
    );
  }

  // Pure-read injection engine (positions, ordering, budget, inclusion
  // groups). Consumes the same enumerator as the scanner but honors the
  // group's inherit flag (injection semantics).
  LorebookInjector _buildLorebookInjector() {
    return LorebookInjector(
      getEntryRefs: () => _collectLoreRefs(),
      getSettings: () => _storageService.lorebookSettings,
      isStickyActive: (e) =>
          _loreTimedEffects.isStickyActive(e, _messages.length),
    );
  }

  // The group lorebook is stored as a JSON string on the group row. Parse it
  // ONCE and keep the live instance — the scanner writes trigger state onto
  // these entry objects, so a fresh parse per read (the pre-Phase-2 behavior)
  // silently discarded every keyword trigger and left group books constant-only.
  // String-compare invalidation: editing the book in group settings replaces
  // the JSON string, which re-parses (and intentionally clears trigger state,
  // same as editing semantics elsewhere).
  Lorebook? get _activeGroupLorebook {
    final raw = _activeGroup?.groupLorebook ?? '';
    if (raw.isEmpty) {
      _cachedGroupBook = null;
      _cachedGroupBookJson = null;
      return null;
    }
    if (_cachedGroupBookJson != raw) {
      try {
        _cachedGroupBook = Lorebook.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        _cachedGroupBook = Lorebook(entries: []);
      }
      _cachedGroupBookJson = raw;
    }
    return _cachedGroupBook;
  }

  Future<void> _reloadChatWorldIds() async {
    final sid = _currentSessionId;
    if (sid == null) {
      _chatPlaceSlots = const ChatPlaceSlots();
      _biomeSchedule = const BiomeSchedule();
      return;
    }
    try {
      // A chat opened BEFORE its character had a world predates any decision
      // about attachments, so its empty list means "undecided" — give it the
      // character's worlds now. Chats where the user actually chose (including
      // choosing none) are flagged and skipped, so a deliberate detach sticks.
      final refs = _activeGroup == null
          ? (_activeCharacter?.worldNames ?? const <String>[])
          : const <String>[];
      if (refs.isNotEmpty) {
        await _worldRepository.backfillChatWorldsFromCharacter(
          chatId: sid,
          characterWorldRefs: refs,
        );
      }
      final slots = await _worldRepository.getChatWorldAttachments(sid);
      _chatPlaceSlots = ChatPlaceSlots(
        primaryId: slots.primaryId,
        loreIds: List.unmodifiable(slots.loreIds),
      );
    } catch (e) {
      debugPrint('[ChatService] chat world load failed: $e');
      _chatPlaceSlots = const ChatPlaceSlots();
    }
    await _reloadBiomeSchedule();
  }

  Future<void> _reloadBiomeSchedule() async {
    final sid = _currentSessionId;
    if (sid == null) {
      _biomeSchedule = const BiomeSchedule();
      return;
    }
    try {
      final rows = await _worldRepository.getChatBiomeSpanRows(sid);
      _biomeSchedule = BiomeSchedule.fromJsonSpans(
        rows: rows,
        worldDefault: _worldDefaultBiome,
      );
    } catch (e) {
      debugPrint('[ChatService] biome schedule load failed: $e');
      _biomeSchedule = BiomeSchedule(worldDefault: _worldDefaultBiome);
    }
  }

  Future<void> setChatWorldIds(List<String> worldIds) async {
    final sid = _currentSessionId;
    if (sid == null) return;
    // Flat list:
    // - Primary still listed → keep role, remaining become lore (no auto-promote).
    // - Primary empty → seed-style partition (first climate-on → Setting).
    // - Primary dropped from list → stay empty; all listed ids are lore.
    final currentPrimary = _chatPlaceSlots.primaryId;
    if (currentPrimary != null && worldIds.contains(currentPrimary)) {
      await setChatPlaceSlots(
        primaryId: currentPrimary,
        loreIds: [
          for (final id in worldIds)
            if (id != currentPrimary) id,
        ],
      );
      return;
    }
    if (currentPrimary == null) {
      final slots = partitionLinkedPlaces(
        worldIds: worldIds,
        isClimateEnabled: (id) =>
            _worldRepository.resolveWorld(id)?.climateEnabled ?? false,
      );
      await setChatPlaceSlots(
        primaryId: slots.primaryId,
        loreIds: slots.loreIds,
      );
      return;
    }
    await setChatPlaceSlots(primaryId: null, loreIds: worldIds);
  }

  /// Setting + Lore writer (Story Tools / web). Empty both = decided empty.
  Future<void> setChatPlaceSlots({
    String? primaryId,
    List<String> loreIds = const [],
  }) async {
    final sid = _currentSessionId;
    if (sid == null) return;
    await _worldRepository.setChatWorldAttachments(
      sid,
      primaryId: primaryId,
      loreIds: loreIds,
    );
    final resolvedPrimary = (primaryId != null && primaryId.isNotEmpty)
        ? primaryId
        : null;
    _chatPlaceSlots = ChatPlaceSlots(
      primaryId: resolvedPrimary,
      loreIds: List.unmodifiable([
        for (final id in loreIds)
          if (id.isNotEmpty && id != resolvedPrimary) id,
      ]),
    );
    await _reloadBiomeSchedule();
    notifyListeners();
  }

  /// Insert a mid-chat climate changeover from [dayCount] onward.
  /// No-op when Primary is empty or climate-off (lore never authors climate).
  Future<void> setChatClimate(Biome biome) async {
    final sid = _currentSessionId;
    if (sid == null) return;
    final primaryId = _chatPlaceSlots.primaryId;
    final primary = primaryId == null
        ? null
        : _worldRepository.resolveWorld(primaryId);
    if (!primaryWorldAllowsClimate(primary)) return;
    final day = _timeService.dayCount < 1 ? 1 : _timeService.dayCount;
    await _worldRepository.setChatBiome(
      chatId: sid,
      dayCount: day,
      biome: biome,
    );
    await _reloadBiomeSchedule();
    notifyListeners();
  }

  List<LoreEntryRef> _collectLoreRefs({bool? inheritOverride}) {
    return collectLoreEntryRefs(
      characters: _activeGroup != null
          ? _groupCharacters
          : (_activeCharacter != null
                ? [_activeCharacter!]
                : const <CharacterCard>[]),
      chatLorebook: _loreTimedEffects.chatLorebook,
      groupLorebook: _activeGroupLorebook,
      chatWorldIds: _chatPlaceSlots.allIds,
      // Decided empty must stay empty — never ghost to group.worldIds.
      groupWorldNames: const [],
      resolveWorld: _worldRepository.resolveWorld,
      inherit:
          inheritOverride ?? (_activeGroup?.inheritCharacterLorebooks ?? true),
    );
  }

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
    for (final m in _messages.reversed) {
      if (m.characterId == '__director__') continue;
      lastUser ??= m.isUser ? m : null;
      lastChar ??= !m.isUser ? m : null;
      if (lastUser != null && lastChar != null) break;
    }
    return MacroContext(
      userName: _userPersonaService.persona.name,
      characterName: speaking.name,
      chatId: _currentSessionId,
      characterId: speaking.dbId,
      description: speaking.description,
      personality: _getEffectivePersonality(speaking),
      scenario: scenario ?? speaking.scenario,
      userPersona: _userPersonaService.persona.persona,
      groupMemberNames: _activeGroup != null
          ? [for (final c in _groupCharacters) c.name]
          : null,
      lastMessage: _messages.isNotEmpty ? _messages.last.displayText : null,
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
}
