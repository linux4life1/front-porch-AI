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
import 'settings_base.dart';

/// How the pre-generation realism judges are fused (eval review Tier-1 §3.4,
/// maintainer-approved 2026-08-10). [auto] — the default — uses the fused
/// one-shot call on remote backends that have already proven native tool
/// calls (exactly the class of model the combined prompt is easy for) and the
/// multi-call path everywhere else, including every local backend. [on]/[off]
/// are the explicit choices the old bool expressed; the user always wins in
/// both directions.
enum OneShotMode { auto, on, off }

/// Realism Engine + Needs simulation + related defaults (oneShot, banned
/// phrases, per-char enjoys hygiene is in CharacterCard / group member
/// JSON, not here).
///
/// Lifted Stage 7.
class RealismSettings with SettingsBase {
  bool _realismDefault = false;
  bool _nsfwCooldownDefault = false;
  bool _passageOfTimeDefault = true;

  /// Global Needs switch. Defaults TRUE and AND-gates the card's own setting
  /// (same shape as [_passageOfTimeDefault], not the NSFW OR-override): with
  /// it on nothing changes, with it off Needs stops for new chats regardless
  /// of what a card asks for. Added 2026-08-07 — Needs had no global switch at
  /// all, so the Porch Life tab had nothing to show.
  bool _needsSimDefault = true;

  /// Run the story clock on its own eval when the Realism Engine is OFF
  /// (docs/design/feature-independence.md, "Passage of Time" — decoupled
  /// 2026-08-06, superseding the 2026-08-02 ruling).
  ///
  /// Defaults FALSE on purpose, and the default is the whole point. Passage of
  /// Time already defaults TRUE, but with the engine off that flag was inert —
  /// nobody chose it in a world where it did anything. Treating it as consent
  /// would hand a per-turn model call to every existing realism-off user
  /// without asking, which is exactly the cost the maintainer declined
  /// (2026-08-06). So standalone advancement needs its own deliberate yes.
  ///
  /// Read only when the engine is off: with realism ON the fused scene-time
  /// eval already drives the clock for free and this flag is ignored.
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
  /// tired, hungry or cheered by the weather, so not every shift in her mood
  /// is something the user did.
  ///
  /// Defaults OFF because it changes the felt behaviour of every reply, and
  /// this is the first release of it. It costs NOTHING per turn — pure
  /// derivation from state already computed, no model call — so the default is
  /// about caution, not cost.
  bool _standingMoodEnabled = false;

  /// Whether a character ACTS on her authored intimate preferences — pursues
  /// what she warms to, in her own register, and turns down what she is not.
  ///
  /// HARD DEPENDENCY ON THE REALISM ENGINE, and unusually it is a real one
  /// rather than an inherited gate. The feature is a loop: she asks, the user
  /// answers, and being refused or indulged moves her mood, which is what she
  /// carries into the next reply. The judge that scores that answer IS the
  /// engine (`realism_prompt_builder.preferencesBlock` reaches the relationship
  /// AND emotional-state evals). With the engine off she would ask for things
  /// and nothing would ever come of it — half a feature, and the worse half.
  /// So this is gated on realism at the point of use, not merely chipped as
  /// depending on it.
  ///
  /// Defaults OFF. It changes how a character behaves in intimate scenes quite
  /// noticeably — she initiates, where before she only responded — and that is
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

  /// See [_standaloneClockEnabled]. Costs one model call per turn while it is
  /// doing anything, which is why it is opt-in and says so in the UI.
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

  /// See [_sceneGuestDetectionEnabled]. Depends on nothing; default ON.
  bool get sceneGuestDetectionEnabled => _sceneGuestDetectionEnabled;

  /// See [_pocketTransfersEnabled]. Costs nothing extra — it rides the Pockets
  /// pass that is already running.
  bool get pocketTransfersEnabled => _pocketTransfersEnabled;

  /// See [_adultThemesExplicit]. The seed is evaluated on READ, not snapshotted
  /// at load: until the user makes an explicit choice, "do you want adult
  /// switches shown" simply tracks "are you running an adult feature", which
  /// stays true even if Afterglow is enabled later in the same session.
  bool get adultThemesEnabled => _adultThemesExplicit ?? _nsfwCooldownDefault;

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
  /// whenever the story clock is actually moving — under the engine, or on
  /// the standalone clock. ChatService gates that (`_clockRunning`); weather
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
  bool get absenceAckEnabled => _absenceAckEnabled;
  int get absenceThresholdHours => _absenceThresholdHours;

