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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/chat/lorebook_collection.dart';
import 'package:front_porch_ai/services/chat/lorebook_matcher.dart';
import 'package:front_porch_ai/services/chat/lorebook_timed_effects.dart';

/// Plain (non-ChangeNotifier) domain service owning lorebook keyword scanning,
/// trigger/depth state mutation on the live LorebookEntry objects, depth
/// decrement (post-AI only for pre-AI triggered entries to preserve sticky for
/// AI-discovered lore), and reset of non-constant trigger state.
///
/// Matching semantics live in lorebook_matcher.dart (ST-parity: regex keys,
/// per-entry case/whole-word overrides, `*` wildcards). Per-entry activation
/// gates handled here: secondary-key selective logic, probability rolls
/// (skipped while an entry is already active, so sticky entries never
/// re-roll), and the enabled flag. Positions/order/budget/recursion/timed
/// effects are stored on the model but engine support is a later phase.
///
/// The scanner mutates entries in-place; it owns no separate trigger map.
/// The entry universe (group book + group worlds + member/1:1 books +
/// attached worlds) comes from the shared [collectLoreEntryRefs] enumerator
/// via the [getEntryRefs] callback, which keeps the service testable in
/// isolation and preserves exact 1:1/group parity: scan/reset always process
/// whatever the callback yields. The callback MUST yield live instances
/// (ChatService's cached group book, live World objects) — trigger state on
/// a fresh parse is invisible to injection.
///
/// The "keep reset blocks in sync" call sites in ChatService (startNewChat,
/// setActive*, _loadLastSession, setActiveGroup, ext-seed, delete, fork,
/// regen/swipe) all route through [resetLorebookTriggerState].
class LorebookScanner {
  final VoidCallback onNotify;
  final List<LoreEntryRef> Function() getEntryRefs;

  /// Most recent chat messages, oldest-first, already formatted (with or
  /// without "Name: " prefixes per the include-names setting). Used by
  /// [scanLatest] to build per-entry scan windows.
  final List<String> Function(int count) getRecentMessages;

  /// Global scan depth (messages). Per-entry `scanDepth` and book-level
  /// `Lorebook.scanDepth` override it.
  final int Function() getGlobalScanDepth;

  /// Global recursive-scan switch. Book-level `recursiveScanning` can force
  /// recursion for entries of that book even when the global is off.
  final bool Function() getRecursiveScan;

  /// Max recursion sweeps; 0 = unlimited (internal safety cap still applies).
  final int Function() getMaxRecursionSteps;

  /// Per-chat ST timed effects (sticky/cooldown). Null in tests that don't
  /// exercise them; delay needs no store and is always honored.
  final LorebookTimedEffects? timedEffects;

  /// Current chat length in messages — the clock timed effects run on.
  final int Function() getChatLength;

  /// Macro substitution for trigger KEYS before matching (ST substitutes
  /// params in keys — e.g. a key of `{{user}}`). Null = keys match as-is.
  final String Function(String key)? resolveKeyMacros;

  /// Runaway guard when max steps is "unlimited".
  static const int _kRecursionHardCap = 10;

  final Random _rng;

  LorebookScanner({
    required this.onNotify,
    required this.getEntryRefs,
    this.getRecentMessages = _noMessages,
    this.getGlobalScanDepth = _defaultScanDepth,
    this.getRecursiveScan = _falseFn,
    this.getMaxRecursionSteps = _zeroFn,
    this.timedEffects,
    this.getChatLength = _zeroFn,
    this.resolveKeyMacros,
    Random? rng,
  }) : _rng = rng ?? Random();

  static List<String> _noMessages(int count) => const [];
  static int _defaultScanDepth() => 1;
  static bool _falseFn() => false;
  static int _zeroFn() => 0;

  /// Distinct live entry refs in the current context. A world attached both
  /// at group level and by a member yields the same live objects twice —
  /// identity-dedup so a probability gate can never roll twice per scan.
  /// The first ref wins, keeping its source book for book-level overrides.
  List<LoreEntryRef> _distinctRefs() {
    final seen = <LorebookEntry>{};
    return [
      for (final ref in getEntryRefs())
        if (seen.add(ref.entry)) ref,
    ];
  }

