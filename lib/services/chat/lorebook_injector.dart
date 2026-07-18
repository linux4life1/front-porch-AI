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

import 'dart:math';

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/chat/lorebook_collection.dart';
import 'package:front_porch_ai/services/chat/lorebook_matcher.dart';
import 'package:front_porch_ai/services/storage/settings/lorebook_settings.dart';

/// An entry destined for @depth insertion into the chat history line list.
/// [role] is stored for chat-completions futures but has no wire form in the
/// current text transcript (same degrade as ST text-completion mode).
class LoreDepthEntry {
  final int depth;
  final int? role;
  final String content;
  const LoreDepthEntry({
    required this.depth,
    required this.content,
    this.role,
  });
}

/// Positioned lore buckets, ready for the prompt assemblers. Every string is
/// either empty or newline-terminated so call sites can concatenate blindly.
class LoreInjectionResult {
  final String beforeChar;
  final String afterChar;
  final String authorNoteTop;
  final String authorNoteBottom;
  final String examplesTop;
  final String examplesBottom;
  final List<LoreDepthEntry> depthEntries;

  /// Display names of entries dropped by the token budget.
  final List<String> overflowDropped;

  /// The effective lore budget (min of percent-of-context and the cap) this
  /// result was built under — the sidebar meter's denominator.
  final int budgetTokens;

  const LoreInjectionResult({
    this.beforeChar = '',
    this.afterChar = '',
    this.authorNoteTop = '',
    this.authorNoteBottom = '',
    this.examplesTop = '',
    this.examplesBottom = '',
    this.depthEntries = const [],
    this.overflowDropped = const [],
    this.budgetTokens = 0,
  });

  /// Sync chars/4 estimate over every bucket (matches _lastPromptBudget's
  /// accounting; the real tokenizer still governs history budgeting because
  /// these strings land inside the fixed content that gets counted there).
  int get approxTokens {
    var chars = beforeChar.length +
        afterChar.length +
        authorNoteTop.length +
        authorNoteBottom.length +
        examplesTop.length +
        examplesBottom.length;
    for (final d in depthEntries) {
      chars += d.content.length;
    }
    return (chars / 4).ceil();
  }

  bool get isEmpty =>
      beforeChar.isEmpty &&
      afterChar.isEmpty &&
      authorNoteTop.isEmpty &&
      authorNoteBottom.isEmpty &&
      examplesTop.isEmpty &&
      examplesBottom.isEmpty &&
      depthEntries.isEmpty;
}

/// Pure-read lore injection engine: activation set → inclusion-group winner
/// filtering → budget fill → position bucketing with per-bucket ordering.
/// Never mutates entry state, so impersonation and the context viewer can
/// call it freely. The scanner owns all trigger-state mutation.
class LorebookInjector {
  final List<LoreEntryRef> Function() getEntryRefs;
  final LorebookSettings Function() getSettings;

  /// Whether an entry is ST-sticky-active (timed effects). Sticky entries
  /// inject without key matches, win their inclusion groups, and fill the
  /// budget first. Wired by the timed-effects store; defaults to never.
  final bool Function(LorebookEntry entry) isStickyActive;

  LorebookInjector({
    required this.getEntryRefs,
    required this.getSettings,
    this.isStickyActive = _never,
  });

  static bool _never(LorebookEntry e) => false;

  /// Active refs (identity-deduped, first source wins for book overrides).
  List<LoreEntryRef> _activeRefs() {
    final seen = <LorebookEntry>{};
    return [
      for (final ref in getEntryRefs())
        if ((ref.entry.enabled &&
                (ref.entry.isTriggered ||
                    ref.entry.constant ||
                    isStickyActive(ref.entry))) &&
            seen.add(ref.entry))
          ref,
    ];
  }

  /// The post-group-filter active entries — the single source of truth for
  /// the sidebar, web facade, and injection alike.
  List<LorebookEntry> activeEntries({required String sessionSeed}) {
    return [
      for (final ref in _groupFiltered(_activeRefs(), sessionSeed)) ref.entry,
    ];
  }

  /// Inclusion groups: of the active members of each group, exactly one
  /// injects. Sticky-active members win outright; then "prioritize"
  /// (groupOverride) members by highest order; then group scoring (most
  /// matched keys this scan); else weighted random — seeded by session +
  /// the active membership set, so the winner is STABLE across turns and
  /// re-rolls only when membership actually changes. An entry in several
  /// groups (comma-separated) must survive every one of them.
  List<LoreEntryRef> _groupFiltered(
    List<LoreEntryRef> active,
    String sessionSeed,
  ) {
    final groups = <String, List<LoreEntryRef>>{};
    for (final ref in active) {
      if (ref.entry.group.isEmpty) continue;
      for (final g in ref.entry.group.split(',')) {
        final name = g.trim();
        if (name.isEmpty) continue;
        groups.putIfAbsent(name, () => []).add(ref);
      }
    }
    if (groups.isEmpty) return active;

    final excluded = <LorebookEntry>{};
    groups.forEach((name, members) {
      if (members.length < 2) return;
      final winner = _pickGroupWinner(name, members, sessionSeed);
      for (final m in members) {
        if (!identical(m.entry, winner.entry)) excluded.add(m.entry);
      }
    });

    return [
      for (final ref in active)
        if (!excluded.contains(ref.entry)) ref,
    ];
  }

