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

import 'package:front_porch_ai/services/chat/chaos/chaos_frequency.dart';
import 'package:front_porch_ai/services/storage/settings/realism/one_shot_mode.dart';
import 'package:front_porch_ai/services/storage/settings/realism/realism_prefs_snapshot.dart';
import 'package:front_porch_ai/services/storage/settings/realism/time_skip_bridge_setting.dart';

import 'settings_base.dart';

export 'package:front_porch_ai/services/storage/settings/realism/one_shot_mode.dart';
export 'package:front_porch_ai/services/storage/settings/realism/realism_import_stamp.dart';

/// Realism Engine + Needs simulation + related defaults (oneShot, banned
/// phrases, per-char enjoys hygiene is in CharacterCard / group member
/// JSON, not here).
///
/// Lifted Stage 7.
class RealismSettings with SettingsBase, TimeSkipBridgeSetting {
  bool _realismDefault = false;
  bool _nsfwCooldownDefault = false;
  bool _passageOfTimeDefault = true;

  /// Global Needs switch. Defaults TRUE. It decides for a card that says
  /// nothing about Needs (an imported card with no `needs_sim_enabled`),
  /// and AND-gates a card that does: with it off Needs stops regardless of
  /// what a card asks for, and a card's explicit false still wins when it
  /// is on (maintainer ruling, 2026-10-10). Passage
  /// of Time is a different shape — [_passageOfTimeDefault] is the live
  /// clock gate, not a card AND. Added 2026-08-07 — Needs had no global switch at
  /// all, so the Porch Life tab had nothing to show.
  bool _needsSimDefault = true;

  /// Leftover pref. Loaded and written so old PWAs do not 400. It gates
  /// nothing — Passage of Time is the only clock driver.
  bool _standaloneClockEnabled = false;

  /// Pockets & Wardrobe — whether the app tracks what a character is wearing
  /// and carrying (docs/design/pockets-and-preferences.md Part 1).
  ///
  /// Defaults FALSE, and unlike most switches here that is not caution — it is
  /// the ruling. Pockets runs its OWN post-generation eval, so it bills a short
  /// model request on every turn it is on, and the standing rule set by the
  /// standalone story clock applies: a feature that spends a call per turn is
  /// opt-in, because that is the user's money to spend and not ours. The
  /// toggle copy says so in as many words.
  ///
  /// Depends on NOTHING. Not the Realism Engine, not Needs, not the Journal,
  /// not Objectives. Pockets is a record plus an injection plus an applier, and
  /// the settled design ruling is explicit that a dependency here would be a
  /// regression rather than a simplification — the earlier plan had it ride the
  /// needs-impact eval, which is gated behind BOTH Realism and Needs and so
  /// would have done nothing at all on a default install.
  bool _pocketsEnabled = false;

  /// Standing Mood (docs/design/pockets-and-preferences.md is not its home —
  /// see the class doc on MoodBaseline). Lets a character arrive already
  /// tired, hungry or cheered by the weather, so not every shift in their mood
  /// is something the user did.
  ///
  /// Defaults OFF because it changes the felt behaviour of every reply, and
  /// this is the first release of it. It costs NOTHING per turn — pure
  /// derivation from state already computed, no model call — so the default is
  /// about caution, not cost.
  bool _standingMoodEnabled = false;

  /// Whether a character ACTS on their authored intimate preferences — pursues
  /// what they warm to, in their own register, and turns down what they are not.
  ///
  /// HARD DEPENDENCY ON THE REALISM ENGINE, and unusually it is a real one
  /// rather than an inherited gate. The feature is a loop: they ask, the user
  /// answers, and being refused or indulged moves their mood, which is what they
  /// carry into the next reply. The judge that scores that answer IS the
  /// engine (`realism_prompt_builder.preferencesBlock` reaches the relationship
  /// AND emotional-state evals). With the engine off they would ask for things
  /// and nothing would ever come of it — half a feature, and the worse half.
  /// So this is gated on realism at the point of use, not merely chipped as
  /// depending on it.
  ///
  /// Defaults OFF. It changes how a character behaves in intimate scenes quite
  /// noticeably — they initiate, where before they only responded — and that is
  /// the user's call to make, not a default to inherit. Costs NOTHING per turn:
  /// two prompt sentences, no extra model call.
  bool _intimateAgencyEnabled = false;

