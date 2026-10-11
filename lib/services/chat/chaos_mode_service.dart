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

import 'chaos/chaos.dart';

/// Plain (non-ChangeNotifier) domain service owning the Chaos Mode / Chance Time
/// state and logic (pressure gauge growth + auto-trigger roll, wheel sampling,
/// apply + injection + metadata side effect, clear timing via delivered flag).
///
/// ChatService owns the instance via a private late final and delegates. Cross
/// state that lives in the parent (pendingRealismMetadata for the delta chip,
/// the 18+ themes switch, the Porch Life frequency) is reached only through
/// callbacks supplied at construction, which keeps the service testable.
///
/// UI-coordination state that crosses widget boundaries (_chanceTimeCompleter for
/// pausing sendMessage during wheel, _chanceTimePendingTrigger for overlay pop,
/// the web pre-picked event) remains in ChatService. The service owns the pure
/// sim core (enabled, nsfw, pressure, cooldown, pendingInjection for prompt,
/// delivered flag, recently used events).
///
/// Pressure is chat-scoped, not per speaker, so group and 1:1 behave the same;
/// `{{char}}` and the other placeholders resolve at apply time in ChatService.
///
/// The event pools live in `chaos/`. Adult events need BOTH the chat's spicy
/// switch and [isAdultAllowed] (the app-wide 18+ themes switch, read live), so
/// turning 18+ themes off takes effect on the very next wheel.
class ChaosModeService {
  final VoidCallback onNotify;
  final Future<void> Function() onSaveChat;
  final void Function(String key, String value) onSetPendingRealismMetadata;

  /// The app-wide 18+ themes switch. Absent means adult events never appear.
  final bool Function()? isAdultAllowed;

  /// The Porch Life Chaos frequency. Absent means [ChaosFrequency.normal].
  final ChaosFrequency Function()? getFrequency;

  bool _chaosModeEnabled = false;
  bool _chaosNsfwEnabled = false; // the chat's spicy switch
  int _chaosPressure = 0; // 0–100; grows each turn without a trigger
  int _cooldownTurns = 0; // user turns left with no growth and no roll
  String?
  _pendingChaosInjection; // event text to inject into the next response prompt
  bool _chaosEventDelivered =
      false; // true after the event has been used in at least one generation
  final List<String> _recentEvents = []; // raw texts, newest last
  final Random _random = Random();

  ChaosModeService({
    required this.onNotify,
    required this.onSaveChat,
    required this.onSetPendingRealismMetadata,
    this.isAdultAllowed,
    this.getFrequency,
  });

  // ── Public surface (for shims in ChatService + direct test/UI callers) ──────

  bool get chaosModeEnabled => _chaosModeEnabled;
  bool get chaosNsfwEnabled => _chaosNsfwEnabled;
  int get chaosPressure => _chaosPressure;
  int get cooldownTurns => _cooldownTurns;

  /// Whether the 18+ themes switch is on. The spicy toggle is hidden when not.
  bool get adultAllowed => isAdultAllowed?.call() ?? false;

  /// Whether adult events can reach the wheel right now.
  bool get spicyActive => _chaosNsfwEnabled && adultAllowed;

  ChaosFrequency get frequency => getFrequency?.call() ?? ChaosFrequency.normal;

  /// True if there is a Chance Time event prepared for the *next* response
  /// generation that has not yet been delivered.
  ///
  /// Once the injection has been consumed (markEventDelivered called from the
  /// prompt builder), this returns false, so the sidebar's "EVENT PENDING"
  /// state clears as soon as the character has received the event. The raw
  /// value + delivered flag are kept so regens/swipes of the reacting AI
  /// message re-inject the same event; the value is only cleared on the *next*
  /// user turn via clearDeliveredPendingIfAny.
  bool get hasPendingChaosEvent =>
      _pendingChaosInjection != null && !_chaosEventDelivered;

  String? get pendingChaosInjection => _pendingChaosInjection;
  bool get chaosEventDelivered => _chaosEventDelivered;

  // The Normal frequency's numbers, kept as the canonical consts.
  static const int baseChance = 5;
  static const int growthPerTurn = 5;
  static const int pressureCap = 100;

  /// How many recently used events a wheel tries to avoid.
  static const int recentMemory = 24;

  /// Every SFW event text (all of `chaos/` minus the adult pool).
  static final List<String> chanceTimeEventPool = [
    for (final e in kAllChaosEvents)
      if (!e.adult) e.text,
  ];

  /// Every adult event text. Only used when [spicyActive].
  static final List<String> chanceTimeNsfwPool = [
    for (final e in kAllChaosEvents)
      if (e.adult) e.text,
  ];

