// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_gen/gen_card_completion.dart';
import 'package:front_porch_ai/services/character_gen/gen_parsing.dart';
import 'package:front_porch_ai/services/character_gen/gen_paused_run.dart';
import 'package:front_porch_ai/services/character_gen/gen_prompts.dart';
import 'package:front_porch_ai/services/character_gen/gen_run_inputs.dart';
import 'package:front_porch_ai/services/character_gen/gen_run_state.dart';
import 'package:front_porch_ai/services/character_gen/gen_stages.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The AI Create pipeline in two phases. Phase A, the profile: base card,
/// interview, the interview rewrite, the identity facts. Phase B
/// ([GenCardCompletion]): dialogue, lorebook, greetings, the opening scene,
/// the image prompt and the stamps.
class GenCharacterGenerator {
  GenCharacterGenerator(this._s) : _completion = GenCardCompletion(_s);

  final GenStages _s;
  final GenCardCompletion _completion;
  GenRunState get _state => _s.state;

  /// Both phases back to back in one run, on one card: what
  /// `generateCharacter` has always done (Scene Guest, the one-shot relay).
  Future<CharacterCard?> run(
    GenRunInputs inputs, {
    required bool abortInFlight,
    required void Function(String accumulated)? onProgress,
    required void Function(String error)? onError,
    required void Function(String status)? onStatus,
  }) async {
    final started = await _profile(
      inputs,
      abortInFlight: abortInFlight,
      onProgress: onProgress,
      onError: onError,
      onStatus: onStatus,
    );
    if (started == null) return null;
    final (paused, epoch) = started;
    return _completion.finish(
      paused: paused,
      card: paused.card,
      epoch: epoch,
      onProgress: onProgress,
      onStatus: onStatus,
    );
  }

  /// Phase A alone: stops once the profile and its facts are written.
  /// Null when stopped or when no card could be read.
  Future<GenPausedRun?> generateProfile(
    GenRunInputs inputs, {
    required bool abortInFlight,
    required void Function(String accumulated)? onProgress,
    required void Function(String error)? onError,
    required void Function(String status)? onStatus,
  }) async {
    final started = await _profile(
      inputs,
      abortInFlight: abortInFlight,
      onProgress: onProgress,
      onError: onError,
      onStatus: onStatus,
    );
    if (started == null) return null;
    onStatus?.call('Profile ready');
    return started.$1;
  }

  /// Phase B of [paused] as its own run (see [GenCardCompletion.complete]).
  Future<CharacterCard?> complete({
    required GenPausedRun paused,
    required bool abortInFlight,
    required void Function(String accumulated)? onProgress,
    required void Function(String error)? onError,
    required void Function(String status)? onStatus,
  }) => _completion.complete(
    paused: paused,
    abortInFlight: abortInFlight,
    onProgress: onProgress,
    onError: onError,
    onStatus: onStatus,
  );