  /// Whether the periodic Scene Guest cast-detection scan runs — the thing that
  /// notices a named side character in the narration and offers to bring them
  /// in as a guest.
  ///
  /// Defaults TRUE because that is what it has always done; this switch exists
  /// to turn it OFF (maintainer, 2026-08-08: "some users find it annoying").
  /// Being interrupted every few turns by an offer you did not ask for is a
  /// reasonable thing to want to stop, and until now there was no way to.
  ///
  /// There WAS a `ChatService.sceneDetectionEnabled` field standing in for this
  /// — default true, no writer, no UI. It has been deleted rather than wired,
  /// because a second switch for one behaviour is how the two end up
  /// disagreeing. This is now the only one, read at the single gate in
  /// `_maybeRunCastDetection`.
  ///
  /// Scope: the AUTOMATIC scan only. `/scan` still works with this off — the
  /// complaint is unprompted offers, and typing the command is a prompt.
  /// Depends on nothing: detection reads narration text and triggers the
  /// existing mint/enter flow, doing zero Realism or Needs work.
  bool _sceneGuestDetectionEnabled = true;

  /// Slice 6: the ONE global switch for suggested scene transitions — the
  /// clock judge may propose "the scene moved to X" (and, in slice 7, a
  /// named new place to mint) only when this is on. Default OFF: a new
  /// model-driven suggestion earns its place by opt-in, never by
  /// appearing unasked in someone's chat. Passage of Time is the hard
  /// precondition — with the clock off the judge never runs at all.
  bool _sceneSuggestionsEnabled = false;

  /// Global Chaos Mode default. Chaos had NO global switch at all — it was
  /// per-chat only, seeded from the card — so Porch Life could only apologise
  /// for it in a footer instead of offering it.
  ///
  /// Depends on NOTHING, and that is a finding rather than an assumption: the
  /// 2026-08-07 audit (docs/design/feature-independence.md) confirmed Chaos
  /// runs fully with the Realism Engine off. It is filed under realism in the
  /// source tree for location only.
  ///
  /// OR-override, the [_nsfwCooldownDefault] shape rather than the
  /// [_needsSimDefault] AND-gate: a card that asks for Chaos still gets it, and
  /// switching this on makes new chats start with it. Defaults FALSE — Chaos
  /// injects random events into a story and that is nobody's default.
  /// The per-chat sidebar switch still wins for an individual story.
  bool _chaosModeDefault = false;

  /// How often Chance Time pops on its own (Porch Life, under Chaos Mode).
  ChaosFrequency _chaosFrequency = ChaosFrequency.normal;

  /// Hand-offs between characters in a group (Pockets). Off by default and
  /// gated on Pockets, because it asks the model for something strictly harder
  /// than the rest of the record: not just WHAT changed but WHO now has it. A
  /// model that names the wrong person puts an item in the wrong character's
  /// pocket — invisible and wrong, rather than merely missing — so this is the
  /// one part of Pockets that genuinely wants a frontier model.
  bool _pocketTransfersEnabled = false;

  /// Global Objectives switch (v45). Objectives are the character's short-lived
  /// quests; they depend on NOTHING but their own eval cost — not the Realism
  /// Engine, not the Journal — and until now they had no off switch at all,
  /// despite firing a completion check on a recurring cadence forever.
  /// Defaults TRUE and AND-gates the card/session setting (the [needsSimDefault]
  /// shape, not the NSFW OR-override), so nothing changes until someone turns
  /// it off deliberately. Ambitions hang off this, since quest completion is
  /// the only thing that moves ambition progress.
  bool _objectivesEnabled = true;

  /// Whether 18+ themes are on for this install. Gates the Porch Life
  /// "After Dark" group (approved sketch: that group is "shown only when 18+
  /// themes are enabled"), and will gate the intimate-preferences section in
  /// the character editors.
  ///
  /// Defaults FALSE — the whole point is that adult switches are not shown to
  /// someone who has not asked for them. But it SEEDS from
  /// [_nsfwCooldownDefault] on first read: anyone already running Afterglow has
  /// plainly opted into 18+ content, and hiding their existing switch behind a
  /// flag they were never shown would strand a setting they deliberately
  /// turned on. The master switch lives in Settings → General (next to the
  /// Porch Life pointer) so it is always reachable even when the group is
  /// hidden.
  /// Null = never explicitly chosen, so the seed below applies.
  bool? _adultThemesExplicit;
  OneShotMode _oneShotMode = OneShotMode.auto;
  bool _preferTextEvals = false;
  bool _weatherEnabled = true;
  bool _weatherFahrenheit = false;
  bool _absenceBannerEnabled = true;