  /// The category of a raw wheel string; unknown text reads as a Wild Card.
  static ChaosCategory categoryOf(String rawEvent) =>
      chaosEventFor(rawEvent)?.category ?? ChaosCategory.wildCard;

  // ── Control / mutation (side-effect free; wrapper in ChatService does save/notify) ──

  void setModeEnabled(bool enabled) {
    _chaosModeEnabled = enabled;
    if (!enabled) {
      _chaosPressure = 0;
      _cooldownTurns = 0;
    }
  }

  void setNsfwEnabled(bool enabled) {
    _chaosNsfwEnabled = enabled;
  }

  // Direct scalar sets for load/reset sites (kept in sync across multiple call sites in parent).
  void setPressure(int value) {
    _chaosPressure = value;
  }

  void setPendingChaosInjection(String? value) {
    _pendingChaosInjection = value;
  }

  void setEventDelivered(bool value) {
    _chaosEventDelivered = value;
  }

  // ── Reset helpers (support "keep reset blocks in sync" comments in parent) ──

  void resetForFreshChat() {
    _chaosModeEnabled = false;
    _chaosNsfwEnabled = false;
    _chaosPressure = 0;
    _cooldownTurns = 0;
    _pendingChaosInjection = null;
    _chaosEventDelivered = false;
    _recentEvents.clear();
  }

  void seedFromGroupOrExt(bool modeEnabled, bool nsfwEnabled) {
    _chaosModeEnabled = modeEnabled;
    _chaosNsfwEnabled = nsfwEnabled;
    // Pressure left as-is or explicitly zeroed by caller per original reset sites.
  }

  /// Loads a saved chat's scalars. [nsfwEnabled] is null where the caller has
  /// no saved value of its own (a group session keeps the group's switch).
  void loadScalars({
    required bool modeEnabled,
    required int pressure,
    bool? nsfwEnabled,
  }) {
    _chaosModeEnabled = modeEnabled;
    _chaosPressure = pressure;
    _cooldownTurns = 0;
    if (nsfwEnabled != null) _chaosNsfwEnabled = nsfwEnabled;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  /// Clear the pending *injection* after it has been delivered in a response.
  /// (The display pendingChanceTimeEvent UI flag is managed in ChatService.)
  void clearDeliveredPendingIfAny() {
    if (_chaosEventDelivered) {
      _pendingChaosInjection = null;
      _chaosEventDelivered = false;
    }
  }

  /// Returns 8 events for the wheel, raw (placeholders unresolved).
  ///
  /// [allowPair] admits events naming a second cast member (`{{other}}`);
  /// [allowUser] admits events naming the user. Recently used events are
  /// skipped while enough others remain.
  List<String> spinWheelEvents({
    bool allowPair = false,
    bool allowUser = true,
  }) {
    return buildChaosWheel(
      includeAdult: spicyActive,
      allowPair: allowPair,
      allowUser: allowUser,
      recent: _recentEvents,
      random: _random,
    );
  }

  /// Records a raw event as used so the next few wheels skip it.
  void rememberEvent(String rawEvent) {
    _recentEvents
      ..remove(rawEvent)
      ..add(rawEvent);
    if (_recentEvents.length > recentMemory) _recentEvents.removeAt(0);
  }

  /// Core apply logic (pressure zero, cooldown start, injection set, realism
  /// metadata via cb, persist/notify). The caller (ChatService thin wrapper)
  /// resolves the placeholders, sets the UI flags and completes the completer.
  Future<void> applyPreparedEvent(String display) async {
    _pendingChaosInjection = display;
    _chaosPressure = 0;
    _cooldownTurns = frequency.cooldown;

    onSetPendingRealismMetadata('chance_time_event', display);

    await onSaveChat();
    onNotify();
    debugPrint('[ChanceTime] Applied: $display — injecting into next response');
  }

  /// Per-turn auto-trigger check. Returns true if the wheel should pop this turn.
  /// During a cooldown the turn is spent with no growth and no roll.
  bool checkAndTickChaosPressure() {
    if (!_chaosModeEnabled) return false;
    if (_cooldownTurns > 0) {
      _cooldownTurns--;
      return false;
    }
    final f = frequency;
    _chaosPressure = (_chaosPressure + f.growth).clamp(0, pressureCap);
    final effectiveChance = (f.base + _chaosPressure).clamp(0, pressureCap);
    final roll = _random.nextInt(100);
    final fires = roll < effectiveChance;
    if (fires) {
      debugPrint(
        '[ChanceTime] Auto-trigger! pressure=$_chaosPressure% roll=$roll',
      );
    }
    return fires;
  }

  // ── Prompt injection support ───────────────────────────────────────────────

  void markEventDelivered() {
    _chaosEventDelivered = true;
  }
}
