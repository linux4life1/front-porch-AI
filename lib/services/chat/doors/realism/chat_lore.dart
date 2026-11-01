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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// The chat's lore: the lorebook scanner and the injector over ONE entry
/// enumerator, the parsed group book, and the per-chat timed effects.
///
/// The entry universe comes from [collectLoreRefs] → collectLoreEntryRefs
/// (group book + chat worlds + member/1:1 books + attached worlds). Scanning
/// always covers everything (inherit=true, no speaker). Injection honors
/// inheritCharacterLorebooks and, on a group turn, only the speaking card's
/// character book (ST Swap). 1:1 vs group parity: the scanner processes
/// whatever the enumerator yields, and lore enumerates once per world id.
class ChatLore {
  ChatLore(this._g);

  final RealismGraph _g;

  /// Per-chat lore session state (ST sticky/cooldown timers, macro locals,
  /// chat-scoped lorebook) — persisted inside the session's groupRealismState
  /// blob via additive keys, hydrated on session load, cleared at session
  /// boundaries via the scanner reset.
  final LorebookTimedEffects timedEffects = LorebookTimedEffects();

  // The group lorebook is stored as a JSON string on the group row. Parse it
  // ONCE and keep the live instance — the scanner writes trigger state onto
  // these entry objects, so a fresh parse per read (the pre-Phase-2 behavior)
  // silently discarded every keyword trigger and left group books constant-only.
  // String-compare invalidation: editing the book in group settings replaces
  // the JSON string, which re-parses (and intentionally clears trigger state,
  // same as editing semantics elsewhere).
  Lorebook? _cachedGroupBook;
  String? _cachedGroupBookJson;
  bool _groupLorebookUnreadable = false;

  ChatSessionState get _session => _g.session;
  StorageService get _storageService => _g.deps.services.storage;

  // Keyword scan (set isTriggered + remaining=sticky), decrement (post-AI
  // pre-set only), and reset of non-const trigger state live in the scanner
  // (plain class). Reset hygiene: resetLorebookTriggerState() is called from
  // every keep-sync site (new chat 1:1+group, entry, load, group re-entry).
  late final LorebookScanner scanner = LorebookScanner(
    onNotify: _g.deps.notify,
    getEntryRefs: () => collectLoreRefs(inheritOverride: true),
    getRecentMessages: (count) {
      // Scan think-stripped prose (promptText), not raw .text — reasoning
      // that names a lore key used to false-trigger entries into the next
      // prompt (prompt-assembly audit 2026-08-11).
      final includeNames = _storageService.lorebookSettings.includeNames;
      final start = _session.messages.length > count
          ? _session.messages.length - count
          : 0;
      return [
        for (final m in _session.messages.sublist(start))
          if (!m.isStatusBanner)
            m.characterId == '__director__'
                ? m.toPromptHistoryLine()
                : (includeNames ? m.toPromptHistoryLine() : m.promptText),
      ];
    },
    getGlobalScanDepth: () => _storageService.lorebookSettings.scanDepth,
    getRecursiveScan: () => _storageService.lorebookSettings.recursiveScan,
    getMaxRecursionSteps: () =>
        _storageService.lorebookSettings.maxRecursionSteps,
    timedEffects: timedEffects,
    getChatLength: () => _session.messages.length,
    resolveKeyMacros: (key) {
      final ch =
          _session.activeCharacter ??
          (_session.groupCharacters.isNotEmpty
              ? _session.groupCharacters.first
              : null);
      if (ch == null) return key;
      return _g.deps.services.macros.resolve(
        key,
        _g.deps.hooks.macroContext(ch),
        section: 'lorekeys',
      );
    },
  );

  // Pure-read injection engine (positions, ordering, budget, inclusion
  // groups). Consumes the same enumerator as the scanner but honors the
  // group's inherit flag (injection semantics).
  late final LorebookInjector injector = LorebookInjector(
    getEntryRefs: () => collectLoreRefs(),
    getSettings: () => _storageService.lorebookSettings,
    isStickyActive: (e) =>
        timedEffects.isStickyActive(e, _session.messages.length),
  );

  /// All currently active lorebook entries (enabled + (triggered or
  /// constant)) for the active group: the group book, the books of worlds
  /// attached to the group, and the speaking character's book (and their
  /// worlds) when `inheritCharacterLorebooks` is on — not every member's.
  /// For UI display (the sidebar) of what lore is "in play".
  List<LorebookEntry> activeGroupLoreEntries() {
    if (_session.activeGroup == null) return const [];
    // Post-group-filter truth (what actually injects), deduplicated by
    // content to avoid showing the exact same lore text twice.
    final seen = <String>{};
    return [
      for (final e in injector.activeEntries(
        sessionSeed: _session.currentSessionId ?? '',
      ))
        if (seen.add(e.content)) e,
    ];
  }

  // An unreadable book is logged once per stored string and flagged for the
  // sidebar and the phone; it is never quietly read as an empty book.
  Lorebook? get _activeGroupLorebook {
    final raw = _session.activeGroup?.groupLorebook ?? '';
    if (_cachedGroupBookJson != raw) {
      _cachedGroupBookJson = raw;
      _groupLorebookUnreadable = false;
      try {
        _cachedGroupBook = parseGroupLorebookJson(raw);
      } catch (e) {
        _cachedGroupBook = null;
        _groupLorebookUnreadable = true;
        debugPrint(
          '[Lorebook] group "${_session.activeGroup?.name}" lorebook could '
          'not be read; its entries are left out: $e',
        );
      }
    }
    return _cachedGroupBook;
  }

  /// True when the active group's stored lorebook could not be read, so none
  /// of its entries are in play.
  bool get groupLorebookUnreadable =>
      _activeGroupLorebook == null && _groupLorebookUnreadable;

  /// The live group-lorebook entries (the instances the scanner marks), for
  /// the phone's lore list.
  List<LorebookEntry> get groupLorebookEntries =>
      _activeGroupLorebook?.entries ?? const [];

  /// The one entry enumerator the scanner and the injector share.
  List<LoreEntryRef> collectLoreRefs({bool? inheritOverride}) {
    final group = _session.activeGroup;
    final worlds = _g.deps.services.worlds;
    final slots = _g.places.slots;
    final inherit =
        inheritOverride ?? (group?.inheritCharacterLorebooks ?? true);
    final scanning = inheritOverride == true;
    var characters = group != null
        ? _session.groupCharacters
        : (_session.activeCharacter != null
              ? [_session.activeCharacter!]
              : const <CharacterCard>[]);
    CharacterCard? speaker;
    if (!scanning && group != null) {
      speaker = _g.groups.workSpeakerCard();
      // No resolved speaker → no character books. Null speaker would
      // inherit every member and walk a present-scene row onto the porch.
      if (speaker == null) characters = const [];
    }
    return collectLoreEntryRefs(
      characters: characters,
      chatLorebook: timedEffects.chatLorebook,
      groupLorebook: _activeGroupLorebook,
      chatWorldIds: slots.allIds,
      // Place-rank context for inclusion-group nearest-wins (slice 2).
      settingChain: slots.primaryId == null
          ? const []
          : worlds.chainFor(slots.primaryId!),
      // Decided empty must stay empty — never ghost to group.worldIds.
      groupWorldNames: const [],
      resolveWorld: worlds.resolveWorld,
      inherit: inherit,
      speaker: speaker,
    );
  }
}