  /// Chat layout: the user's bubble mirrored to the right (avatar right,
  /// buttons left), the look before user and character rows shared one
  /// layout. Off = both on the left.
  bool _userMessagesOnRight = false;
  bool _absenceAckEnabled = false;
  int _absenceThresholdHours = 24;
  bool _dreamsEnabled = true;
  bool _ambitionsEnabled = true;
  bool _plannerEnabled = false;
  bool _promiseLedgerEnabled = true;
  List<String> _bannedPhrases = [];

  bool get realismDefault => _realismDefault;
  bool get nsfwCooldownDefault => _nsfwCooldownDefault;
  bool get passageOfTimeDefault => _passageOfTimeDefault;
  bool get needsSimDefault => _needsSimDefault;

  /// Leftover pref for old PWAs. Ignored by the story clock.
  bool get standaloneClockEnabled => _standaloneClockEnabled;

  /// See [_objectivesEnabled]. The switch Objectives never had.
  bool get objectivesEnabled => _objectivesEnabled;

  /// See [_pocketsEnabled]. Costs one short model call per turn while on.
  bool get pocketsEnabled => _pocketsEnabled;

  /// See [_standingMoodEnabled]. Free: no model call, ever.
  bool get standingMoodEnabled => _standingMoodEnabled;

  /// See [_intimateAgencyEnabled]. Free, and hard-gated on the engine at the
  /// point of use — the switch alone is not enough to turn it on.
  bool get intimateAgencyEnabled => _intimateAgencyEnabled;

  /// See [_chaosModeDefault]. Depends on nothing.
  bool get chaosModeDefault => _chaosModeDefault;
  ChaosFrequency get chaosFrequency => _chaosFrequency;

  /// See [_sceneGuestDetectionEnabled]. Depends on nothing; default ON.
  bool get sceneGuestDetectionEnabled => _sceneGuestDetectionEnabled;

  /// See [_sceneSuggestionsEnabled]. Rides the Passage of Time clock;
  /// default OFF.
  bool get sceneSuggestionsEnabled => _sceneSuggestionsEnabled;

  /// See [_pocketTransfersEnabled]. Costs nothing extra — it rides the Pockets
  /// pass that is already running.
  bool get pocketTransfersEnabled => _pocketTransfersEnabled;

  /// See [_adultThemesExplicit]. The seed is evaluated on READ, not snapshotted
  /// at load: until the user makes an explicit choice, "do you want adult
  /// switches shown" simply tracks "are you running an adult feature", which
  /// stays true even if Afterglow is enabled later in the same session.
  bool get adultThemesEnabled => _adultThemesExplicit ?? _nsfwCooldownDefault;

  /// Whether Porch Life allows Afterglow (arousal, the Lust bar, climax,
  /// refractory): its switch, and only while 18+ themes are on. Within it each
  /// chat's own switch decides, and a card's switch seeds new chats.
  bool get afterglowEnabled => adultThemesEnabled && _nsfwCooldownDefault;

  /// One-Shot Eval mode. [OneShotMode.auto] (the default) fuses the judges
  /// into one call on remote backends that have already proven native tool
  /// calls, and stays on the multi-call path everywhere else — the resolution
  /// lives in `resolveOneShotMode` (pass_support.dart) because it needs the
  /// backend probe, which storage deliberately knows nothing about.
  OneShotMode get oneShotMode => _oneShotMode;

  /// Prefer the streaming JSON/XML floor even when the model speaks tools.
  /// Default false: tools stay preferred when supported. Persist this name;
  /// the Porch Life switch ON means use tools (`!preferTextEvals`).
  bool get preferTextEvals => _preferTextEvals;

  /// Legacy bool surface over [oneShotMode], kept because callers and the
  /// persistence test predate the tri-state. True means explicitly ON.
  bool get realismOneShotEval => _oneShotMode == OneShotMode.on;

  /// Living Time story weather (living-time-features.md §3). Effective
  /// whenever the story clock is actually moving (Passage of Time on).
  /// ChatService gates that (`_clockRunning`); weather
  /// itself is deterministic math and needs no eval of its own.
  bool get weatherEnabled => _weatherEnabled;

  /// Display temperatures in °F instead of °C (§3 v3). Display-only: the
  /// canonical unit is °C everywhere internally, and the generation prompt
  /// carries no numbers at all (words-only contract).
  bool get weatherFahrenheit => _weatherFahrenheit;

