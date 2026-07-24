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
import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/utils/json_sanitizer.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/chargen/char_macro.dart';
import 'package:front_porch_ai/services/chargen/lorebook_mechanics.dart';

part 'chargen/character_gen_llm.dart';
part 'chargen/character_gen_prompts.dart';
part 'chargen/character_gen_steps.dart';
part 'chargen/character_gen_steps2.dart';
part 'chargen/character_gen_parsing.dart';
part 'chargen/character_gen_editors.dart';

/// Per-category descriptions for lorebook generation prompts.
const _loreCategoryDescriptions = {
  'Locations':
      'Notable places in the world: cities, provinces, landmarks, dungeons, taverns, wilderness areas. Describe geography, atmosphere, reputation, and who frequents them',
  'NPCs/Allies':
      'Supporting characters who exist in the world: shopkeepers, rulers, rivals, mysterious figures, recurring contacts. Name, role, personality, and relationship to the setting',
  'Factions/Organizations':
      'Guilds, governments, criminal syndicates, cults, religious orders, military groups. Structure, goals, reputation, territory, and influence',
  'Culture/Customs':
      'Social norms, traditions, holidays, taboos, greetings, food, clothing, entertainment, laws. How people in this world live day-to-day',
  'Abilities/Magic':
      'Magic systems, combat arts, supernatural phenomena, technology rules. How powers work, costs, limitations, who can use them, societal attitudes toward them',
  'Flora/Fauna':
      'Creatures, monsters, beasts, plants, and materials unique to this world. Appearance, behavior, ecological role, uses, and dangers',
  'History/Events':
      'World-level historical events: wars, cataclysms, discoveries, founding of nations, political upheavals. NOT the character\'s personal biography',
  'Items/Equipment':
      'Notable weapons, artifacts, potions, tools, currencies, trade goods. Origin, properties, rarity, cultural significance',
  'Secrets/Hidden Lore':
      'Forbidden knowledge, hidden locations, conspiracies, prophecies, sealed powers, forgotten truths that most people in the world don\'t know about',
};

// The interview is assembled in _runCharacterInterview in a deliberate order:
// VOICE first (it grounds the greeting + example dialogue, so establishing it
// early keeps every later answer voice-consistent), then motive/wound, the
// (conditional) relationship to {{user}}, the social gradient, pressure
// behavior, joy, the (conditional) NSFW question, and APPEARANCE last (so the
// character doesn't open with a vanity monologue before its voice exists). The
// old "goal triad" (three overlapping questions about wants/plans/how) was
// collapsed into one motive + one wound question.
const _qVoice =
    'How do you talk? Give me two quick samples of your voice: first, how you\'d '
    'explain something to someone you\'re trying to impress — then how you\'d say '
    'the same thing to someone you completely trust.';
const _qWho =
    'In your own words: who are you, and what do you want more than anything '
    'right now?';
const _qWound =
    'Tell me about a moment from your past that shaped who you are — and what it '
    'left you afraid of, or unable to do.';
const _qSocial =
    'How do you treat someone who\'s just met you versus someone you\'ve come to '
    'trust completely? What changes?';
const _qPressure =
    'When you\'re cornered, or when someone truly angers you — what do you '
    'actually do? Show me, don\'t tell me.';
const _qJoy =
    'What brings you genuine joy or peace — the thing that lets your guard down?';
const _qAppearance =
    'Now describe your physical appearance in your own words — what you look like '
    'and how you carry yourself. Be specific.';

/// Only asked when a relationship to {{user}} is set — voices the bond so the
/// greeting and example dialogue carry real history. Skipped for strangers /
/// one-shots (an empty relationship), where invented shared history would hurt.
String _relationshipQuestion(String relationship) =>
    'Your relationship to {{user}} is: $relationship. Who are they to you, '
    'really — what do you want from them, and what\'s unresolved or unspoken '
    'between you?';