  /// Production scan entry point: evaluates every entry against its own
  /// window of recent messages (entry.scanDepth ?? book.scanDepth ?? global),
  /// then runs recursion sweeps so activated lore can trigger other lore.
  /// An entry depth of 0 means "never scans chat" (ST semantics — such
  /// entries activate only via constant or recursion).
  void scanLatest() {
    // Windows memoized per distinct depth — in practice depths cluster at
    // one or two values, so this stays a couple of joins per scan.
    final buffers = <int, String>{};
    String bufferFor(int depth) => buffers.putIfAbsent(
          depth,
          () => getRecentMessages(depth).join('\n'),
        );

    final refs = _distinctRefs();
    final chatLength = getChatLength();
    // Timed-effect bookkeeping first: expire stickies (starting their
    // protected cooldowns), drop finished/rewound effects.
    timedEffects?.tick(chatLength, [for (final r in refs) r.entry]);

    // Probability failures are remembered for this whole scan (incl. the
    // recursion sweeps below) — ST's per-scan failed-roll memory.
    final failedRolls = <LorebookEntry>{};

    bool changed = false;
    for (final ref in refs) {
      final entry = ref.entry;

      // Sticky-active: force-refresh with no key match and no roll.
      if (entry.enabled &&
          timedEffects != null &&
          timedEffects!.isStickyActive(entry, chatLength)) {
        if (!entry.isTriggered) {
          entry.isTriggered = true;
          changed = true;
        }
        if (entry.remainingDepth < entry.stickyDepth) {
          entry.remainingDepth = entry.stickyDepth;
        }
        continue;
      }

      final depth = entry.scanDepth ?? ref.book.scanDepth ?? getGlobalScanDepth();
      if (depth <= 0) continue;
      if (_scanEntryAgainst(entry, bufferFor(depth.clamp(1, 100)),
          failedRolls: failedRolls, chatLength: chatLength)) {
        changed = true;
      }
    }

    if (_runRecursionSweeps(refs, failedRolls)) changed = true;

    if (changed) {
      onNotify();
    }
  }

  /// Recursion: content of active entries (minus preventRecursion) forms a
  /// buffer that can activate further entries. `excludeRecursion` entries
  /// never activate here; `delayUntilRecursion` level-N entries only become
  /// eligible once lower levels stop producing activations (ST semantics).
  /// Returns whether anything activated.
  bool _runRecursionSweeps(
    List<LoreEntryRef> refs,
    Set<LorebookEntry> failedRolls,
  ) {
    final globalOn = getRecursiveScan();
    bool eligibleBook(LoreEntryRef ref) =>
        globalOn || (ref.book.recursiveScanning ?? false);
    if (!refs.any(eligibleBook)) return false;

    final maxSteps = getMaxRecursionSteps();
    final cap = maxSteps <= 0
        ? _kRecursionHardCap
        : (maxSteps > _kRecursionHardCap ? _kRecursionHardCap : maxSteps);

    final delayedLevels = refs
        .map((r) => r.entry.delayUntilRecursion)
        .where((l) => l > 0)
        .toSet()
        .toList()
      ..sort();

    bool anyActivated = false;
    var level = 1;
    for (var step = 0; step < cap; step++) {
      final buffer = [
        for (final ref in refs)
          if (ref.entry.enabled &&
              (ref.entry.isTriggered || ref.entry.constant) &&
              !ref.entry.preventRecursion)
            ref.entry.injectableContent,
      ].join('\n');
      if (buffer.isEmpty) break;

      bool sweepActivated = false;
      final chatLength = getChatLength();
      for (final ref in refs) {
        final e = ref.entry;
        if (!eligibleBook(ref)) continue;
        if (e.isTriggered || e.constant) continue;
        if (e.excludeRecursion) continue;
        if (e.delayUntilRecursion > level) continue;
        if (_scanEntryAgainst(e, buffer,
            failedRolls: failedRolls,
            recursionLevel: level,
            chatLength: chatLength)) {
          sweepActivated = true;
        }
      }

      if (sweepActivated) {
        anyActivated = true;
        continue;
      }
      // Dry sweep: unlock the next delayed level, or stop.
      final next =
          delayedLevels.where((l) => l > level).fold<int>(0, (a, l) => a == 0 ? l : a);
      if (next == 0) break;
      level = next;
    }
    return anyActivated;
  }

  /// Mutation-free dry-run: which enabled entries WOULD trigger on [draft]?
  /// Key + secondary-logic gates only — no probability rolls, no trigger
  /// writes, no timed-effect ticks. Powers the sidebar's live preview.
  Set<LorebookEntry> previewTriggers(String draft) {
    final hits = <LorebookEntry>{};
    if (draft.trim().isEmpty) return hits;
    for (final ref in _distinctRefs()) {
      final entry = ref.entry;
      if (!entry.enabled || entry.constant || entry.isTriggered) continue;
      if (entry.delayUntilRecursion > 0) continue;
      bool matches(String rawKey) {
        final key = (resolveKeyMacros != null && rawKey.contains('{{'))
            ? resolveKeyMacros!(rawKey)
            : rawKey;
        return keyMatchesText(
          key,
          draft,
          caseSensitive: entry.caseSensitive ?? false,
          matchWholeWords: entry.matchWholeWords,
          forceRegex: entry.useRegex,
        );
      }

      if (entry.keys.any(matches) && secondaryLogicSatisfied(entry, matches)) {
        hits.add(entry);
      }
    }
    return hits;
  }

