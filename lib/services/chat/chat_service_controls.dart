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

/// Public runtime toggle/control surface for the Realism, Needs, Chaos and
/// Chance-Time systems: the feature enable switches (realism, NSFW cooldown,
/// passage of time, needs sim, chaos mode/NSFW), time nudging, the chance-time
/// wheel + apply, chaos-pressure tick, and the per-need decay-rate setters
/// (1:1 and group). Extracted verbatim from the god file (zero behaviour
/// change). The decay-rate setters keep their existing 1:1-vs-group branch, so
/// Realism/Needs parity is unchanged by the move.
extension ChatServiceControls on ChatService {
  // ── Public Toggle Methods ──

  Future<void> setRealismEnabled(bool enabled) async {
    _realismEnabled = enabled;
    // Anchor the narrative weekday to the real-world day when realism first turns on for this session.
    // Only set if not already anchored (0 = legacy/unset). This prevents re-anchoring on toggle-off/on
    // for long-running sessions, keeping Day N stable across restarts.
    if (enabled) {
      _timeService.ensureStartDayOfWeekAnchored();
    }

    if (enabled && _activeGroup == null && _activeCharacter != null) {
      // ── Solution 1: Pending greeting flag ────────────────────────────
      // The greeting was placed while realism was off. Fire the baseline
      // eval now that the user has explicitly enabled it.
      if (_greetingEvalPending && !_hasRealismBaseline) {
        debugPrint(
          '[Realism] Consuming pending greeting eval (user enabled realism after load).',
        );
        _runPostGreetingEval();
      }
      // ── Solution 3: Retroactive scan on enable ────────────────────────
      // Realism was enabled mid-conversation with no baseline captured yet
      // (emotion is blank, affection is zero, multiple messages exist).
      // Run a full retrospective eval against all visible messages.
      else if (!_hasRealismBaseline && _messages.length > 1) {
        debugPrint(
          '[Realism] No baseline detected — running retroactive scan on enable.',
        );
        _runRetroactiveBaselineEval();
      }
    }

    if (!enabled) {
      // IMPORTANT: Do NOT zero out realism state when disabling!
      // Just stop using it. State persists in memory/DB so re-enabling restores it.
      // Old behavior was destructive - it deleted all character building progress.
      debugPrint(
        '[Realism] Disabled (preserving state: bond=${_relationshipService.affectionScore}, trust=${_relationshipService.trustLevel}, emotion=$_characterEmotion)',
      );
    }
    await _saveChat();
    notifyListeners();
  }

  Future<void> setNsfwCooldownEnabled(bool enabled) async {
    _nsfwService.setNsfwCooldownEnabled(enabled);
    // In a group the flag is PER-CHARACTER (each speaker's eval reloads it via
    // loadNsfwScalarsForSpeaker), so the chat-wide toggle must be written into
    // EVERY member's _groupRealism entry — otherwise members keep their stale
    // (off) per-char flag and arousal is never evaluated for them. (1:1 just uses
    // the scalar above; this loop is a no-op there.)
    if (_activeGroup != null) {
      for (final c in _groupCharacters) {
        final id = _getCharacterIdFromCard(c);
        final entry = _groupRealism[id] ??= <String, dynamic>{};
        entry['nsfwCooldownEnabled'] = enabled;
        // Parity with 1:1: NsfwService.setNsfwCooldownEnabled(false) zeroes
        // the scalar arousal + cooldowns, so disabling must clear each
        // member's persisted values too — otherwise re-enabling resumed
        // members from stale arousal/cooldowns while a 1:1 chat restarted
        // fresh. (Also the documented escape hatch: toggling off and on
        // resets a chat's lust state to neutral in BOTH modes.)
        if (!enabled) {
          entry['arousal'] = 0;
          entry['cooldownTurnsRemaining'] = 0;
          entry['cooldownTurnsTotal'] = 0;
        }
      }
    }
    await _saveChat();
    notifyListeners();
  }

  Future<void> setPassageOfTimeEnabled(bool enabled) async {
    _timeService.setPassageOfTimeEnabled(enabled);
    await _saveChat();
    notifyListeners();
  }

