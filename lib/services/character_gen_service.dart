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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/character_gen/character_gen.dart';

export 'package:front_porch_ai/services/character_gen/gen_paused_run.dart';
export 'package:front_porch_ai/services/character_gen/gen_profile_writer.dart'
    show ProfileRewrite;
export 'package:front_porch_ai/services/character_gen/gen_run_inputs.dart';
export 'package:front_porch_ai/services/character_gen/greeting_recipe.dart';

/// Service for AI-powered character generation.
///
/// Takes minimal user input (name, concept, personality keywords)
/// and uses the LLM to generate a complete V2 character card.
///
/// Generation is split into multiple API calls:
/// 1. Base card (description, personality, scenario, etc.)
/// 2. First message (dedicated call for quality)
/// 3. Alternate greetings (one per call, with prior context for uniqueness)
class CharacterGenService {
  /// [retryDelay] is how long a failed model call waits before each retry
  /// (default 2 s, 4 s); tests pass zero.
  CharacterGenService(
    this._llmService, {
    Duration Function(int attempt)? retryDelay,
  }) : _retryDelay = retryDelay;

  final LLMService _llmService;
  final Duration Function(int attempt)? _retryDelay;
  late final GenRunState _state = GenRunState(
    _llmService,
    retryDelay: _retryDelay,
  );
  late final GenStages _stages = GenStages(_state);
  late final GenCharacterGenerator _generator = GenCharacterGenerator(_stages);
  late final GenEnhancer _enhancer = GenEnhancer(_stages);
  late final GenGreetingWriter _greetings = GenGreetingWriter(_stages);
  late final GenProfileWriter _profile = GenProfileWriter(_stages);
  late final GenReviewRewrites _review = GenReviewRewrites(_stages);

  /// The raw LLM output from the last base card generation, for image prompt extraction.
  String? get lastRawOutput => _state.lastRawOutput;
  set lastRawOutput(String? value) => _state.lastRawOutput = value;

  String? get generatedImagePrompt => _state.generatedImagePrompt;
  set generatedImagePrompt(String? value) =>
      _state.generatedImagePrompt = value;

  /// How the last [generateCharacter] run wrote its greetings.
  /// Null until a run reaches them.
  GreetingRecipe? get greetingRecipe => _state.greetingRecipe;
  set greetingRecipe(GreetingRecipe? value) => _state.greetingRecipe = value;

  bool get isAborted => _state.aborted;

  /// Why the last call of the last run failed after its retries (the
  /// backend's error text), or null when nothing failed since that run
  /// began. A Stop never sets it. When a rewrite, re-read or regenerate
  /// returns null, null here means the model answered the same or nothing
  /// usable; set means it failed: "The rewrite failed: [lastFailure]".
  String? get lastFailure => _state.lastFailure;

  /// Abort the current generation. Signals the LLM service to close its
  /// HTTP connection and sets a flag so inter-step checks bail out.
  void abort() {
    _state.aborted = true;
    _state.generationEpoch++; // Invalidate any in-flight retry loops
    _llmService.abortGeneration();
    debugPrint('CharacterGen: Abort requested by user');
  }