  /// Living Time dreams (living-time-features.md §1). Effective when the
  /// story clock is moving (engine or standalone) and the Journal is on —
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
    _realismDefault = prefs?.getBool(k('realism_default')) ?? false;
    _nsfwCooldownDefault = prefs?.getBool(k('nsfw_cooldown_default')) ?? false;
    _passageOfTimeDefault =
        prefs?.getBool(k('passage_of_time_default')) ?? true;
    _needsSimDefault = prefs?.getBool(k('needs_sim_default')) ?? true;
    _standaloneClockEnabled =
        prefs?.getBool(k('standalone_clock_enabled')) ?? false;
    _objectivesEnabled = prefs?.getBool(k('objectives_enabled')) ?? true;
    _pocketsEnabled = prefs?.getBool(k('pockets_enabled')) ?? false;
    _standingMoodEnabled = prefs?.getBool(k('standing_mood_enabled')) ?? false;
    _intimateAgencyEnabled =
        prefs?.getBool(k('intimate_agency_enabled')) ?? false;
    _chaosModeDefault = prefs?.getBool(k('chaos_mode_default')) ?? false;
    _sceneGuestDetectionEnabled =
        prefs?.getBool(k('scene_guest_detection_enabled')) ?? true;
    _pocketTransfersEnabled =
        prefs?.getBool(k('pocket_transfers_enabled')) ?? false;
    _adultThemesExplicit = prefs?.getBool(k('adult_themes_enabled'));
    _oneShotMode = switch (prefs?.getString(k('realism_one_shot_mode'))) {
      'on' => OneShotMode.on,
      'off' => OneShotMode.off,
      'auto' => OneShotMode.auto,
      // Pre-tri-state install: an explicit true was a deliberate opt-in and
      // stays ON. false was the old default and indistinguishable from
      // "never touched", so it becomes Auto — the new default, which only
      // ever differs from off on a remote backend that has proven tools.
      _ =>
        (prefs?.getBool(k('realism_one_shot_eval')) ?? false)
            ? OneShotMode.on
            : OneShotMode.auto,
    };
    _preferTextEvals = prefs?.getBool(k('prefer_text_evals')) ?? false;
    _weatherEnabled = prefs?.getBool(k('weather_enabled')) ?? true;
    _weatherFahrenheit = prefs?.getBool(k('weather_fahrenheit')) ?? false;
    _absenceBannerEnabled = prefs?.getBool(k('absence_banner_enabled')) ?? true;
    _absenceAckEnabled = prefs?.getBool(k('absence_ack_enabled')) ?? false;
    _absenceThresholdHours = prefs?.getInt(k('absence_threshold_hours')) ?? 24;
    _dreamsEnabled = prefs?.getBool(k('dreams_enabled')) ?? true;
    _ambitionsEnabled = prefs?.getBool(k('ambitions_enabled')) ?? true;
    _plannerEnabled = prefs?.getBool(k('planner_enabled')) ?? false;
    _promiseLedgerEnabled = prefs?.getBool(k('promise_ledger_enabled')) ?? true;

