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

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/controls/chance_time.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_deps.dart';
import 'package:front_porch_ai/services/chat/doors/controls/group_member_ext_writer.dart';
import 'package:front_porch_ai/services/chat/doors/controls/member_chaos.dart';
import 'package:front_porch_ai/services/chat/doors/controls/member_switches.dart';
import 'package:front_porch_ai/services/chat/doors/controls/story_clock_nudges.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/storage_service.dart';

export 'package:front_porch_ai/services/chat/doors/controls/chance_time.dart';
export 'package:front_porch_ai/services/chat/doors/controls/controls_deps.dart';
export 'package:front_porch_ai/services/chat/doors/controls/story_clock_nudges.dart';

/// The chat's runtime switches and the gates read from them: Realism (the
/// chat's own switch behind Porch Life's permission), Needs, Objectives,
/// Afterglow, Chaos and its 18+ events, low hygiene, the call and the clock
/// (Porch Life's Passage of Time, read live), plus One-Shot's tri-state
/// decision. It also holds the permission watch, the start queue and the
/// user-turn hold, the story clock's manual controls ([clock]) and Chance
/// Time ([chance]).
///
/// Not a notifier: every write notifies through [ControlsDeps.notify]
/// synchronously, as the switches always did — Needs paints before its
/// save, and the composer and the overlay read each transition.
class ControlsDoor {
  ControlsDoor(this.deps);

  final ControlsDeps deps;

  ChatSessionState get _session => deps.session;
  StorageService get _storage => deps.storage;
  RealismGraph get _g => deps.graph();
  GroupChat? get _activeGroup => _session.activeGroup;

  // ── The chat's own switches: what a chat stores, seeds and carries ────

  /// This chat's own Realism switch. Realism runs behind [realismEnabled]
  /// (test/hygiene/realism_gate_ratchet_test.dart).
  bool _realismChatSwitch = false;

  /// The chat's STORED Needs switch: state, seeds and rewinds only. Needs
  /// run behind `NeedsPass.active` (test/hygiene/needs_gate_ratchet_test).
  bool needsSimEnabled = false;

  /// Per-chat Objectives switch (v45). Defaults true; read through
  /// [objectivesActive].
  bool objectivesEnabled = true;

  /// This chat's own Pockets & Wardrobe switch
  /// (docs/design/pockets-wardrobe-chat-toggle.md). Seeds from the card's
  /// default at new-chat entry and from the stored column on restore
  /// (missing column → derived from the card once, maintainer ruling D1).
  /// Group chats keep this honest but unused: their gate answers per member
  /// from the session bag. Missing reads on, as the card flag always did.
  bool _pocketsChatSwitch = true;

  /// The chat's stored "enjoys low hygiene" (the inversion for hygiene);
  /// [enjoysLowHygiene] prefers the live card.
  bool chatEnjoysLowHygiene = false;

  bool _callMode = false;

  /// The public switch, for the Realism toggle and test doubles.
  bool get realismChatSwitch => _realismChatSwitch;

  /// The chat's own Realism switch, for the stores, seeds and carries to
  /// read and write.
  bool get chatRealism => _realismChatSwitch;
  void setChatRealism(bool on) => _realismChatSwitch = on;

  /// The 1:1 chat's stored Pockets switch, for the save wire, seeds and the
  /// checkbox. NOT the gate — that is `PocketsLedger.pocketsEnabledFor`,
  /// which ANDs the Porch Life global and (in groups) the member's bag.
  bool get pocketsChatSwitch => _pocketsChatSwitch;
  void setChatPockets(bool on) => _pocketsChatSwitch = on;

  // ── The gates ─────────────────────────────────────────────────────────

  /// The Realism gate every reader goes through: Porch Life allows Realism
  /// (as of this turn's start) AND this chat's own switch, in a group the
  /// SPEAKING member's own ([GroupRealismStore.currentSpeakerId]: the one
  /// picked for the turn, else the next up). Saves, seeds and carries keep
  /// the raw switch, so Porch Life off never overwrites a chat's choice.
  bool get realismEnabled =>
      permission.allowed &&
      (_activeGroup == null
          ? _realismChatSwitch
          : _g.groups.realismOnFor(_g.groups.currentSpeakerId()));

  /// [realismEnabled] for member [id] of a group, whoever is speaking: a
  /// rewind of that member's reply, or a pass over the whole cast.
  bool realismEnabledFor(String? id) =>
      permission.allowed &&
      (_activeGroup == null ? chatRealism : _g.groups.realismOnFor(id));