  /// Living Time absence awareness (living-time-features.md §2). Banner is
  /// app-voice and default ON; the in-character acknowledgment is default
  /// OFF by explicit maintainer decision (can read as creepy). Threshold in
  /// hours before either fires.
  bool get absenceBannerEnabled => _absenceBannerEnabled;
  bool get userMessagesOnRight => _userMessagesOnRight;
  bool get absenceAckEnabled => _absenceAckEnabled;
  int get absenceThresholdHours => _absenceThresholdHours;

  /// Living Time dreams (living-time-features.md §1). Effective when the
  /// story clock is moving (Passage of Time on) and the Journal is on —
  /// ChatService gates. Dreams fire on day crossings, so what they actually
  /// need is a clock that crosses days, not the engine per se.
  bool get dreamsEnabled => _dreamsEnabled;

  /// Long-term character goals. Independent of the Realism Engine on purpose:
  /// the goals themselves are authored on the character card, so they are never
  /// stale and cost nothing extra to inject. Only their PROGRESS annotation
  /// comes from the engine, and a progress figure that stops moving is far less
  /// misleading than a stale fact would be.
  bool get ambitionsEnabled => _ambitionsEnabled;

  /// Planner feature. Default OFF. Not Plans/Wings it.
  bool get plannerEnabled => _plannerEnabled;

  /// The promise/debt ledger. Also independent of Realism, but NOT free and NOT
  /// unconditional: detection is one extra model call per reply, and storage is
  /// the Journal (one journal card per commitment), so it does nothing with the
  /// Journal switched off. Both facts are surfaced in the settings copy —
  /// spending a user's tokens without telling them is not acceptable.
  bool get promiseLedgerEnabled => _promiseLedgerEnabled;
  List<String> get bannedPhrases => List.unmodifiable(_bannedPhrases);

  void load() {
    final s = RealismPrefsSnapshot.read(prefs, k);
    _realismDefault = s.realismDefault;
    _nsfwCooldownDefault = s.nsfwCooldownDefault;
    _passageOfTimeDefault = s.passageOfTimeDefault;
    _needsSimDefault = s.needsSimDefault;
    _standaloneClockEnabled = s.standaloneClockEnabled;
    _objectivesEnabled = s.objectivesEnabled;
    _pocketsEnabled = s.pocketsEnabled;
    _standingMoodEnabled = s.standingMoodEnabled;
    _intimateAgencyEnabled = s.intimateAgencyEnabled;
    _chaosModeDefault = s.chaosModeDefault;
    _chaosFrequency = s.chaosFrequency;
    _sceneGuestDetectionEnabled = s.sceneGuestDetectionEnabled;
    _sceneSuggestionsEnabled = s.sceneSuggestionsEnabled;
    _pocketTransfersEnabled = s.pocketTransfersEnabled;
    _adultThemesExplicit = s.adultThemesExplicit;
    _oneShotMode = s.oneShotMode;
    _preferTextEvals = s.preferTextEvals;
    _weatherEnabled = s.weatherEnabled;
    _weatherFahrenheit = s.weatherFahrenheit;
    _absenceBannerEnabled = s.absenceBannerEnabled;
    _userMessagesOnRight = s.userMessagesOnRight;
    _absenceAckEnabled = s.absenceAckEnabled;
    _absenceThresholdHours = s.absenceThresholdHours;
    _dreamsEnabled = s.dreamsEnabled;
    _ambitionsEnabled = s.ambitionsEnabled;
    _plannerEnabled = s.plannerEnabled;
    _promiseLedgerEnabled = s.promiseLedgerEnabled;
    final banned = s.bannedPhrases;
    if (banned != null) _bannedPhrases = banned;
  }

  Future<void> setAmbitionsEnabled(bool value) {
    _ambitionsEnabled = value;
    return _saveBool('ambitions_enabled', value);
  }

  Future<void> setPlannerEnabled(bool value) {
    _plannerEnabled = value;
    return _saveBool('planner_enabled', value);
  }

  Future<void> setPromiseLedgerEnabled(bool value) {
    _promiseLedgerEnabled = value;
    return _saveBool('promise_ledger_enabled', value);
  }

  Future<void> setWeatherEnabled(bool value) {
    _weatherEnabled = value;
    return _saveBool('weather_enabled', value);
  }

  Future<void> setWeatherFahrenheit(bool value) {
    _weatherFahrenheit = value;
    return _saveBool('weather_fahrenheit', value);
  }