  /// Phase A, returning the pause and the run's epoch so [run] can go on
  /// in the same run.
  Future<(GenPausedRun, int)?> _profile(
    GenRunInputs inputs, {
    required bool abortInFlight,
    required void Function(String accumulated)? onProgress,
    required void Function(String error)? onError,
    required void Function(String status)? onStatus,
  }) async {
    final name = inputs.name;
    final concept = inputs.concept;
    final personalityKeywords = inputs.personalityKeywords;
    final apiSystemPrompt = inputs.apiSystemPrompt;
    final age = inputs.age;
    final sex = inputs.sex;
    final relationship = inputs.relationship;
    final backstory = inputs.backstory;
    final scenario = inputs.scenario;
    final worldLore = inputs.worldLore;
    final nsfwEnabled = inputs.nsfwEnabled;
    final reasoningEnabled = inputs.reasoningEnabled;

    // Voice must be set BEFORE the base-card prompt so description /
    // personality pick up tense and third-person pronouns.
    _state.narrativeVoice = NarrativeVoice.parse(
      perspective: inputs.narrativePerspective,
      tense: inputs.narrativeTense,
    );
    _state.narrativeSex = sex;

    // ── Step 1: Generate base card ──────────────────────────────
    onStatus?.call('Generating character profile...');
    final basePrompt = buildBaseCardPrompt(
      voice: _state.narrativeVoice,
      narrativeSex: _state.narrativeSex,
      name: name,
      concept: concept,
      personalityKeywords: personalityKeywords,
      generateLorebook: inputs.generateLorebook,
      loreCategories: inputs.loreCategories,
      loreDepth: inputs.loreDepth,
      apiSystemPrompt: apiSystemPrompt,
      age: age,
      sex: sex,
      relationship: relationship,
      descriptionDetail: inputs.descriptionDetail,
      generateDescription: inputs.generateDescription,
      scenario: scenario,
      worldLore: worldLore,
    );

    debugPrint(
      'CharacterGen: Starting generation for "$name" (reasoning: $reasoningEnabled)',
    );
    // Clear stuck state from a previous interactive run. abortGeneration is
    // SERVICE-WIDE: it closes whatever request the shared backend has in
    // flight, so background callers (the Scene Guest mint, which runs inside
    // a live chat where journal/growth/realism evals are expected to be
    // mid-request) pass abortInFlight: false to avoid killing them.
    // abortInFlight also gates the per-step server-side idle handling in
    // GenLlmCaller.call (force-abort vs wait) for the same reason.
    final int currentEpoch = _state.beginRun(
      abortInFlight: abortInFlight,
      reasoningEnabled: reasoningEnabled,
      includeDynamicMacros: inputs.includeDynamicMacros,
    );

    int attempts = 0;
    CharacterCard? card;

    while (attempts < 3 && card == null) {
      if (_state.isStale(currentEpoch)) return null;
      if (attempts > 0) {
        onStatus?.call('JSON Parse failed. Retrying generation...');
        debugPrint(
          'CharacterGen: Retrying generation (Attempt ${attempts + 1})',
        );
      }

      final baseOutput = await _s.llm.call(
        basePrompt,
        isJsonMode: true,
        onProgress: attempts == 0 ? onProgress : null,
      );
      _state.lastRawOutput = baseOutput; // Store for image prompt extraction

      if (baseOutput == null) {
        // A refusal (auth, billing) answers the same every time: stop here
        // and say what the backend said.
        if (_state.refused) {
          onError?.call('The model refused the request: ${_state.lastFailure}');
          return null;
        }
        attempts++;
        continue;
      }

      // Reject suspiciously short output (model warm-up / placeholder)
      final strippedLen = stripThinkBlocks(baseOutput).length;
      if (strippedLen < 100) {
        debugPrint(
          'CharacterGen: Output too short ($strippedLen chars) — likely placeholder, retrying',
        );
        attempts++;
        continue;
      }

      final cleaned = JsonSanitizer.sanitize(baseOutput);
      debugPrint('CharacterGen: Base output cleaned (${cleaned.length} chars)');

      // Detect literal "..." placeholder values (some models output skeleton JSON)
      if (cleaned.contains('"..."') || cleaned.contains('"…"')) {
        debugPrint(
          'CharacterGen: Detected placeholder "..." values — retrying',
        );
        attempts++;
        continue;
      }

      card = parseGeneratedCardJson(cleaned, name);
      attempts++;
    }

    if (card == null) {
      onError?.call(
        'Failed to parse base card JSON after multiple attempts. Try a different model or prompt.',
      );
      return null;
    }

    // If the user provided a specific scenario, use it verbatim —
    // don't let the LLM summarize or rewrite it.
    if (scenario.trim().isNotEmpty) {
      card.scenario = scenario.trim();
      debugPrint('CharacterGen: Using user-provided scenario verbatim');
    }

    // ── Step 1b: (system_prompt intentionally left blank) ────────────
    // The character card's system_prompt field is left empty so the
    // user's active system prompt or API default is used at chat time.

    // ── Step 1c: Truncation recovery ────────────────────────────
    // If critical fields are empty, the JSON was likely truncated.
    // Make a focused retry asking only for the missing fields.
    final missingFields = <String>[];
    if (card.personality.trim().isEmpty) missingFields.add('personality');
    if (card.scenario.trim().isEmpty) missingFields.add('scenario');

    if (missingFields.isNotEmpty) {
      debugPrint(
        'CharacterGen: Truncation detected — missing: ${missingFields.join(", ")}',
      );
      onStatus?.call('Recovering truncated fields...');
      onProgress?.call('');

      final recoveryCard = await _s.lore.recoverMissingFields(
        name: name,
        concept: concept,
        personalityKeywords: personalityKeywords,
        missingFields: missingFields,
        apiSystemPrompt: apiSystemPrompt,
        age: age,
        sex: sex,
        relationship: relationship,
        backstory: backstory,
        onProgress: onProgress,
      );

      if (recoveryCard != null) {
        if (card.personality.trim().isEmpty &&
            recoveryCard.personality.trim().isNotEmpty) {
          card.personality = recoveryCard.personality;
        }
        if (card.scenario.trim().isEmpty &&
            recoveryCard.scenario.trim().isNotEmpty) {
          card.scenario = recoveryCard.scenario;
        }
        debugPrint(
          'CharacterGen: Recovery filled ${missingFields.length - [if (card.personality.trim().isEmpty) 'personality', if (card.scenario.trim().isEmpty) 'scenario'].length} fields',
        );
      }
    }
    if (_state.isStale(currentEpoch)) return null;

    // ── Step 2: Character Interview (voice enrichment) ────────────
    // Run 5 in-character Q&A turns to establish authentic voice.
    // Use the accumulated answers to rewrite description + personality,
    // enrich lorebook entries, and pass the transcript into greeting prompts.
    onStatus?.call('Running character interview...');
    onProgress?.call('');
    final interviewTranscript = await _s.interview.runInterview(
      card: card,
      name: name,
      nsfwEnabled: nsfwEnabled,
      relationship: relationship,
      onStatus: onStatus,
      onProgress: onProgress,
      worldLore: worldLore,
    );

    if (interviewTranscript.isNotEmpty) {
      // Rewrite description and personality using the interview voice
      onStatus?.call('Enriching character profile from interview...');
      onProgress?.call('');
      await _s.interview.enrichCardFromInterview(
        card: card,
        name: name,
        interviewTranscript: interviewTranscript,
        preserveUserScenario: scenario.trim().isNotEmpty,
        onProgress: onProgress,
      );
    }
    if (_state.isStale(currentEpoch)) return null;

    // The Automated mode's description, verbatim over the model's rewrite,
    // so the profile step and the facts read the text the user built.
    final override = inputs.descriptionOverride;
    if (override != null) card.description = override;

    // ── Step 3: Identity facts (birthday, work, stance, lists, notes) ──
    IdentityFacts? facts;
    if (inputs.includeIdentityFacts) {
      onStatus?.call("Reading the character's facts...");
      onProgress?.call('');
      facts = await _s.identity.read(
        name: name,
        age: age,
        sex: sex,
        relationship: relationship,
        description: card.description,
        personality: card.personality,
        scenario: card.scenario,
        interviewTranscript: interviewTranscript,
        nsfwEnabled: nsfwEnabled,
        onProgress: onProgress,
      );
      if (_state.isStale(currentEpoch)) return null;
      if (facts != null) {
        applyIdentityFacts(card, facts, nsfw: nsfwEnabled);
      }
    }

    return (
      GenPausedRun(
        inputs: inputs,
        card: card,
        interviewTranscript: interviewTranscript,
        facts: facts,
      ),
      currentEpoch,
    );
  }
}