  /// Objectives are actually running for this chat: the per-chat switch AND the
  /// global one (docs/design/feature-independence.md). Objectives depend on
  /// nothing but their own eval cost — not the Realism Engine, not the Journal.
  ///
  /// The global is applied LIVE here rather than AND-ed into
  /// [objectivesEnabled] at seed time the way Needs does it. That difference
  /// is deliberate: the stored-AND means flipping the global off leaves every
  /// already-open chat running, which for Needs is merely surprising but here
  /// would defeat the switch's whole purpose — stopping a recurring model
  /// call. Checking live means "off" takes effect on the next turn, everywhere.
  ///
  /// In a group the per-chat half is the SPEAKING member's own switch.
  bool get objectivesActive =>
      (_activeGroup == null
          ? objectivesEnabled
          : _g.groups.objectivesOnFor(_g.groups.currentSpeakerId())) &&
      _storage.realismSettings.objectivesEnabled;

  /// Porch Life Passage of Time — live. Not a seeded copy, not per-chat.
  bool get clockRunning => StoryClock.isRunning(
    passageOfTimeEnabled: _storage.realismSettings.passageOfTimeDefault,
  );

  /// The one-shot decision for THIS turn — the tri-state setting resolved
  /// against the live backend (pure policy in resolveOneShotMode; the
  /// probe verdict and locality are the only inputs storage can't know; both
  /// describe the model that runs the evals, the helper when one is on).
  /// Consulted by the pre-generation dance, the regen replay, and the
  /// retroactive baseline scan, so all three paths flip together.
  bool get oneShotActive => resolveOneShotMode(
    mode: _storage.realismSettings.oneShotMode,
    isLocal: deps.lanes.evalModelIsLocal,
    toolSupport: _g.transport.probe.supportFor(_g.transport.backendIdentity),
    // A live voice call upgrades Off to Auto's fuse-where-safe rule — one
    // eval call instead of three before the character can speak.
    callMode: _callMode,
    preferTextEvals: _storage.realismSettings.preferTextEvals,
  );

  /// Whether the app is in voice call mode (auto-disables reasoning for
  /// lower latency).
  bool get callMode => _callMode;

  /// Ending a call also releases any parked call-model swap.
  void setCallMode(bool value) {
    _callMode = value;
    if (!value) deps.send().exitCallModelSwap();
    deps.notify();
  }

  /// Returns whether the currently active character enjoys low hygiene.
  /// We always prefer the live value from the character's FrontPorchExtensions
  /// so that toggling the setting on the character immediately affects any
  /// already-loaded chats (no database change required).
  bool get enjoysLowHygiene {
    // Group chats have no single "active character" hygiene preference — it is
    // strictly per-speaker (the injection builders resolve it from each
    // member's own card). Never fall through to the 1:1 scalar in a group, or a
    // preference carried in from a previous 1:1 (e.g. a "enjoys being dirty"
    // character) would stay stale and invert every group member's hygiene.
    if (_activeGroup != null) {
      return _session.activeCharacter?.frontPorchExtensions?.enjoysLowHygiene ??
          false;
    }
    return _session.activeCharacter?.frontPorchExtensions?.enjoysLowHygiene ??
        chatEnjoysLowHygiene;
  }

  /// Re-reads the "Enjoys low hygiene" preference from the currently active
  /// character's FrontPorchExtensions. Call this after editing the character
  /// so that existing chats immediately pick up the new setting without a
  /// database change.
  void refreshEnjoysLowHygieneFromActiveCharacter() {
    if (_session.activeCharacter != null) {
      chatEnjoysLowHygiene =
          _session.activeCharacter!.frontPorchExtensions?.enjoysLowHygiene ??
          false;
      deps.notify();
    }
  }

  // ── Porch Life's permission, the start queue and the user-turn hold ───

  /// Porch Life's permission, landing between turns.
  late final RealismPermissionWatch permission = RealismPermissionWatch(
    allowed: () => _storage.realismSettings.realismAllowed,
    turnBusy: () => realismTurnBusy,
    turn: deps.turn,
    onChange: _onRealismPermissionChanged,
    ready: _storage.initialized,
  );

  /// A user turn from its send to its settle.
  late final UserTurnHold userTurn = UserTurnHold(deps.notify);

  late final RealismStartQueue _realismStart = RealismStartQueue(
    busy: () => realismTurnBusy || deps.cast().baseline.isProcessingGreeting,
    turn: deps.turn,
    chatId: () => _session.currentSessionId,
    start: _startRealismNow,
  );

  /// A turn in flight, the user's line and its pre-reply judges included.
  bool get realismTurnBusy => deps.engine().isTurnBusy || userTurn.held;

  void _onRealismPermissionChanged(bool allowed) {
    if (deps.life.disposed) return;
    deps.notify();
    if (allowed) onRealismStarted();
  }

  /// A 1:1 chat's Realism has started running: its switch turned on, Porch
  /// Life allowing it again, or a saved chat whose start scan was blocked.
  /// With no baseline yet it scores its starting point, once, from the
  /// greeting placed while Realism was off or from the history so far:
  /// between turns, never beside one or a second scan ([RealismStartQueue]).
  /// A group scores from its next turn, as it always has.
  void onRealismStarted() => _realismStart.request();