const _nsfwInterviewQuestion =
    'When it comes to sex and intimacy: what do you crave, where are your hard '
    'limits, are you dominant or submissive — and if there\'s someone you '
    'desire, what do they do to you?';

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
  final LLMService _llmService;

  /// The raw LLM output from the last base card generation, for image prompt extraction.
  String? lastRawOutput;
  String? generatedImagePrompt;

  int _generationEpoch = 0;
  bool _aborted = false;
  bool _reasoningEnabled = false;

  /// Whether this run may tear down other in-flight work on the shared LLM
  /// service (the client abort at start + the server-side abort each step
  /// takes on local KoboldCpp). True for the interactive wizard (clear stuck
  /// state from a previous run); false for background runs like the Scene
  /// Guest mint, which must WAIT for the backend instead of killing the
  /// journal/growth/realism evals that legitimately share it.
  bool _abortInFlight = true;

  /// Opt-in: when true, the lorebook + greeting prompts invite the model to add
  /// dynamic `{{pick}}`/`{{roll}}` "living detail" macros. Off by default —
  /// capable models use them well, weaker ones place them awkwardly.
  bool _includeDynamicMacros = false;

  bool get isAborted => _aborted;

  /// Abort the current generation. Signals the LLM service to close its
  /// HTTP connection and sets a flag so inter-step checks bail out.
  void abort() {
    _aborted = true;
    _generationEpoch++; // Invalidate any in-flight retry loops
    _llmService.abortGeneration();
    debugPrint('CharacterGen: Abort requested by user');
  }

  CharacterGenService(this._llmService);

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
    bool abortInFlight = true,
    void Function(String accumulated)? onProgress,
    void Function(String error)? onError,
    void Function(String status)? onStatus,
  }) async {
    // ── Step 1: Generate base card ──────────────────────────────
    onStatus?.call('Generating character profile...');
    final basePrompt = _buildBasePrompt(
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
    _generationEpoch++;
    final int currentEpoch = _generationEpoch;
    _aborted = false;
    // Clear stuck state from a previous interactive run. abortGeneration is
    // SERVICE-WIDE: it closes whatever request the shared backend has in
    // flight, so background callers (the Scene Guest mint, which runs inside
    // a live chat where journal/growth/realism evals are expected to be
    // mid-request) pass abortInFlight: false to avoid killing them.
    // _abortInFlight also gates the per-step server-side idle handling in
    // _callLLM (force-abort vs wait) for the same reason.
    _abortInFlight = abortInFlight;
    if (abortInFlight) _llmService.abortGeneration();
    _reasoningEnabled = reasoningEnabled;
    _includeDynamicMacros = includeDynamicMacros;

    int attempts = 0;
    CharacterCard? card;

    while (attempts < 3 && card == null) {
      if (_aborted || _generationEpoch != currentEpoch) return null;
      if (attempts > 0) {
        onStatus?.call('JSON Parse failed. Retrying generation...');
        debugPrint(
          'CharacterGen: Retrying generation (Attempt ${attempts + 1})',
        );
      }

      final baseOutput = await _callLLM(
        basePrompt,
        isJsonMode: true,
        onProgress: attempts == 0 ? onProgress : null,
      );
      lastRawOutput = baseOutput; // Store for image prompt extraction

      if (baseOutput == null) {
        attempts++;
        continue;
      }

      // Reject suspiciously short output (model warm-up / placeholder)
      final strippedLen = baseOutput
          .replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '')
          .trim()
          .length;
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

      card = _parseCharacterJson(cleaned, name);
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

      final recoveryCard = await _recoverMissingFields(
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
    if (_aborted || _generationEpoch != currentEpoch) return null;

    // ── Step 2: Character Interview (voice enrichment) ────────────
    // Run 5 in-character Q&A turns to establish authentic voice.
    // Use the accumulated answers to rewrite description + personality,
    // enrich lorebook entries, and pass the transcript into greeting prompts.
    onStatus?.call('Running character interview...');
    onProgress?.call('');
    final interviewTranscript = await _runCharacterInterview(
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
      await _enrichCardFromInterview(
        card: card,
        name: name,
        interviewTranscript: interviewTranscript,
        preserveUserScenario: scenario.trim().isNotEmpty,
        onProgress: onProgress,
      );
    }
    if (_aborted || _generationEpoch != currentEpoch) return null;

    // ── Step 2c: Generate example dialogue (dedicated step) ────────
    // Runs after enrichment so we have the final personality text.
    // Uses raw text output (not JSON) for reliability.
    if (interviewTranscript.isNotEmpty) {
      onStatus?.call('Writing example dialogue...');
      onProgress?.call('');
      await _generateExampleDialogue(
        card: card,
        name: name,
        interviewTranscript: interviewTranscript,
        onProgress: onProgress,
      );
    }
    if (_aborted || _generationEpoch != currentEpoch) return null;

    // ── Step 2b: Lorebook generation (after interview) ────────────
    // Runs after interview so transcript context makes entries richer.
    // Only fires if lorebook was requested and not yet generated inline.
    if (generateLorebook &&
        (card.lorebook == null || card.lorebook!.entries.isEmpty)) {
      debugPrint('CharacterGen: Generating lorebook after interview...');
      onStatus?.call('Generating world lore...');
      onProgress?.call('');
      await _generateLorebookSeparately(
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
    if (_aborted || _generationEpoch != currentEpoch) return null;

    // ── Step 3: Generate first message ────────────────────────
    onStatus?.call('Writing first message...');
    onProgress?.call(''); // Clear preview
    final firstMsgPrompt = _buildGreetingPrompt(
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

    final firstMsgOutput = await _callLLM(
      firstMsgPrompt,
      maxLen: 4096,
      minLen: 512,
      onProgress: onProgress,
    );
    if (firstMsgOutput != null && firstMsgOutput.trim().isNotEmpty) {
      card.firstMessage = _cleanGreeting(firstMsgOutput);
    }
    if (_aborted || _generationEpoch != currentEpoch) return null;

    // ── Step 4: Generate alternate greetings ──────────────────
    if (altGreetingCount > 0) {
      // Generate distinct meeting scenarios for each alt greeting upfront.
      // This is the key difference: each alt gets its own unique context
      // (chance coffee shop encounter, shared umbrella in a rainstorm, etc.)
      // so they're structurally different stories, not just mood variations.
      onStatus?.call('Planning alternate scenarios...');
      onProgress?.call('');
      final altScenarios = await _generateAltScenarios(
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

        final altPrompt = _buildGreetingPrompt(
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

        final altOutput = await _callLLM(
          altPrompt,
          maxLen: 4096,
          minLen: 512,
          onProgress: onProgress,
        );
        if (altOutput != null && altOutput.trim().isNotEmpty) {
          alts.add(_cleanGreeting(altOutput));
        }
      }
      card.alternateGreetings = alts;
    }
    if (_aborted || _generationEpoch != currentEpoch) return null;

    // ── Step 5: Generate Tailored Image Prompt ────────────────
    onStatus?.call('Drafting illustration prompt...');
    onProgress?.call('');
    generatedImagePrompt = await _generateImagePrompt(
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

    onStatus?.call('Character generated!');
    return card;
  }
}