  /// Scan one explicit buffer against every entry, ignoring scan windows and
  /// recursion. Kept for tests and for callers that already hold the exact
  /// text.
  void scanLorebook(String text) {
    bool changed = false;
    final failedRolls = <LorebookEntry>{};
    for (final ref in _distinctRefs()) {
      if (_scanEntryAgainst(ref.entry, text, failedRolls: failedRolls)) {
        changed = true;
      }
    }
    if (changed) {
      onNotify();
    }
  }

  /// Evaluate one entry against [text] through the gate chain (enabled →
  /// delay → cooldown → delay-until-recursion → keys → secondary logic →
  /// probability with per-scan failure memory). On success:
  /// isTriggered=true, remainingDepth=stickyDepth, timed effects recorded.
  /// Returns whether the entry NEWLY triggered.
  bool _scanEntryAgainst(
    LorebookEntry entry,
    String text, {
    required Set<LorebookEntry> failedRolls,
    int recursionLevel = 0,
    int chatLength = 0,
  }) {
    if (!entry.enabled) return false;
    // ST delay: suppressed until the chat is at least N messages long.
    if (entry.delay > 0 && chatLength < entry.delay) return false;
    // ST cooldown: cannot re-activate while cooling down (sticky-active
    // entries never reach here — they refresh before the gate chain).
    if (timedEffects != null &&
        timedEffects!.isOnCooldown(entry, chatLength)) {
      return false;
    }
    // Delayed-until-recursion entries never activate in a normal scan.
    if (entry.delayUntilRecursion > 0 && recursionLevel == 0) return false;

    bool matches(String rawKey) {
      final key = (resolveKeyMacros != null && rawKey.contains('{{'))
          ? resolveKeyMacros!(rawKey)
          : rawKey;
      return keyMatchesText(
        key,
        text,
        caseSensitive: entry.caseSensitive ?? false,
        matchWholeWords: entry.matchWholeWords,
        forceRegex: entry.useRegex,
      );
    }

    if (!entry.keys.any(matches)) return false;
    if (!secondaryLogicSatisfied(entry, matches)) return false;

    // Probability gate: rolled only when the entry is not already active —
    // an active (sticky) entry refreshes without re-rolling — and at most
    // once per scan (recursion sweeps never re-roll a failed entry).
    if (!entry.isTriggered &&
        entry.useProbability &&
        entry.probability < 100) {
      if (failedRolls.contains(entry)) return false;
      if (_rng.nextInt(100) >= entry.probability) {
        failedRolls.add(entry);
        return false;
      }
    }

    final newlyTriggered = !entry.isTriggered;
    entry.isTriggered = true;
    entry.remainingDepth = entry.stickyDepth;
    entry.lastMatchScore = entry.keys.where(matches).length +
        entry.secondaryKeys.where(matches).length;
    if (newlyTriggered) {
      timedEffects?.recordActivation(entry, chatLength);
    }
    return newlyTriggered;
  }

  /// Public exposure of the single-key matcher for tests and direct callers.
  bool matchKeyword(String key, String text) =>
      keyMatchesText(key.toLowerCase(), text.toLowerCase());

  /// Decrement remainingDepth only for the provided set of entries.
  /// Used after AI response finalization so that lore entries *discovered in
  /// the AI's own response* keep their full stickyDepth for the next user
  /// turn. Only non-constant entries are decremented; when remaining <= 0,
  /// isTriggered=false. If any un-trigger happens, calls onNotify.
  void decrementLoreDepthForEntries(Set<LorebookEntry> entriesToDecrement) {
    if (entriesToDecrement.isEmpty) return;
    bool changed = false;

    for (final entry in entriesToDecrement) {
      if (entry.isTriggered && !entry.constant) {
        entry.remainingDepth--;
        if (entry.remainingDepth <= 0) {
          entry.isTriggered = false;
          changed = true;
        }
      }
    }

    if (changed) {
      onNotify();
    }
  }

  /// Reset lorebook trigger state (isTriggered=false + remainingDepth=0) for
  /// all non-constant entries in the current context (group book + worlds +
  /// character books). Constant entries are skipped (always active if
  /// enabled). No notify — callers drive subsequent UI updates.
  /// Every caller of this reset is a session boundary (startNewChat,
  /// setActive*, 0-session loads) — never regen/swipe — so per-chat timed
  /// effects clear here too; loading a real session re-hydrates its own.
  void resetLorebookTriggerState() {
    timedEffects?.reset();
    for (final ref in _distinctRefs()) {
      if (!ref.entry.constant) {
        ref.entry.isTriggered = false;
        ref.entry.remainingDepth = 0;
      }
    }
  }
}
