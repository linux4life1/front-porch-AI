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

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/chat/lorebook_matcher.dart';

/// Per-chat lore session state: ST timed effects (sticky / cooldown, in
/// MESSAGE counts), {{setvar}} macro locals, and the chat-scoped lorebook.
/// Everything here shares one lifecycle — persisted in the session blob,
/// hydrated on load, cleared at session boundaries — which is why it is
/// co-located.
/// Persisted as the additive `lorebookTimers` key inside the session's
/// groupRealismState JSON blob (no schema change; dies with the session).
///
/// Entries are identified by [loreEntryHash] (FNV-1a over name+keys+content),
/// so editing an entry intentionally drops its timed state — ST behavior.
/// `delay` needs no stored state: it is a pure `chatLength < delay` check
/// made by the scanner.
///
/// ST interaction rules implemented across this store + the scanner gates:
/// sticky-active entries force-refresh without key matches, skip probability
/// rolls, bypass cooldown, and win inclusion groups; when a sticky expires
/// and the entry carries a cooldown, the cooldown starts `protected` (it
/// survives without further key matches). Deleting messages back past an
/// effect's start removes it unless protected.
class LorebookTimedEffects {
  final Map<int, ({int start, int end})> _sticky = {};
  final Map<int, ({int start, int end, bool protected})> _cooldown = {};

  /// Per-chat {{setvar}}/{{getvar}} macro variables. Serialized under the
  /// top-level `macroVars` key.
  final Map<String, String> localMacroVars = {};

  /// The chat-scoped lorebook — lore that lives and dies with this one
  /// conversation. Live instance (the scanner writes trigger state onto its
  /// entries); serialized under the top-level `chatLorebook` key.
  final Lorebook chatLorebook = Lorebook(entries: []);

  bool isStickyActive(LorebookEntry entry, int chatLength) {
    final s = _sticky[loreEntryHash(entry)];
    return s != null && chatLength >= s.start && chatLength < s.end;
  }

  bool isOnCooldown(LorebookEntry entry, int chatLength) {
    final c = _cooldown[loreEntryHash(entry)];
    return c != null && chatLength >= c.start && chatLength < c.end;
  }

  /// Messages of sticky remaining (0 when not sticky-active) — sidebar pill.
  int stickyRemaining(LorebookEntry entry, int chatLength) {
    final s = _sticky[loreEntryHash(entry)];
    if (s == null || chatLength < s.start || chatLength >= s.end) return 0;
    return s.end - chatLength;
  }

  /// Messages of cooldown remaining (0 when not cooling) — sidebar pill.
  int cooldownRemaining(LorebookEntry entry, int chatLength) {
    final c = _cooldown[loreEntryHash(entry)];
    if (c == null || chatLength < c.start || chatLength >= c.end) return 0;
    return c.end - chatLength;
  }

  /// Record effects for a NEWLY activated entry. Re-matches never refresh a
  /// running sticky timer (ST rule — the `putIfAbsent`-style guard).
  void recordActivation(LorebookEntry entry, int chatLength) {
    final h = loreEntryHash(entry);
    if (entry.sticky > 0 && !_sticky.containsKey(h)) {
      _sticky[h] = (start: chatLength, end: chatLength + entry.sticky);
    }
    if (entry.cooldown > 0 && entry.sticky <= 0 && !_cooldown.containsKey(h)) {
      _cooldown[h] = (
        start: chatLength,
        end: chatLength + entry.cooldown,
        protected: false,
      );
    }
  }

  /// Expiry bookkeeping, run once at the top of every scan:
  /// - a sticky that ended starts the entry's cooldown as `protected`;
  /// - expired cooldowns are removed;
  /// - effects whose start lies beyond the current chat length (messages
  ///   were deleted/swiped back) are dropped unless protected.
  /// [entries] resolves hashes back to live entries for the cooldown value.
  void tick(int chatLength, Iterable<LorebookEntry> entries) {
    final byHash = <int, LorebookEntry>{
      for (final e in entries) loreEntryHash(e): e,
    };

    final endedSticky = <int>[];
    _sticky.forEach((h, s) {
      if (chatLength >= s.end || chatLength < s.start) endedSticky.add(h);
    });
    for (final h in endedSticky) {
      final s = _sticky.remove(h)!;
      final entry = byHash[h];
      final rewound = chatLength < s.start;
      if (!rewound && entry != null && entry.cooldown > 0) {
        _cooldown[h] = (
          start: chatLength,
          end: chatLength + entry.cooldown,
          protected: true,
        );
      }
    }

    _cooldown.removeWhere(
      (h, c) => chatLength >= c.end || (chatLength < c.start && !c.protected),
    );
  }

  /// The `chatLorebook` JSON fragment, or null when empty.
  Map<String, dynamic>? chatLorebookFragment() =>
      chatLorebook.entries.isEmpty ? null : chatLorebook.toJson();

  /// The `macroVars` JSON fragment, or null when empty.
  Map<String, dynamic>? macroVarsFragment() =>
      localMacroVars.isEmpty ? null : Map<String, dynamic>.from(localMacroVars);

  /// The `lorebookTimers` JSON fragment, or null when there is nothing to
  /// persist (keeps plain sessions at the literal '{}' old versions expect).
  Map<String, dynamic>? toJsonFragment() {
    if (_sticky.isEmpty && _cooldown.isEmpty) return null;
    return {
      'sticky': _sticky.map(
        (h, s) => MapEntry('$h', {'start': s.start, 'end': s.end}),
      ),
      'cooldown': _cooldown.map(
        (h, c) => MapEntry('$h', {
          'start': c.start,
          'end': c.end,
          'protected': c.protected,
        }),
      ),
    };
  }

  /// Restore from a session's groupRealismState JSON string (tolerant of
  /// null/empty/'{}'/legacy shapes/malformed JSON — all reset to empty).
  void hydrate(String? groupRealismStateJson) {
    reset();
    final raw = groupRealismStateJson;
    if (raw == null || raw.isEmpty || raw == '{}') return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      if (decoded['macroVars'] is Map) {
        (decoded['macroVars'] as Map).forEach((k, v) {
          localMacroVars[k.toString()] = v.toString();
        });
      }
      if (decoded['chatLorebook'] is Map) {
        chatLorebook.entries.addAll(
          Lorebook.fromJson(
            Map<String, dynamic>.from(decoded['chatLorebook'] as Map),
          ).entries,
        );
      }
      if (decoded['lorebookTimers'] is! Map) return;
      final timers = Map<String, dynamic>.from(decoded['lorebookTimers'] as Map);
      final sticky = timers['sticky'];
      if (sticky is Map) {
        sticky.forEach((k, v) {
          final h = int.tryParse(k.toString());
          if (h == null || v is! Map) return;
          final start = (v['start'] as num?)?.toInt();
          final end = (v['end'] as num?)?.toInt();
          if (start != null && end != null) {
            _sticky[h] = (start: start, end: end);
          }
        });
      }
      final cooldown = timers['cooldown'];
      if (cooldown is Map) {
        cooldown.forEach((k, v) {
          final h = int.tryParse(k.toString());
          if (h == null || v is! Map) return;
          final start = (v['start'] as num?)?.toInt();
          final end = (v['end'] as num?)?.toInt();
          if (start != null && end != null) {
            _cooldown[h] = (
              start: start,
              end: end,
              protected: v['protected'] == true,
            );
          }
        });
      }
    } catch (_) {
      reset();
    }
  }

  void reset() {
    _sticky.clear();
    _cooldown.clear();
    localMacroVars.clear();
    chatLorebook.entries.clear();
  }
}