  LoreEntryRef _pickGroupWinner(
    String groupName,
    List<LoreEntryRef> members,
    String sessionSeed,
  ) {
    LoreEntryRef highestOrder(Iterable<LoreEntryRef> refs) =>
        refs.reduce((a, b) => b.entry.order > a.entry.order ? b : a);

    final sticky = members.where((m) => isStickyActive(m.entry));
    if (sticky.isNotEmpty) return highestOrder(sticky);

    final override = members.where((m) => m.entry.groupOverride);
    if (override.isNotEmpty) return highestOrder(override);

    final scoring = members.where((m) => m.entry.useGroupScoring ?? false);
    if (scoring.isNotEmpty) {
      var best = members.first;
      for (final m in members.skip(1)) {
        if (m.entry.lastMatchScore > best.entry.lastMatchScore) best = m;
      }
      return best;
    }

    // Weighted random, deterministic while the active membership holds.
    final membershipKey = (members.map((m) => loreEntryHash(m.entry)).toList()
          ..sort())
        .join(',');
    final rng = Random(fnv1a32('$sessionSeed|$groupName|$membershipKey'));
    final totalWeight = members.fold<int>(
      0,
      (sum, m) => sum + (m.entry.groupWeight > 0 ? m.entry.groupWeight : 1),
    );
    var roll = rng.nextInt(totalWeight);
    for (final m in members) {
      roll -= m.entry.groupWeight > 0 ? m.entry.groupWeight : 1;
      if (roll < 0) return m;
    }
    return members.last;
  }

  /// Assemble positioned buckets under the token budget.
  LoreInjectionResult buildInjection({
    required String sessionSeed,
    required int contextSize,
  }) {
    final settings = getSettings();
    final pctBudgetEarly = (contextSize * settings.budgetPercent / 100).round();
    final effectiveBudget = settings.budgetCap > 0
        ? min(pctBudgetEarly, settings.budgetCap)
        : pctBudgetEarly;
    final filtered = _groupFiltered(_activeRefs(), sessionSeed);
    if (filtered.isEmpty) {
      return LoreInjectionResult(budgetTokens: effectiveBudget);
    }

    // Fill order: sticky-active first, then by descending order — that is
    // the survival priority when the budget runs out.
    final fillOrder = List<LoreEntryRef>.of(filtered)
      ..sort((a, b) {
        final sa = isStickyActive(a.entry) ? 1 : 0;
        final sb = isStickyActive(b.entry) ? 1 : 0;
        if (sa != sb) return sb - sa;
        return b.entry.order.compareTo(a.entry.order);
      });

    final budget = effectiveBudget;

    final included = <LoreEntryRef>[];
    final overflow = <String>[];
    final seenContent = <String>{};
    final perBookUsed = <Lorebook, int>{};
    var used = 0;
    for (final ref in fillOrder) {
      final content = ref.entry.injectableContent;
      if (content.isEmpty) continue;
      if (!seenContent.add(content)) continue; // legacy content dedup
      final tokens = (content.length / 4).ceil();
      if (!ref.entry.ignoreBudget) {
        final bookCap = ref.book.tokenBudget;
        final bookUsed = perBookUsed[ref.book] ?? 0;
        if (used + tokens > budget ||
            (bookCap != null && bookUsed + tokens > bookCap)) {
          overflow.add(ref.entry.displayName);
          continue;
        }
        used += tokens;
        perBookUsed[ref.book] = bookUsed + tokens;
      }
      included.add(ref);
    }

    // Emit each position bucket in ASCENDING order: ST semantics put higher
    // order closer to the end of its block (nearer the generation point).
    final byPosition = <int, List<LoreEntryRef>>{};
    for (final ref in included) {
      // Outlet (7) has no outlet macro support — falls back to before-char.
      final pos = ref.entry.position == 7 ? 0 : ref.entry.position;
      byPosition.putIfAbsent(pos, () => []).add(ref);
    }
    List<String> bucket(int pos) {
      final refs = byPosition[pos];
      if (refs == null) return const [];
      final stable = List<LoreEntryRef>.of(refs);
      // Stable sort ascending by order (List.sort isn't stable — decorate
      // with the fill index so ties keep their budget-priority sequence).
      final indexed = stable.asMap().entries.toList()
        ..sort((a, b) {
          final byOrder = a.value.entry.order.compareTo(b.value.entry.order);
          return byOrder != 0 ? byOrder : a.key.compareTo(b.key);
        });
      return [for (final e in indexed) e.value.entry.injectableContent];
    }

    String joined(int pos, {String frame = ''}) {
      final parts = bucket(pos);
      if (parts.isEmpty) return '';
      final body = parts.join('\n');
      return frame.isEmpty ? '$body\n' : '$frame\n$body\n';
    }

    return LoreInjectionResult(
      beforeChar: joined(0, frame: 'Context Info:'),
      afterChar: joined(1),
      authorNoteTop: joined(2),
      authorNoteBottom: joined(3),
      examplesTop: joined(5),
      examplesBottom: joined(6),
      depthEntries: [
        for (final ref in (byPosition[4] ?? const <LoreEntryRef>[]))
          LoreDepthEntry(
            depth: ref.entry.depth < 0 ? 0 : ref.entry.depth,
            role: ref.entry.role,
            content: ref.entry.injectableContent,
          ),
      ],
      overflowDropped: overflow,
      budgetTokens: effectiveBudget,
    );
  }
}
