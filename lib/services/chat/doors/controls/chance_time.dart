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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_deps.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';

/// Chance Time: the wheel, the event it lands on and the send it parks.
/// The pressure math, pools, roll and the apply core live on
/// [ChaosModeService]; this holds the UI coordination around them (the
/// overlay trigger, the parked send, the phone's pre-picked event) and the
/// one hard-lock lookup spin and accept both re-gate through.
class ChanceTime {
  ChanceTime(this._d);

  final ControlsDeps _d;

  RealismGraph get _g => _d.graph();
  ChatSessionState get _session => _d.session;
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;

  /// The rotation head, moved past members who are Away or at work.
  CharacterCard? get _upcomingSpeaker =>
      _d.send().speakers.upcomingGroupSpeaker;

  /// Who a Chance Time event names: the upcoming group speaker, else the
  /// 1:1 host.
  String get _speakerName => _d.send().chanceReveal.chanceTimeSpeakerName;

  /// True for one cycle to pop the overlay.
  bool pendingTrigger = false;

  /// Pauses sendMessage while the wheel is up; whoever accepts first
  /// completes it.
  Completer<void>? completer;

  /// The single event the web/mobile "reveal your fate" modal shows and
  /// accepts while sendMessage is parked on [completer]. The desktop samples
  /// its own spinning wheel; a phone has no room for one, so one event is
  /// pre-picked from the same pool. Set at the gate, cleared on resume.
  String? webEvent;

  /// Who [webEvent] names, fixed at the spin.
  String? webName;

  /// Returns 8 raw events for the wheel. Pair events (`{{other}}`) need a
  /// second group member; user events need the user in the scene.
  List<String> spinWheelEvents() {
    _previewSpeaker();
    return _g.chaos.spinWheelEvents(
      allowPair: _partners(_speakerName).isNotEmpty,
      allowUser: !(_session.groupManager?.observerMode ?? false),
    );
  }

  /// Random turn order picks a speaker only when the turn starts, after the
  /// wheel has named someone. A spin makes that pick ahead instead, so the
  /// event, its 18+ gate and the reply follow one member. It is not a forced
  /// pick: an Away member coming back (an @-name, a quiet pulse) still
  /// answers, as in round robin. Round robin and a hand-picked or @-named
  /// member already name one.
  void _previewSpeaker() {
    if (_activeGroup == null || _upcomingSpeaker != null) return;
    _session.groupManager?.previewRandomSpeaker();
  }

  /// Accepting an event holds the member it names as the next random pick,
  /// in case a turn since the spin used that pick up.
  void _holdSpeaker(String name) {
    if (_activeGroup == null || _upcomingSpeaker != null) return;
    final card = _groupCharacters.where((c) => c.name == name).firstOrNull;
    if (card != null) _session.groupManager?.previewSpeaker(card);
  }

  /// PR 6: is the body Chance Time names mid a HARD refractory lock? 1:1 reads
  /// the live scalars (they hold the host, who is the attribution); groups map
  /// the NAME back to its card and read that member's STORED refractory —
  /// never the live scalars, which may still hold the previous speaker's. No
  /// match answers false: chaos fails open and spins today's wheel. Soft bodies
  /// answer false by decision — their desire is honest. A body Afterglow does
  /// not run for answers false too (Porch Life, the chat's switch or the
  /// member's): its recovery is kept hidden, and a hidden lock must not
  /// steer the wheel.
  bool hardLockForSpeakerNamed(String name) {
    if (_activeGroup == null) {
      if (!_g.nsfw.nsfwCooldownEnabled) return false;
      final r = _g.nsfw.refractory;
      return r.running && !r.soft;
    }
    final card = _groupCharacters.where((c) => c.name == name).firstOrNull;
    if (card == null) return false;
    final id = _d.hooks.characterIdFor(card);
    if (!_d.storage.realismSettings.afterglowEnabled ||
        !_g.groups.afterglowOnFor(id)) {
      return false;
    }
    final r = _g.groups.members[id]?.refractory ?? Refractory.none;
    return r.running && !r.soft;
  }

  /// The hard lock for whoever Chance Time names now.
  bool get speakerHardLocked => hardLockForSpeakerNamed(_speakerName);

  List<String> _partners(String speakerName) => [
    for (final c in _groupCharacters)
      if (c.name != speakerName) c.name,
  ];

  /// A raw event with its placeholders filled for [charName]: `{{user}}` is
  /// the persona, `{{other}}` a group member other than [charName]. The
  /// partner is picked from the event text, so the wheel's preview and the
  /// applied event always name the same person.
  String resolveChanceTimeEvent(String raw, String charName) {
    var text = raw.replaceAll('{{char}}', charName);
    if (text.contains('{{user}}')) {
      final user = _d.personas.persona.name.trim();
      text = text.replaceAll('{{user}}', user.isEmpty ? 'you' : user);
    }
    if (text.contains('{{other}}')) {
      final partners = _partners(charName);
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
    // One shared chat service serves both the desktop wheel and any web clients,
    // so either surface may resolve the same parked completer. Whoever lands
    // first wins; a late second accept is a no-op instead of completing an
    // already-completed completer (which would throw a StateError).
    final parked = completer;
    if (parked != null && parked.isCompleted) return;
    _holdSpeaker(charName);
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
        hardLockForSpeakerNamed(charName)) {
      final wheel = spinWheelEvents();
      applied = wheel.firstWhere(
        (t) => chaosEventFor(t)?.desireAsserting != true,
        // A wheel always carries SFW events (adults take only
        // kAdultWheelSlots of eight), so this orElse is a formality.
        orElse: () => wheel.first,
      );
    }
    final display = resolveChanceTimeEvent(applied, charName);
    _g.chaos.rememberEvent(applied);
    await _g.chaos.applyPreparedEvent(display);
    webEvent = null;
    webName = null;
    // Resume a parked send if one is waiting. Manual SPIN NOW has no
    // completer — applying the injection is the whole point.
    if (parked != null && !parked.isCompleted) parked.complete();
  }

  /// Per-turn auto-trigger check. Delegates to the service (verbatim
  /// roll/pressure logic).
  bool checkAndTickChaosPressure() => _g.chaos.checkAndTickChaosPressure();
}
