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
    // (The story clock is always anchored — the old ensureStartDayOfWeekAnchored
    // legacy-0 repair died with the modulo-7 weekday math.)

    if (enabled && _activeGroup == null && _activeCharacter != null) {
      // ── Solution 1: Pending greeting flag ────────────────────────────
      // The greeting was placed while realism was off. Fire the baseline
      // eval now that the user has explicitly enabled it.
      if (_greetingEvalPending && !_realismDance.hasBaseline) {
        debugPrint(
          '[Realism] Consuming pending greeting eval (user enabled realism after load).',
        );
        _runPostGreetingEval();
      }
      // ── Solution 3: Retroactive scan on enable ────────────────────────
      // Realism was enabled mid-conversation with no baseline captured yet
      // (emotion is blank, affection is zero, multiple messages exist).
      // Run a full retrospective eval against all visible messages.
      else if (!_realismDance.hasBaseline && _messages.length > 1) {
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

  Future<void> _setPassageOfTimeEnabledImpl(bool enabled) async {
    await _storageService.realismSettings.setPassageOfTimeDefault(enabled);
    _timeService.markClockGateSource('porch_life');
    notifyListeners();
  }

  /// Toggles the Needs Simulation for the current session.
  ///
  /// - `true`: initializes the default need vector (if empty) then begins tracking.
  /// - `false`: hides the strip. The live vector stays so save can tell
  ///   explicit OFF from a never-seeded row (hide ≠ erase).
  ///
  /// The change is persisted with the session and broadcast via [notifyListeners].
  /// Matches the side-effect style of [setNsfwCooldownEnabled] and [setChaosModeEnabled].
  Future<void> setNeedsSimEnabled(bool enabled) async {
    _needsSimEnabled = enabled;
    // Enabling mid-chat: the needs vector is only seeded at chat start (see
    // chat_entry/group_entry), so a toggle-on after a needs-off start leaves it
    // empty and the sidebar shows no scores. Seed it now from the active
    // character/group baselines, mirroring the chat-start init so 1:1 and group
    // behave identically. Off must not wipe the kit — a later save of
    // false+null looks like a stale never-seeded row and hydrate would
    // flip Needs back on.
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
          _needsSimulation.initializeFreshWithDefaults(
            NeedsSimulation.baselinesFromExtensions(ext),
          );
        } else {
          _needsSimulation.initializeFresh();
        }
      }
    }
    // Paint first. A save that throws (unmodifiable needsOff used to)
    // must not leave the switch ON and the strip empty.
    notifyListeners();
    await _saveChat();
  }

  /// The character editor is the 1:1 Needs switch now that the chat sidebar
  /// has none. A save that moves the card's choice away from [before] applies
  /// it to every 1:1 chat with that character: the open one live, the others
  /// through their stored flag, which hydrate reads on open. A save that
  /// leaves the choice alone touches no chat, so fixing a typo never flips
  /// Needs. Group chats keep their own switch in Group Settings → Needs.
  Future<void> followCardNeedsChoice(
    CharacterCard card, {
    required bool? before,
  }) async {
    final after = card.frontPorchExtensions?.needsSimChoice;
    if (after == null || after == before) return;
    final dbId = card.dbId;
    final active = _activeCharacter;
    if (_activeGroup == null &&
        active != null &&
        (identical(active, card) || (dbId != null && active.dbId == dbId))) {
      await setNeedsSimEnabled(after);
    }
    if (dbId == null) return;
    // The open chat's row too: its own save skips a chat with no messages.
    for (final s in await _db.getSessionsForCharacter(dbId)) {
      if (s.groupId != null || s.needsSimEnabled == after) continue;
      await _db.patchSession(
        SessionsCompanion(
          id: drift.Value(s.id),
          needsSimEnabled: drift.Value(after),
        ),
      );
    }
  }

  /// Per-chat Objectives switch (v45). Off means the quests stop running: no
  /// completion checks, no autonomous proposals, no task generation, and the
  /// sidebar panel goes away.
  ///
  /// The objective ROWS are deliberately left alone. Turning a feature off must
  /// not delete a user's work — flip it back on and every quest, task and tick
  /// is exactly where it was. Same "inert, values preserved" contract the NSFW
  /// cooldown follows.
  Future<void> setObjectivesEnabled(bool enabled) async {
    _objectivesEnabled = enabled;
    await _saveChat();
    notifyListeners();
  }

  // ── Manual Time Nudge ────────────────────────────────────────────────────

  /// Called by the sidebar chevron buttons. delta = +1 (forward) or -1 (back).
  /// Thin delegation to TimeService (core logic + cb-driven patch). Save/notify
  /// + `_clockRunning` guard kept in god wrapper (UI coordination).
  Future<void> nudgeTimePeriod(int delta) async {
    if (!_clockRunning) return;
    final before = _timeService.clock;
    _clockWriter.pendingNudgeBefore = before;
    await _timeService.nudgeTimePeriod(delta);
    _clockWriter.writeSlotClock(
      _clockReader.visibleTipMessage(),
      kind: SlotClockWrite.nudge,
    );
    // Day-ate journal rides TimeService.onStoryDayChanged.
    await _episodeCrumbs.maybeMint(before, _timeService.clock);
    unawaited(_birthdaySync.ensure());
    await _saveChat();
    notifyListeners();
  }

  /// Calendar dialog: set the story's current date & time directly.
  /// Same guard/save/notify shape as the nudge (it IS a precise nudge).
  Future<void> setStoryClock(DateTime clock) async {
    if (!_clockRunning) return;
    final before = _timeService.clock;
    _clockWriter.pendingNudgeBefore = before;
    await _timeService.setClockDirect(clock);
    _clockWriter.writeSlotClock(
      _clockReader.visibleTipMessage(),
      kind: SlotClockWrite.nudge,
    );
    // Day-ate journal rides TimeService.onStoryDayChanged.
    await _episodeCrumbs.maybeMint(before, _timeService.clock);
    unawaited(_birthdaySync.ensure());
    await _saveChat();
    notifyListeners();
  }

  /// Calendar dialog: re-anchor "story begins on…" — the whole timeline
  /// slides together (Day N is preserved, every date re-derives).
  Future<void> setStoryStartDate(DateTime date) async {
    if (!_clockRunning) return;
    final oldStart = _timeService.startDate;
    _timeService.setStartDate(date);
    final delta = _timeService.startDate.difference(oldStart);
    shiftMessageClockStamps(_messages, delta);
    await _shiftPersistedSessionClockStamps(delta);
    _clockReader.applyTipClock();
    unawaited(_birthdaySync.ensure());
    await _saveChat();
    notifyListeners();
  }

  Future<void> _shiftPersistedSessionClockStamps(Duration delta) async {
    final sid = _currentSessionId;
    if (sid == null || delta == Duration.zero) return;
    final rows = await _db.getMessagesForSession(sid);
    final seen = Set<Map>.identity();
    for (final row in rows) {
      var changed = false;
      Map<String, dynamic>? meta;
      if (row.metadata != null) {
        meta = Map<String, dynamic>.from(
          jsonDecode(row.metadata!) as Map<String, dynamic>,
        );
        if (shiftClockFields(meta, delta, seen)) changed = true;
      }
      List<dynamic>? swipes;
      if (row.swipeMetadata != null) {
        swipes = [
          for (final e in jsonDecode(row.swipeMetadata!) as List<dynamic>)
            e == null
                ? null
                : () {
                    final m = Map<String, dynamic>.from(e as Map);
                    if (shiftClockFields(m, delta, seen)) changed = true;
                    return m;
                  }(),
        ];
      }
      if (!changed) continue;
      await _db.updateMessage(
        MessagesCompanion(
          id: drift.Value(row.id),
          metadata: drift.Value(meta == null ? null : jsonEncode(meta)),
          swipeMetadata: drift.Value(
            swipes == null ? null : jsonEncode(swipes),
          ),
        ),
      );
    }
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

  bool get _afterglowChatSwitchImpl => _activeGroup == null
      ? _nsfwService.storedNsfwCooldownEnabled
      : _groupStore.afterglowOn;

  /// This chat's own Afterglow switch: the 1:1 chat's stored flag, or the
  /// group chat's. It counts only while Porch Life (with 18+) allows
  /// Afterglow. Either way the chat starts from calm: off zeroes Lust and
  /// any recovery, as it always has, and on starts from calm whatever a
  /// rewind or a re-score left in memory while it was off.
  Future<void> _setAfterglowEnabledImpl(bool enabled) async {
    if (enabled == _afterglowChatSwitchImpl) return;
    if (_activeGroup == null) {
      _nsfwService.setNsfwCooldownEnabled(enabled);
    } else {
      _groupStore.afterglowOn = enabled;
      for (final id in _groupRealism.keys.toList()) {
        _groupStore.memberForWrite(id)
          ..arousal = 0
          ..refractory = Refractory.none;
      }
    }
    _nsfwService.resetRuntimeArousalAndCooldown();
    await _saveChat();
    notifyListeners();
  }

  /// Returns 8 raw events for the wheel. Pair events (`{{other}}`) need a
  /// second group member; user events need the user in the scene.
  List<String> spinWheelEvents() {
    return _chaosModeService.spinWheelEvents(
      allowPair: _chanceTimePartners(chanceTimeSpeakerName).isNotEmpty,
      allowUser: !observerMode,
    );
  }

  /// PR 6: is the body Chance Time names mid a HARD refractory lock? 1:1
  /// reads the live scalars (they hold the host, who is the attribution);
  /// groups map the NAME back to its card and read that member's STORED
  /// refractory — never the live scalars, which may still hold the
  /// previous speaker's. No match answers false: chaos fails open and
  /// spins today's wheel. Soft bodies answer false by decision — their
  /// desire is honest.
  bool _hardLockForSpeakerNamed(String name) {
    if (_activeGroup == null) {
      final r = _nsfwService.refractory;
      return r.running && !r.soft;
    }
    final card = _groupCharacters.where((c) => c.name == name).firstOrNull;
    if (card == null) return false;
    final r =
        _groupStore.members[_getCharacterIdFromCard(card)]?.refractory ??
        Refractory.none;
    return r.running && !r.soft;
  }

  List<String> _chanceTimePartners(String speakerName) => [
    for (final c in groupCharacters)
      if (c.name != speakerName) c.name,
  ];

  /// A raw event with its placeholders filled for [charName]: `{{user}}` is
  /// the persona, `{{other}}` a group member other than [charName]. The
  /// partner is picked from the event text, so the wheel's preview and the
  /// applied event always name the same person.
  String resolveChanceTimeEvent(String raw, String charName) {
    var text = raw.replaceAll('{{char}}', charName);
    if (text.contains('{{user}}')) {
      final user = _userPersonaService.persona.name.trim();
      text = text.replaceAll('{{user}}', user.isEmpty ? 'you' : user);
    }
    if (text.contains('{{other}}')) {
      final partners = _chanceTimePartners(charName);
      final other = partners.isEmpty
          ? 'someone nearby'
          : partners[raw.hashCode.abs() % partners.length];
      text = text.replaceAll('{{other}}', other);
    }
    return text;
  }

  /// Called by the wheel overlay once the animation lands on an event.
  /// Thin wrapper: resolve the placeholders, remember the event so the next
  /// wheels skip it, delegate core (pressure/cooldown/injection/metadata/save/
  /// notify) to the service, then complete the completer.
  Future<void> applyChanceTimeResult(String event, String charName) async {
    // One shared ChatService serves both the desktop wheel and any web clients,
    // so either surface may resolve the same parked completer. Whoever lands
    // first wins; a late second accept is a no-op instead of completing an
    // already-completed completer (which would throw a StateError).
    final completer = _chanceTimeCompleter;
    if (completer != null && completer.isCompleted) return;
    // PR 6 re-gate at ACCEPT (review M1): a manual SPIN NOW parks without
    // halting generation, so between spin and accept a group pointer can
    // rotate onto a body that was locked the whole window, and an
    // intervening climax can lock the 1:1 host. A desire-asserting event
    // whose named body is locked NOW must not land: swap in the first
    // desire-free event from a fresh gated spin. Legality beats fidelity
    // to the card that was shown — `Lust: 0` with aroused prose is the
    // exact trust break this PR exists to close.
    var applied = event;
    if (chaosEventFor(event)?.desireAsserting == true &&
        _hardLockForSpeakerNamed(charName)) {
      final wheel = spinWheelEvents();
      applied = wheel.firstWhere(
        (t) => chaosEventFor(t)?.desireAsserting != true,
        // A wheel always carries SFW events (adults take only
        // kAdultWheelSlots of eight), so this orElse is a formality.
        orElse: () => wheel.first,
      );
    }
    final display = resolveChanceTimeEvent(applied, charName);
    _chaosModeService.rememberEvent(applied);
    await _chaosModeService.applyPreparedEvent(display);
    _webChanceTimeEvent = null;
    // Resume a parked send if one is waiting. Manual SPIN NOW has no
    // completer — applying the injection is the whole point.
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  /// Per-turn auto-trigger check. Delegates to service (verbatim roll/pressure logic).
  bool checkAndTickChaosPressure() {
    return _chaosModeService.checkAndTickChaosPressure();
  }

  // ── Central dispose guard (rec 2 from PR #47) ─────────────────────────────────
  // Overrides protect every notifyListeners() call (many direct + after async DB/repo
  // work) from post-dispose use. Placed here (not a new void _ private) to obey god
  // rules (void _ count must stay exactly 15 live grep after every edit + final).
  // Deletion of the now-redundant per-site try/catch guard in _loadActiveObjectives
  // (and its comment) is part of this task (see that site for the removed code).
  /// Write a group member's current extensions (pace, which needs are on,
  /// baselines) to the avatar and the group-members row.
  Future<void> persistGroupMemberExtensions({String? memberId}) async {
    if (_activeGroup == null) return;

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
        ext.ensureStableId();
        char.frontPorchExtensions = ext;

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
              frontPorchExtensions: drift.Value(jsonEncode(ext.toJson())),
            ),
          );
        }
      }
    }

    await _saveChat();
    notifyListeners();
  }
}
