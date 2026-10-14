// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_gen/gen_paused_run.dart';
import 'package:front_porch_ai/services/character_gen/gen_run_state.dart';
import 'package:front_porch_ai/services/character_gen/gen_stages.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';

/// A rewritten profile and the facts read again from it. Also the relay's
/// JSON shape.
class ProfileRewrite {
  const ProfileRewrite({
    required this.description,
    required this.personality,
    required this.scenario,
    this.facts,
  });

  final String description;
  final String personality;
  final String scenario;

  /// Null when the facts re-read gave nothing; the caller keeps its facts.
  final IdentityFacts? facts;

  Map<String, dynamic> toJson() => {
    'description': description,
    'personality': personality,
    'scenario': scenario,
    'facts': facts?.toJson(),
  };
}

/// The Profile step's rewrites: the profile from the same interview with
/// the author's steer, and the facts re-read from the profile as it is now.
/// Each call is its own run from the paused data; nothing is written to the
/// paused run itself.
class GenProfileWriter {
  GenProfileWriter(this._s);

  final GenStages _s;
  GenRunState get _state => _s.state;

  /// Rewrite description, personality and scenario from [paused]'s
  /// interview and the three texts as the author has them now, steered by
  /// [direction]. Only the interview rewrite runs again. A scenario the user
  /// typed, and the Automated mode's description, come back as given. The
  /// facts are then re-read from the new profile.
  ///
  /// Null when stopped, or when the model changed nothing.
  Future<ProfileRewrite?> rewriteProfile({
    required GenPausedRun paused,
    required String description,
    required String personality,
    required String scenario,
    String direction = '',
    bool abortInFlight = true,
    void Function(String accumulated)? onProgress,
  }) async {
    final inputs = paused.inputs;
    final epoch = _begin(paused, abortInFlight);
    final work = CharacterCard(
      name: inputs.name,
      description: description,
      personality: personality,
      scenario: scenario,
    );
    await _s.interview.enrichCardFromInterview(
      card: work,
      name: inputs.name,
      interviewTranscript: paused.interviewTranscript,
      preserveUserScenario: inputs.userScenario,
      direction: direction,
      onProgress: onProgress,
    );
    if (_state.isStale(epoch)) return null;
    if (inputs.descriptionOverride != null) work.description = description;
    if (work.description == description &&
        work.personality == personality &&
        work.scenario == scenario) {
      return null;
    }
    final facts = await _readFacts(paused, work);
    if (_state.isStale(epoch)) return null;
    return ProfileRewrite(
      description: work.description,
      personality: work.personality,
      scenario: work.scenario,
      facts: facts,
    );
  }

  /// Read the identity facts again from the profile as the author has it
  /// now. Null when stopped or when the model answered nothing usable.
  Future<IdentityFacts?> rereadIdentityFacts({
    required GenPausedRun paused,
    required String description,
    required String personality,
    required String scenario,
    bool abortInFlight = true,
  }) async {
    final epoch = _begin(paused, abortInFlight);
    final facts = await _readFacts(
      paused,
      CharacterCard(
        name: paused.inputs.name,
        description: description,
        personality: personality,
        scenario: scenario,
      ),
    );
    return _state.isStale(epoch) ? null : facts;
  }

  Future<IdentityFacts?> _readFacts(GenPausedRun paused, CharacterCard card) {
    final inputs = paused.inputs;
    return _s.identity.read(
      name: inputs.name,
      age: inputs.age,
      sex: inputs.sex,
      relationship: inputs.relationship,
      description: card.description,
      personality: card.personality,
      scenario: card.scenario,
      interviewTranscript: paused.interviewTranscript,
      nsfwEnabled: inputs.nsfwEnabled,
    );
  }

  /// The paused run's voice and switches, and a fresh epoch.
  int _begin(GenPausedRun paused, bool abortInFlight) {
    final inputs = paused.inputs;
    _state.narrativeVoice = NarrativeVoice.parse(
      perspective: inputs.narrativePerspective,
      tense: inputs.narrativeTense,
    );
    _state.narrativeSex = inputs.sex;
    return _state.beginRun(
      abortInFlight: abortInFlight,
      reasoningEnabled: inputs.reasoningEnabled,
      includeDynamicMacros: inputs.includeDynamicMacros,
    );
  }
}