  /// Generate a complete character card from user-provided creative inputs.
  ///
  /// Uses multi-step generation: base card first, then greetings separately.
  Future<CharacterCard?> generateCharacter({
    required String name,
    required String concept,
    String personalityKeywords = '',
    String artStyle = '',
    String imageGenPromptParadigm = 'natural',
    String greetingLength = 'Medium (2-4 paragraphs)',
    int altGreetingCount = 2,
    List<String> greetingTones = const ['Neutral'],
    bool generateLorebook = true,
    List<String> loreCategories = const [],
    String loreDepth = 'Standard',
    String apiSystemPrompt = '',
    String age = '',
    String sex = '',
    String relationship = '',
    String descriptionDetail = '2-3 paragraphs',
    String backstory = '',
    String scenario = '',
    String characterContext = '',
    String userPersonaContext = '',
    String? worldLore,
    bool generateDescription = false,
    bool nsfwEnabled = false,
    bool reasoningEnabled = false,
    bool includeDynamicMacros = false,
    String narrativePerspective = 'first',
    String narrativeTense = 'present',
    String? descriptionOverride,
    bool includeIdentityFacts = true,
    bool abortInFlight = true,
    void Function(String accumulated)? onProgress,
    void Function(String error)? onError,
    void Function(String status)? onStatus,
  }) => _generator.run(
    GenRunInputs(
      name: name,
      concept: concept,
      personalityKeywords: personalityKeywords,
      artStyle: artStyle,
      imageGenPromptParadigm: imageGenPromptParadigm,
      greetingLength: greetingLength,
      altGreetingCount: altGreetingCount,
      greetingTones: greetingTones,
      generateLorebook: generateLorebook,
      loreCategories: loreCategories,
      loreDepth: loreDepth,
      apiSystemPrompt: apiSystemPrompt,
      age: age,
      sex: sex,
      relationship: relationship,
      descriptionDetail: descriptionDetail,
      backstory: backstory,
      scenario: scenario,
      characterContext: characterContext,
      userPersonaContext: userPersonaContext,
      worldLore: worldLore,
      generateDescription: generateDescription,
      nsfwEnabled: nsfwEnabled,
      reasoningEnabled: reasoningEnabled,
      includeDynamicMacros: includeDynamicMacros,
      narrativePerspective: narrativePerspective,
      narrativeTense: narrativeTense,
      descriptionOverride: descriptionOverride,
      includeIdentityFacts: includeIdentityFacts,
    ),
    abortInFlight: abortInFlight,
    onProgress: onProgress,
    onError: onError,
    onStatus: onStatus,
  );

  /// Phase A of [generateCharacter]: base card, interview, the profile
  /// rewrite and the identity facts, then stop. Nothing downstream
  /// (dialogue, lorebook, greetings, the opening scene) is written until
  /// [completeCharacter]. Null when stopped or no card could be read.
  Future<GenPausedRun?> generateProfile({
    required GenRunInputs inputs,
    bool abortInFlight = true,
    void Function(String accumulated)? onProgress,
    void Function(String error)? onError,
    void Function(String status)? onStatus,
  }) => _generator.generateProfile(
    inputs,
    abortInFlight: abortInFlight,
    onProgress: onProgress,
    onError: onError,
    onStatus: onStatus,
  );

  /// Phase B for [paused], as its own run on a copy of its card (a Stop
  /// leaves [paused] as it was). The returned card is what
  /// [generateCharacter] would have returned. Null when stopped.
  Future<CharacterCard?> completeCharacter({
    required GenPausedRun paused,
    bool abortInFlight = true,
    void Function(String accumulated)? onProgress,
    void Function(String error)? onError,
    void Function(String status)? onStatus,
  }) => _generator.complete(
    paused: paused,
    abortInFlight: abortInFlight,
    onProgress: onProgress,
    onError: onError,
    onStatus: onStatus,
  );

  /// Rewrite [paused]'s profile from its interview and the three texts as
  /// the author has them now, steered by [direction]; then re-read the
  /// facts. [onProgress] streams the rewrite's JSON (`parseProfileStream`).
  /// Null when stopped or when the model changed nothing.
  Future<ProfileRewrite?> rewriteProfile({
    required GenPausedRun paused,
    required String description,
    required String personality,
    required String scenario,
    String direction = '',
    bool abortInFlight = true,
    void Function(String accumulated)? onProgress,
  }) => _profile.rewriteProfile(
    paused: paused,
    description: description,
    personality: personality,
    scenario: scenario,
    direction: direction,
    abortInFlight: abortInFlight,
    onProgress: onProgress,
  );

  /// Read [paused]'s identity facts again from the profile as it is now.
  Future<IdentityFacts?> rereadIdentityFacts({
    required GenPausedRun paused,
    required String description,
    required String personality,
    required String scenario,
    bool abortInFlight = true,
  }) => _profile.rereadIdentityFacts(
    paused: paused,
    description: description,
    personality: personality,
    scenario: scenario,
    abortInFlight: abortInFlight,
  );