  void _startRealismNow() {
    if (!realismEnabled ||
        _activeGroup != null ||
        _session.activeCharacter == null) {
      return;
    }
    final baseline = deps.cast().baseline;
    if (baseline.greetingEvalPending && !_g.dance.hasBaseline) {
      debugPrint(
        '[Realism] Consuming pending greeting eval (Realism started).',
      );
      unawaited(baseline.runPostGreetingEval());
    } else if (!_g.dance.hasBaseline && _session.messages.length > 1) {
      debugPrint('[Realism] No baseline detected — running retroactive scan.');
      unawaited(baseline.runRetroactiveBaselineEval());
    }
  }

  // ── Switch writes ─────────────────────────────────────────────────────

  /// A group member's own switches in this chat; the sidebar and the phone
  /// write them by member id. In a group [setRealismEnabled] and its kin are
  /// the chat-wide cards of Group Settings, which turn the whole cast.
  late final MemberSwitches memberSwitches = MemberSwitches(deps);

  Future<void> setRealismEnabled(bool enabled) async {
    _realismChatSwitch = enabled;
    memberSwitches.applyToAll(realism: enabled);
    if (enabled) onRealismStarted();

    if (!enabled) {
      // IMPORTANT: Do NOT zero out realism state when disabling!
      // Just stop using it. State persists in memory/DB so re-enabling restores it.
      // Old behavior was destructive - it deleted all character building progress.
      debugPrint(
        '[Realism] Disabled (preserving state: bond=${_g.relationship.affectionScore}, trust=${_g.relationship.trustLevel}, emotion=${_g.registers.emotion})',
      );
    }
    await deps.saveChat();
    deps.notify();
  }

  /// Writes Porch Life Passage of Time — the live clock gate.
  Future<void> setPassageOfTimeEnabled(bool enabled) async {
    await _storage.realismSettings.setPassageOfTimeDefault(enabled);
    _g.time.markClockGateSource('porch_life');
    deps.notify();
  }

  /// Toggles the Needs Simulation for the current session.
  ///
  /// - `true`: initializes the default need vector (if empty) then begins tracking.
  /// - `false`: hides the strip. The live vector stays so save can tell
  ///   explicit OFF from a never-seeded row (hide ≠ erase).
  ///
  /// The change is persisted with the session and broadcast.
  /// Matches the side-effect style of [setAfterglowEnabled] and [setChaosModeEnabled].
  Future<void> setNeedsSimEnabled(bool enabled) async {
    needsSimEnabled = enabled;
    memberSwitches.applyToAll(needs: enabled);
    // Enabling mid-chat: the needs vector is only seeded at chat start (see
    // chat_entry/group_entry), so a toggle-on after a needs-off start leaves it
    // empty and the sidebar shows no scores. Seed it now from the active
    // character/group baselines, mirroring the chat-start init so 1:1 and group
    // behave identically. Off must not wipe the kit — a later save of
    // false+null looks like a stale never-seeded row and hydrate would
    // flip Needs back on.
    final needs = _g.needs;
    if (enabled && needs.vector.isEmpty) {
      if (_activeGroup != null) {
        needs.initializeFreshWithDefaults(const {
          'hunger': 80,
          'bladder': 80,
          'energy': 80,
          'social': 80,
          'fun': 80,
          'hygiene': 80,
          'comfort': 80,
        });
      } else {
        final ext = _session.activeCharacter?.frontPorchExtensions;
        if (ext != null) {
          needs.initializeFreshWithDefaults(
            NeedsSimulation.baselinesFromExtensions(ext),
          );
        } else {
          needs.initializeFresh();
        }
      }
    }
    // Paint first. A save that throws (unmodifiable needsOff used to)
    // must not leave the switch ON and the strip empty.
    deps.notify();
    await deps.saveChat();
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
    objectivesEnabled = enabled;
    memberSwitches.applyToAll(objectives: enabled);
    await deps.saveChat();
    deps.notify();
  }

  /// Turn this 1:1 chat's Pockets & Wardrobe on or off.
  /// (docs/design/pockets-wardrobe-chat-toggle.md.)
  ///
  /// `false` HIDES and freezes: the record is retained verbatim (the save
  /// wire writes it outside the gate), no pockets model call runs, hand
  /// edits are refused — no catch-up mechanic, and the confirmation dialog
  /// says so before the flip. `true` resumes from the retained record and
  /// seeds the card's starting kit once ONLY for a chat with no record at
  /// all, the way [setNeedsSimEnabled] seeds the vector. Never a retro-scan.
  Future<void> setPocketsEnabled(bool enabled) async {
    _pocketsChatSwitch = enabled;
    if (enabled && _g.hostPockets == null) {
      final card = _session.activeCharacter;
      if (card != null) {
        final seed = PocketsLedger.startingPocketsFor(card);
        if (!seed.isEmpty) _g.hostPockets = seed;
      }
    }
    // Paint first, same rule as Needs: a save that throws must not leave
    // the switch flipped against a stale panel.
    deps.notify();
    await deps.saveChat();
  }