  Future<void> setUserMessagesOnRight(bool value) {
    _userMessagesOnRight = value;
    return _saveBool('user_messages_on_right', value);
  }

  Future<void> setAbsenceBannerEnabled(bool value) {
    _absenceBannerEnabled = value;
    return _saveBool('absence_banner_enabled', value);
  }

  Future<void> setAbsenceAckEnabled(bool value) {
    _absenceAckEnabled = value;
    return _saveBool('absence_ack_enabled', value);
  }

  Future<void> setAbsenceThresholdHours(int value) async {
    _absenceThresholdHours = value;
    await prefs?.setInt(k('absence_threshold_hours'), value);
    notify();
  }

  Future<void> setDreamsEnabled(bool value) {
    _dreamsEnabled = value;
    return _saveBool('dreams_enabled', value);
  }

  Future<void> setOneShotMode(OneShotMode value) async {
    _oneShotMode = value;
    await prefs?.setString(k('realism_one_shot_mode'), value.name);
    notify();
  }

  Future<void> setPreferTextEvals(bool value) {
    _preferTextEvals = value;
    return _saveBool('prefer_text_evals', value);
  }

  /// Legacy bool surface over [setOneShotMode]: an explicit toggle is an
  /// explicit choice, so it maps to ON/OFF — never Auto. Keeps writing the
  /// old bool key too (the persistence test pins it, and a downgrade then
  /// reads a truthful value).
  Future<void> setRealismOneShotEval(bool value) async {
    await prefs?.setBool(k('realism_one_shot_eval'), value);
    await setOneShotMode(value ? OneShotMode.on : OneShotMode.off);
  }

  Future<void> setRealismDefault(bool value) {
    _realismDefault = value;
    return _saveBool('realism_default', value);
  }

  Future<void> setNsfwCooldownDefault(bool value) {
    _nsfwCooldownDefault = value;
    return _saveBool('nsfw_cooldown_default', value);
  }

  Future<void> setNeedsSimDefault(bool value) {
    _needsSimDefault = value;
    return _saveBool('needs_sim_default', value);
  }

  Future<void> setPassageOfTimeDefault(bool value) {
    _passageOfTimeDefault = value;
    return _saveBool('passage_of_time_default', value);
  }

  Future<void> setStandaloneClockEnabled(bool value) {
    _standaloneClockEnabled = value;
    return _saveBool('standalone_clock_enabled', value);
  }

  Future<void> setAdultThemesEnabled(bool value) {
    _adultThemesExplicit = value;
    return _saveBool('adult_themes_enabled', value);
  }

  Future<void> setObjectivesEnabled(bool value) {
    _objectivesEnabled = value;
    return _saveBool('objectives_enabled', value);
  }

  Future<void> setPocketsEnabled(bool value) {
    _pocketsEnabled = value;
    return _saveBool('pockets_enabled', value);
  }

  Future<void> setStandingMoodEnabled(bool value) {
    _standingMoodEnabled = value;
    return _saveBool('standing_mood_enabled', value);
  }

  Future<void> setIntimateAgencyEnabled(bool value) {
    _intimateAgencyEnabled = value;
    return _saveBool('intimate_agency_enabled', value);
  }

  Future<void> setChaosModeDefault(bool value) {
    _chaosModeDefault = value;
    return _saveBool('chaos_mode_default', value);
  }

  Future<void> setChaosFrequency(ChaosFrequency value) async {
    _chaosFrequency = value;
    await prefs?.setString(k('chaos_frequency'), value.name);
    notify();
  }

  Future<void> setSceneGuestDetectionEnabled(bool value) {
    _sceneGuestDetectionEnabled = value;
    return _saveBool('scene_guest_detection_enabled', value);
  }

  Future<void> setSceneSuggestionsEnabled(bool value) {
    _sceneSuggestionsEnabled = value;
    return _saveBool('scene_suggestions_enabled', value);
  }

  Future<void> setPocketTransfersEnabled(bool value) {
    _pocketTransfersEnabled = value;
    return _saveBool('pocket_transfers_enabled', value);
  }

  Future<void> setBannedPhrases(List<String> value) async {
    _bannedPhrases = value.where((s) => s.isNotEmpty).toList();
    await prefs?.setString(k('banned_phrases'), jsonEncode(_bannedPhrases));
    notify();
  }

  Future<void> _saveBool(String key, bool value) async {
    await prefs?.setBool(k(key), value);
    notify();
  }
}