    final bannedJson = prefs?.getString(k('banned_phrases'));
    if (bannedJson != null) {
      try {
        _bannedPhrases = List<String>.from(jsonDecode(bannedJson) as List);
      } catch (_) {
        _bannedPhrases = [];
      }
    }
  }

  Future<void> setAmbitionsEnabled(bool value) async {
    _ambitionsEnabled = value;
    await prefs?.setBool(k('ambitions_enabled'), value);
    notify();
  }

  Future<void> setPlannerEnabled(bool value) async {
    _plannerEnabled = value;
    await prefs?.setBool(k('planner_enabled'), value);
    notify();
  }

  Future<void> setPromiseLedgerEnabled(bool value) async {
    _promiseLedgerEnabled = value;
    await prefs?.setBool(k('promise_ledger_enabled'), value);
    notify();
  }

  Future<void> setWeatherEnabled(bool value) async {
    _weatherEnabled = value;
    await prefs?.setBool(k('weather_enabled'), value);
    notify();
  }

  Future<void> setWeatherFahrenheit(bool value) async {
    _weatherFahrenheit = value;
    await prefs?.setBool(k('weather_fahrenheit'), value);
    notify();
  }

  Future<void> setAbsenceBannerEnabled(bool value) async {
    _absenceBannerEnabled = value;
    await prefs?.setBool(k('absence_banner_enabled'), value);
    notify();
  }

  Future<void> setAbsenceAckEnabled(bool value) async {
    _absenceAckEnabled = value;
    await prefs?.setBool(k('absence_ack_enabled'), value);
    notify();
  }

  Future<void> setAbsenceThresholdHours(int value) async {
    _absenceThresholdHours = value;
    await prefs?.setInt(k('absence_threshold_hours'), value);
    notify();
  }

  Future<void> setDreamsEnabled(bool value) async {
    _dreamsEnabled = value;
    await prefs?.setBool(k('dreams_enabled'), value);
    notify();
  }

  Future<void> setOneShotMode(OneShotMode value) async {
    _oneShotMode = value;
    await prefs?.setString(k('realism_one_shot_mode'), value.name);
    notify();
  }

  Future<void> setPreferTextEvals(bool value) async {
    _preferTextEvals = value;
    await prefs?.setBool(k('prefer_text_evals'), value);
    notify();
  }

  /// Legacy bool surface over [setOneShotMode]: an explicit toggle is an
  /// explicit choice, so it maps to ON/OFF — never Auto. Keeps writing the
  /// old bool key too (the persistence test pins it, and a downgrade then
  /// reads a truthful value).
  Future<void> setRealismOneShotEval(bool value) async {
    await prefs?.setBool(k('realism_one_shot_eval'), value);
    await setOneShotMode(value ? OneShotMode.on : OneShotMode.off);
  }

  Future<void> setRealismDefault(bool value) async {
    _realismDefault = value;
    await prefs?.setBool(k('realism_default'), value);
    notify();
  }

  Future<void> setNsfwCooldownDefault(bool value) async {
    _nsfwCooldownDefault = value;
    await prefs?.setBool(k('nsfw_cooldown_default'), value);
    notify();
  }

  Future<void> setNeedsSimDefault(bool value) async {
    _needsSimDefault = value;
    await prefs?.setBool(k('needs_sim_default'), value);
    notify();
  }

  Future<void> setPassageOfTimeDefault(bool value) async {
    _passageOfTimeDefault = value;
    await prefs?.setBool(k('passage_of_time_default'), value);
    notify();
  }

  Future<void> setStandaloneClockEnabled(bool value) async {
    _standaloneClockEnabled = value;
    await prefs?.setBool(k('standalone_clock_enabled'), value);
    notify();
  }

  Future<void> setAdultThemesEnabled(bool value) async {
    _adultThemesExplicit = value;
    await prefs?.setBool(k('adult_themes_enabled'), value);
    notify();
  }

  Future<void> setObjectivesEnabled(bool value) async {
    _objectivesEnabled = value;
    await prefs?.setBool(k('objectives_enabled'), value);
    notify();
  }

  Future<void> setPocketsEnabled(bool value) async {
    _pocketsEnabled = value;
    await prefs?.setBool(k('pockets_enabled'), value);
    notify();
  }

  Future<void> setStandingMoodEnabled(bool value) async {
    _standingMoodEnabled = value;
    await prefs?.setBool(k('standing_mood_enabled'), value);
    notify();
  }

  Future<void> setIntimateAgencyEnabled(bool value) async {
    _intimateAgencyEnabled = value;
    await prefs?.setBool(k('intimate_agency_enabled'), value);
    notify();
  }

  Future<void> setChaosModeDefault(bool value) async {
    _chaosModeDefault = value;
    await prefs?.setBool(k('chaos_mode_default'), value);
    notify();
  }

  Future<void> setSceneGuestDetectionEnabled(bool value) async {
    _sceneGuestDetectionEnabled = value;
    await prefs?.setBool(k('scene_guest_detection_enabled'), value);
    notify();
  }

  Future<void> setPocketTransfersEnabled(bool value) async {
    _pocketTransfersEnabled = value;
    await prefs?.setBool(k('pocket_transfers_enabled'), value);
    notify();
  }

  Future<void> setBannedPhrases(List<String> value) async {
    _bannedPhrases = value.where((s) => s.isNotEmpty).toList();
    await prefs?.setString(k('banned_phrases'), jsonEncode(_bannedPhrases));
    notify();
  }
}
