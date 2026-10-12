// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_gen/gen_parsing.dart';
import 'package:front_porch_ai/services/character_gen/gen_prompts.dart';
import 'package:front_porch_ai/services/character_gen/gen_run_state.dart';
import 'package:front_porch_ai/services/character_gen/gen_stages.dart';
import 'package:front_porch_ai/services/character_gen/greeting_recipe.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The AI Create pipeline: base card, interview, enrichment, dialogue,
/// lorebook, greetings, Porch Life, and the image prompt.
class GenCharacterGenerator {
  GenCharacterGenerator(this._s);

  final GenStages _s;
  GenRunState get _state => _s.state;

  /// Generate a complete character card from user-provided creative inputs.
  ///
  /// Uses multi-step generation: base card first, then greetings separately.
  Future<CharacterCard?> run({
    required String name,
    required String concept,
    required String personalityKeywords,
    required String artStyle,
    required String imageGenPromptParadigm,
    required String greetingLength,
    required int altGreetingCount,
    required List<String> greetingTones,
    required bool generateLorebook,
    required List<String> loreCategories,
    required String loreDepth,
    required String apiSystemPrompt,
    required String age,
    required String sex,
    required String relationship,
    required String descriptionDetail,
    required String backstory,
    required String scenario,
    required String characterContext,
    required String userPersonaContext,
    required String? worldLore,
    required bool generateDescription,
    required bool nsfwEnabled,
    required bool reasoningEnabled,
    required bool includeDynamicMacros,
    required String narrativePerspective,
    required String narrativeTense,
    required bool abortInFlight,
    required void Function(String accumulated)? onProgress,
    required void Function(String error)? onError,
    required void Function(String status)? onStatus,
  }) async {
    // Voice must be set BEFORE the base-card prompt so description /
    // personality pick up tense and third-person pronouns.
    _state.narrativeVoice = NarrativeVoice.parse(
      perspective: narrativePerspective,
      tense: narrativeTense,
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
      generateLorebook: generateLorebook,
      loreCategories: loreCategories,
      loreDepth: loreDepth,
      apiSystemPrompt: apiSystemPrompt,
      age: age,
      sex: sex,
      relationship: relationship,
      descriptionDetail: descriptionDetail,
      generateDescription: generateDescription,
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
      includeDynamicMacros: includeDynamicMacros,
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

    // ── Step 2c: Generate example dialogue (dedicated step) ────────
    // Runs after enrichment so we have the final personality text.
    // Uses raw text output (not JSON) for reliability.
    if (interviewTranscript.isNotEmpty) {
      onStatus?.call('Writing example dialogue...');
      onProgress?.call('');
      await _s.interview.generateExampleDialogue(
        card: card,
        name: name,
        interviewTranscript: interviewTranscript,
        onProgress: onProgress,
      );
    }
    if (_state.isStale(currentEpoch)) return null;

    // ── Step 2b: Lorebook generation (after interview) ────────────
    // Runs after interview so transcript context makes entries richer.
    // Only fires if lorebook was requested and not yet generated inline.
    if (generateLorebook &&
        (card.lorebook == null || card.lorebook!.entries.isEmpty)) {
      debugPrint('CharacterGen: Generating lorebook after interview...');
      onStatus?.call('Generating world lore...');
      onProgress?.call('');
      await _s.lore.generateLorebookSeparately(
        card: card,
        name: name,
        concept: concept,
        loreCategories: loreCategories,
        loreDepth: loreDepth,
        interviewTranscript: interviewTranscript,
        worldLore: worldLore,
        onProgress: onProgress,
      );
    }
    if (_state.isStale(currentEpoch)) return null;

    // Kept so the creator's Greetings step can write one more greeting the
    // way these were written (regenerateGreeting).
    _state.greetingRecipe = GreetingRecipe(
      greetingLength: greetingLength,
      tones: greetingTones,
      characterContext: characterContext,
      userPersonaContext: userPersonaContext,
      interviewTranscript: interviewTranscript,
      worldLore: worldLore,
      includeDynamicMacros: includeDynamicMacros,
      reasoningEnabled: reasoningEnabled,
      nsfwEnabled: nsfwEnabled,
    );

    // ── Step 3: Generate first message ────────────────────────
    onStatus?.call('Writing first message...');
    onProgress?.call(''); // Clear preview
    final firstMsgPrompt = _s.greetingPrompt(
      name: name,
      description: card.description,
      personality: card.personality,
      scenario: card.scenario,
      length: greetingLength,
      tone: greetingTones.isNotEmpty ? greetingTones[0] : 'Neutral',
      previousGreetings: [],
      characterContext: characterContext,
      userPersonaContext: userPersonaContext,
      interviewTranscript: interviewTranscript,
      worldLore: worldLore,
    );

    final firstMsgOutput = await _s.llm.call(
      firstMsgPrompt,
      maxLen: 4096,
      minLen: 512,
      onProgress: onProgress,
    );
    if (firstMsgOutput != null && firstMsgOutput.trim().isNotEmpty) {
      card.firstMessage = cleanGeneratedGreeting(firstMsgOutput);
    }
    if (_state.isStale(currentEpoch)) return null;

    // ── Step 4: Generate alternate greetings ──────────────────
    if (altGreetingCount > 0) {
      // Generate distinct meeting scenarios for each alt greeting upfront.
      // This is the key difference: each alt gets its own unique context
      // (chance coffee shop encounter, shared umbrella in a rainstorm, etc.)
      // so they're structurally different stories, not just mood variations.
      onStatus?.call('Planning alternate scenarios...');
      onProgress?.call('');
      final altScenarios = await _s.interview.generateAltScenarios(
        name: name,
        concept: concept,
        defaultScenario: card.scenario,
        personality: card.personality,
        count: altGreetingCount,
        worldLore: worldLore,
        onProgress: onProgress,
      );

      final alts = <String>[];
      for (int i = 0; i < altGreetingCount; i++) {
        onStatus?.call(
          'Writing alternate greeting ${i + 1} of $altGreetingCount...',
        );
        onProgress?.call(''); // Clear preview

        // Use the unique scenario for this alt; fall back to default if generation failed.
        final altScenario =
            (i < altScenarios.length && altScenarios[i].isNotEmpty)
            ? altScenarios[i]
            : card.scenario;

        final altPrompt = _s.greetingPrompt(
          name: name,
          description: card.description,
          personality: card.personality,
          scenario: altScenario,
          length: greetingLength,
          tone: greetingTones.isNotEmpty
              ? greetingTones[(i + 1) % greetingTones.length]
              : 'Neutral',
          previousGreetings: [card.firstMessage, ...alts],
          characterContext: characterContext,
          userPersonaContext: userPersonaContext,
          interviewTranscript: interviewTranscript,
          worldLore: worldLore,
        );

        final altOutput = await _s.llm.call(
          altPrompt,
          maxLen: 4096,
          minLen: 512,
          onProgress: onProgress,
        );
        if (altOutput != null && altOutput.trim().isNotEmpty) {
          alts.add(cleanGeneratedGreeting(altOutput));
        }
      }
      // Seeds are not authored with these rewritten alts — compact against
      // empty so leftover source furious cannot land on Get out.
      card.assignRewrittenAlternateGreetings(alts);
    }
    if (_state.isStale(currentEpoch)) return null;

    // ── Step 4b: Porch Life identity (ambitions / wardrobe / tastes) ──
    // After the greeting exists so worn/carrying match the opening beat.
    // Tools first when the backend speaks them; text JSON is the floor.
    onStatus?.call('Seeding wardrobe and ambitions...');
    onProgress?.call('');
    await _s.porchLife.seedIdentity(
      card: card,
      name: name,
      interviewTranscript: interviewTranscript,
      nsfwEnabled: nsfwEnabled,
      onProgress: onProgress,
    );
    if (_state.isStale(currentEpoch)) return null;

    // ── Step 5: Generate Tailored Image Prompt ────────────────
    onStatus?.call('Drafting illustration prompt...');
    onProgress?.call('');
    _state.generatedImagePrompt = await _s.lore.generateImagePrompt(
      name: name,
      description: card.description,
      scenario: card.scenario,
      artStyle: artStyle,
      imageGenPromptParadigm: imageGenPromptParadigm,
      onProgress: onProgress,
    );

    // Models don't reliably emit {{char}} for description/personality even when
    // instructed to, and a literal name baked into the card can confuse models
    // mid-chat. Normalize every generated text field to the portable macro.
    // (Logic lives in chargen/char_macro.dart so it stays unit-testable.)
    applyCharMacroToCard(card, name);
    stampNarrativeVoice(
      card,
      voice: _state.narrativeVoice,
      sex: _state.narrativeSex,
    );
    // Beside the voice: how the greetings were written, so a rewrite after a
    // reload or a restart matches them (the desktop save and the web create
    // both persist this card).
    final recipe = _state.greetingRecipe;
    if (recipe != null) stampGreetingRecipe(card, recipe);

    onStatus?.call('Character generated!');
    return card;
  }
}