  /// Toggles the Needs Simulation for the current session.
  ///
  /// - `true`: initializes the default need vector (if empty) then begins tracking.
  /// - `false`: clears the in-memory vector (levels are discarded for this session).
  ///
  /// The change is persisted with the session and broadcast via [notifyListeners].
  /// Matches the side-effect style of [setNsfwCooldownEnabled] and [setChaosModeEnabled].
  Future<void> setNeedsSimEnabled(bool enabled) async {
    _needsSimEnabled = enabled;
    // Enabling mid-chat: the needs vector is only seeded at chat start (see
    // chat_entry/group_entry), so a toggle-on after a needs-off start leaves it
    // empty and the sidebar shows no scores. Seed it now from the active
    // character/group baselines, mirroring the chat-start init so 1:1 and group
    // behave identically.
    if (enabled && _needsSimulation.vector.isEmpty) {
      if (_activeGroup != null) {
        _needsSimulation.initializeFreshWithDefaults(const {
          'hunger': 80,
          'bladder': 80,
          'energy': 80,
          'social': 80,
          'fun': 80,
          'hygiene': 80,
          'comfort': 80,
        });
      } else {
        final ext = _activeCharacter?.frontPorchExtensions;
        if (ext != null) {
          _needsSimulation.initializeFreshWithDefaults({
            'hunger': ext.needsBaselineHunger,
            'bladder': ext.needsBaselineBladder,
            'energy': ext.needsBaselineEnergy,
            'social': ext.needsBaselineSocial,
            'fun': ext.needsBaselineFun,
            'hygiene': ext.needsBaselineHygiene,
            'comfort': ext.needsBaselineComfort,
          });
        } else {
          _needsSimulation.initializeFresh();
        }
      }
    }
    await _saveChat();
    notifyListeners();
  }

  // ── Manual Time Nudge ────────────────────────────────────────────────────

  /// Called by the sidebar chevron buttons. delta = +1 (forward) or -1 (back).
  /// Thin delegation to TimeService (core logic + cb-driven patch). Save/notify
  /// + realism guard kept in god wrapper (UI coordination).
  Future<void> nudgeTimePeriod(int delta) async {
    if (!_realismEnabled) return;
    _timeService.nudgeTimePeriod(delta);
    await _saveChat();
    notifyListeners();
  }

  // ── Chaos Mode / Chance Time (thin delegation to extracted service) ──────
  // Control sets delegate fully (like needsSimEnabled precedent). Actions thin to
  // handle the UI-coordination flags (pendingEvent, completer) that stay in god.
  // All impl (pressure math, pools, roll, apply core, etc.) deleted from here.

  Future<void> setChaosModeEnabled(bool enabled) async {
    _chaosModeService.setModeEnabled(enabled);
    await _saveChat();
    notifyListeners();
  }

  Future<void> setChaosNsfwEnabled(bool enabled) async {
    _chaosModeService.setNsfwEnabled(enabled);
    await _saveChat();
    notifyListeners();
  }

  /// Clear the pending event after the UI has consumed it.
  void clearChanceTimeEvent() {
    _pendingChanceTimeEvent = null;
    // no notifyListeners — avoids rebuild storms; UI already consumed it
  }

  /// Returns 8 randomly-sampled events for the wheel UI to display.
  List<String> spinWheelEvents() {
    return _chaosModeService.spinWheelEvents();
  }

  /// Called by the wheel overlay once the animation lands on an event.
  /// Thin wrapper: compute display ({{char}} replace), set UI flag, delegate core
  /// (pressure/injection/metadata/save/notify) to service, then complete completer.
  Future<void> applyChanceTimeResult(String event, String charName) async {
    // One shared ChatService serves both the desktop wheel and any web clients,
    // so either surface may resolve the same parked completer. Whoever lands
    // first wins; a late second accept is a no-op instead of completing an
    // already-completed completer (which would throw a StateError).
    final completer = _chanceTimeCompleter;
    if (completer == null || completer.isCompleted) return;
    final display = event.replaceAll('{{char}}', charName);
    _pendingChanceTimeEvent = display;
    await _chaosModeService.applyPreparedEvent(display);
    // Resume the paused sendMessage flow (UI coordination stays in god).
    // Re-check: applyPreparedEvent awaited above, so the other surface could
    // have completed it in the gap.
    if (!completer.isCompleted) completer.complete();
  }