  /// New example dialogue for [card], steered by [direction]. [card] is
  /// only read. Null when stopped or when nothing usable came back.
  Future<String?> regenerateExampleDialogue({
    required CharacterCard card,
    GreetingRecipe recipe = const GreetingRecipe(),
    String direction = '',
    bool abortInFlight = true,
    void Function(String accumulated)? onProgress,
  }) => _review.regenerateExampleDialogue(
    card: card,
    recipe: recipe,
    direction: direction,
    abortInFlight: abortInFlight,
    onProgress: onProgress,
  );

  /// A new lorebook for [card] that keeps entries edited by hand
  /// (`isHandEdited`) and the book's settings. [card] is only read.
  Future<Lorebook?> rewriteLorebook({
    required CharacterCard card,
    required String concept,
    GreetingRecipe recipe = const GreetingRecipe(),
    List<String> loreCategories = const [],
    String loreDepth = 'Standard',
    String direction = '',
    bool abortInFlight = true,
    void Function(String accumulated)? onProgress,
  }) => _review.rewriteLorebook(
    card: card,
    recipe: recipe,
    concept: concept,
    loreCategories: loreCategories,
    loreDepth: loreDepth,
    direction: direction,
    abortInFlight: abortInFlight,
    onProgress: onProgress,
  );

  /// Rewrite the [selection]-chosen text fields of [source] using
  /// [chatGrounding] (built by `buildChatExcerptBlock`) as the source of truth
  /// for voice and history.
  ///
  /// [source] is never mutated. The returned card carries the enhanced text
  /// fields (unselected ones keep [source]'s values verbatim); `lorebook` is
  /// non-null only when the selection asked for one. Returns null on abort or
  /// when nothing was selected.
  Future<CharacterCard?> enhanceCharacter({
    required CharacterCard source,
    required EnhanceSelection selection,
    required String chatGrounding,
    String userPersonaContext = '',
    String greetingLength = 'Medium (2-4 paragraphs)',
    bool nsfwEnabled = false,
    bool reasoningEnabled = false,
    bool abortInFlight = false,
    String? narrativePerspective,
    String? narrativeTense,
    String? sex,
    void Function(String accumulated)? onProgress,
    void Function(String error)? onError,
    void Function(String status)? onStatus,
  }) => _enhancer.run(
    source: source,
    selection: selection,
    chatGrounding: chatGrounding,
    userPersonaContext: userPersonaContext,
    greetingLength: greetingLength,
    nsfwEnabled: nsfwEnabled,
    reasoningEnabled: reasoningEnabled,
    abortInFlight: abortInFlight,
    narrativePerspective: narrativePerspective,
    narrativeTense: narrativeTense,
    sex: sex,
    onProgress: onProgress,
    onError: onError,
    onStatus: onStatus,
  );

  /// Write greeting [index] of [card] again. 0 is the first message, 1 and up
  /// are the alternates in order, and `alternateGreetings.length + 1` writes
  /// a new alternate. [direction] is the author's one-line steer; empty
  /// writes it as creation did. Same prompt, voice and clean-up as creation,
  /// from the card's current text. [card] is only read.
  ///
  /// Returns the new text with the name turned into `{{char}}`, or null
  /// when stopped ([abort]) or when the model gave nothing.
  Future<String?> regenerateGreeting({
    required CharacterCard card,
    required int index,
    String direction = '',
    GreetingRecipe recipe = const GreetingRecipe(),
    bool abortInFlight = true,
    void Function(String accumulated)? onProgress,
  }) => _greetings.regenerateGreeting(
    card: card,
    index: index,
    direction: direction,
    recipe: recipe,
    abortInFlight: abortInFlight,
    onProgress: onProgress,
  );

  /// Read again what [card]'s first message shows the character wearing and
  /// carrying: the Porch Life pass creation runs once the first message
  /// exists. Null when stopped, or when the model named nothing to wear or
  /// carry (the caller then keeps the outfit it has).
  Future<PorchLifeIdentity?> rereadOpeningWardrobe({
    required CharacterCard card,
    GreetingRecipe recipe = const GreetingRecipe(),
    bool abortInFlight = true,
  }) => _greetings.rereadOpeningWardrobe(
    card: card,
    recipe: recipe,
    abortInFlight: abortInFlight,
  );
}