  /// A group member's per-chat Pockets switch — same contract as
  /// [setPocketsEnabled] for that member alone: off freezes and hides only
  /// their track. The UI confirms the freeze, naming the member.
  Future<void> setMemberPocketsEnabled(String memberId, bool enabled) async {
    final bag = _g.groups.members[memberId];
    if (enabled && bag?.pockets == null) {
      for (final c in _session.groupCharacters) {
        if (deps.session.characterIdFor(c) == memberId) {
          final seed = PocketsLedger.startingPocketsFor(c);
          if (!seed.isEmpty) {
            _g.groups.memberForWrite(memberId).pockets = seed;
          }
          break;
        }
      }
    }
    _g.groups.memberForWrite(memberId).pocketsSwitch = enabled;
    deps.notify();
    await deps.saveChat();
  }

  /// The switch the checkbox shows: the 1:1 chat's stored choice, or the
  /// member's per-chat choice (their bag, falling back to the card default
  /// for a chat the entry seed has not written yet). The STORED value, not
  /// the live gate — the gate would grey the switch under a Porch Life veto
  /// the user already made their choice about.
  bool pocketsSwitchFor(String memberId) {
    if (_activeGroup == null) return _pocketsChatSwitch;
    final seeded = _g.groups.members[memberId]?.pocketsSwitch;
    if (seeded != null) return seeded;
    for (final c in _session.groupCharacters) {
      if (deps.session.characterIdFor(c) == memberId) {
        return c.frontPorchExtensions?.pocketsEnabled ?? true;
      }
    }
    return true;
  }

  Future<void> setChaosModeEnabled(bool enabled) async {
    _g.chaos.setModeEnabled(enabled);
    await deps.saveChat();
    deps.notify();
  }

  Future<void> setChaosNsfwEnabled(bool enabled) async {
    _g.chaos.setNsfwEnabled(enabled);
    await deps.saveChat();
    deps.notify();
  }

  // ── Chaos per member (PR 5b, docs/design/chaos-per-character.md) ─────
  // The member-scoped reads/writes the sidebar's Chaos card and the web
  // twin go through; bodies in [MemberChaos].
  late final MemberChaos chaosMembers = MemberChaos(deps, memberSwitches);

  /// This chat's own Afterglow switch: the 1:1 chat's stored flag, or, in a
  /// group, the older chat-wide one. Nothing shows it in a group any more:
  /// each member has their own ([MemberSwitches]), and it only seeds them.
  bool get afterglowChatSwitch => _activeGroup == null
      ? _g.nsfw.storedNsfwCooldownEnabled
      : _g.groups.afterglowOn;

  /// The switches over the body the scalars hold: the 1:1 chat's, or the
  /// group chat's AND that member's own.
  bool get afterglowSwitchForLoaded => _activeGroup == null
      ? _g.nsfw.storedNsfwCooldownEnabled
      : _g.groups.afterglowOnFor(_g.nsfw.loadedMemberId);

  /// Writes [afterglowChatSwitch]. It counts only while Porch Life (with
  /// 18+) allows Afterglow. Off hides Lust and recovery and holds them where
  /// they are (hide, never erase, as Pockets does); on shows them again,
  /// unchanged. Nothing zeroes them either way, in a 1:1 or for any member.
  /// In a group it turns the whole cast; one member's is
  /// [MemberSwitches.setAfterglow].
  Future<void> setAfterglowEnabled(bool enabled) async {
    if (_activeGroup == null) {
      if (enabled == afterglowChatSwitch) return;
      _g.nsfw.setNsfwCooldownEnabled(enabled);
    } else {
      _g.groups.afterglowOn = enabled;
      memberSwitches.applyToAll(afterglow: enabled);
    }
    await deps.saveChat();
    deps.notify();
  }

  // ── The story clock's controls and Chance Time ────────────────────────

  late final StoryClockNudges clock = StoryClockNudges(
    deps,
    clockRunning: () => clockRunning,
  );

  late final ChanceTime chance = ChanceTime(deps);

  // ── A group member's own switches, persisted ──────────────────────────

  /// Write a group member's current extensions (pace, which needs are on,
  /// baselines, the defaults a new chat starts from) to the avatar and the
  /// group-members row.
  Future<void> persistGroupMemberExtensions({String? memberId}) =>
      _extWriter.persist(memberId: memberId);

  late final GroupMemberExtWriter _extWriter = GroupMemberExtWriter(deps);
}