  /// Per-turn auto-trigger check. Delegates to service (verbatim roll/pressure logic).
  bool checkAndTickChaosPressure() {
    return _chaosModeService.checkAndTickChaosPressure();
  }

  // (Chance Time pools moved verbatim to ChaosModeService; deletion complete.)

  // ── Central dispose guard (rec 2 from PR #47) ─────────────────────────────────
  // Overrides protect every notifyListeners() call (many direct + after async DB/repo
  // work) from post-dispose use. Placed here (not a new void _ private) to obey god
  // rules (void _ count must stay exactly 15 live grep after every edit + final).
  // Deletion of the now-redundant per-site try/catch guard in _loadActiveObjectives
  // (and its comment) is part of this task (see that site for the removed code).
  /// Update a group member's needs decay rate. With [memberId] null this targets
  /// every member (legacy "apply to all"); with a [memberId] it targets that one
  /// member — the per-character path the Group Settings UI now uses so each
  /// member decays at its own rate. Persists to the member card ext + PNG + the
  /// GroupMembers row, which is exactly what runtime `_activeDecayRates()` reads.
  Future<void> setGroupNeedsDecayRate(
    String key,
    int value, {
    String? memberId,
  }) async {
    if (_activeGroup == null) return;
    // The legacy shared map only has meaning for the "apply to all" call; a
    // per-member edit writes straight to that member's card ext below.
    if (memberId == null) _groupDecayRates[key] = value;

    if (_characterRepository != null) {
      final v2Service = V2CardService();
      final db = await AppDatabase.instance();

      final targets = memberId == null
          ? _groupCharacters
          : _groupCharacters.where(
              (c) => _getCharacterIdFromCard(c) == memberId,
            );
      for (final char in targets) {
        final ext = char.frontPorchExtensions ?? FrontPorchExtensions();
        final newExt = ext.copyWith(
          needsDecayHunger: key == 'hunger' ? value : null,
          needsDecayBladder: key == 'bladder' ? value : null,
          needsDecayEnergy: key == 'energy' ? value : null,
          needsDecaySocial: key == 'social' ? value : null,
          needsDecayFun: key == 'fun' ? value : null,
          needsDecayHygiene: key == 'hygiene' ? value : null,
          needsDecayComfort: key == 'comfort' ? value : null,
        );
        newExt.ensureStableId();
        char.frontPorchExtensions = newExt;

        if (char.imagePath != null) {
          final file = File(char.imagePath!);
          if (await file.exists()) {
            await v2Service.saveCardAsPng(
              char,
              char.imagePath!,
              char.imagePath!,
            );
          }
        }

        if (char.dbId != null) {
          await db.updateGroupMember(
            GroupMembersCompanion(
              id: drift.Value(char.dbId!),
              frontPorchExtensions: drift.Value(jsonEncode(newExt.toJson())),
            ),
          );
        }
      }
    }

    await _saveChat();
    notifyListeners();
  }

  /// Update a decay rate for the active 1:1 character
  Future<void> setNeedsDecayRate(String key, int value) async {
    if (_activeCharacter == null || _characterRepository == null) return;

    final ext =
        _activeCharacter!.frontPorchExtensions ?? FrontPorchExtensions();
    final newExt = ext.copyWith(
      needsDecayHunger: key == 'hunger' ? value : null,
      needsDecayBladder: key == 'bladder' ? value : null,
      needsDecayEnergy: key == 'energy' ? value : null,
      needsDecaySocial: key == 'social' ? value : null,
      needsDecayFun: key == 'fun' ? value : null,
      needsDecayHygiene: key == 'hygiene' ? value : null,
      needsDecayComfort: key == 'comfort' ? value : null,
    );
    newExt.ensureStableId();
    _activeCharacter!.frontPorchExtensions = newExt;

    await _characterRepository!.updateCharacter(_activeCharacter!);
    notifyListeners();
  }
}
