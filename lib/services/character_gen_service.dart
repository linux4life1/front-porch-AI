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
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';

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

  bool get isAborted => _aborted;

  /// Abort the current generation. Signals the LLM service to close its
  /// HTTP connection and sets a flag so inter-step checks bail out.
  void abort() {
    _aborted = true;
    _generationEpoch++; // Invalidate any in-flight retry loops
    _llmService.abortGeneration();
    debugPrint('CharacterGen: Abort requested by user');
  }

  /// Per-category descriptions for lorebook generation prompts.
  static const _loreCategoryDescriptions = {
    'Locations': 'Notable places in the world: cities, provinces, landmarks, dungeons, taverns, wilderness areas. Describe geography, atmosphere, reputation, and who frequents them',
    'NPCs/Allies': 'Supporting characters who exist in the world: shopkeepers, rulers, rivals, mysterious figures, recurring contacts. Name, role, personality, and relationship to the setting',
    'Factions/Organizations': 'Guilds, governments, criminal syndicates, cults, religious orders, military groups. Structure, goals, reputation, territory, and influence',
    'Culture/Customs': 'Social norms, traditions, holidays, taboos, greetings, food, clothing, entertainment, laws. How people in this world live day-to-day',
    'Abilities/Magic': 'Magic systems, combat arts, supernatural phenomena, technology rules. How powers work, costs, limitations, who can use them, societal attitudes toward them',
    'Flora/Fauna': 'Creatures, monsters, beasts, plants, and materials unique to this world. Appearance, behavior, ecological role, uses, and dangers',
    'History/Events': 'World-level historical events: wars, cataclysms, discoveries, founding of nations, political upheavals. NOT the character\'s personal biography',
    'Items/Equipment': 'Notable weapons, artifacts, potions, tools, currencies, trade goods. Origin, properties, rarity, cultural significance',
    'Secrets/Hidden Lore': 'Forbidden knowledge, hidden locations, conspiracies, prophecies, sealed powers, forgotten truths that most people in the world don\'t know about',
  };

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

    debugPrint('CharacterGen: Starting generation for "$name" (reasoning: $reasoningEnabled)');
    _generationEpoch++;
    final int currentEpoch = _generationEpoch;
    _aborted = false;
    _llmService.abortGeneration(); // clear stuck state just in case
    _reasoningEnabled = reasoningEnabled;

    int attempts = 0;
    CharacterCard? card;

    while (attempts < 3 && card == null) {
      if (_aborted || _generationEpoch != currentEpoch) return null;
      if (attempts > 0) {
        onStatus?.call('JSON Parse failed. Retrying generation...');
        debugPrint('CharacterGen: Retrying generation (Attempt ${attempts + 1})');
      }

      final baseOutput = await _callLLM(basePrompt, isJsonMode: true, onProgress: attempts == 0 ? onProgress : null);
      lastRawOutput = baseOutput; // Store for image prompt extraction
      
      if (baseOutput == null) {
        attempts++;
        continue;
      }

      // Reject suspiciously short output (model warm-up / placeholder)
      final strippedLen = baseOutput
          .replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim().length;
      if (strippedLen < 100) {
        debugPrint('CharacterGen: Output too short ($strippedLen chars) — likely placeholder, retrying');
        attempts++;
        continue;
      }

      final cleaned = JsonSanitizer.sanitize(baseOutput);
      debugPrint('CharacterGen: Base output cleaned (${cleaned.length} chars)');

      // Detect literal "..." placeholder values (some models output skeleton JSON)
      if (cleaned.contains('"..."') || cleaned.contains('"…"')) {
        debugPrint('CharacterGen: Detected placeholder "..." values — retrying');
        attempts++;
        continue;
      }

      card = _parseCharacterJson(cleaned, name);
      attempts++;
    }

    if (card == null) {
      onError?.call('Failed to parse base card JSON after multiple attempts. Try a different model or prompt.');
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
      debugPrint('CharacterGen: Truncation detected — missing: ${missingFields.join(", ")}');
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
        if (card.personality.trim().isEmpty && recoveryCard.personality.trim().isNotEmpty) {
          card.personality = recoveryCard.personality;
        }
        if (card.scenario.trim().isEmpty && recoveryCard.scenario.trim().isNotEmpty) {
          card.scenario = recoveryCard.scenario;
        }
        debugPrint('CharacterGen: Recovery filled ${missingFields.length - [
          if (card.personality.trim().isEmpty) 'personality',
          if (card.scenario.trim().isEmpty) 'scenario',
        ].length} fields');
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
      onStatus: onStatus,
      onProgress: onProgress,
      worldLore: worldLore,
    );

    if (interviewTranscript.isNotEmpty) {
      // Rewrite description and personality using the interview voice
      onStatus?.call('Enriching character profile from interview...');
      onProgress?.call('');
      await _enrichCardAndGenerateExamples(
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
    if (generateLorebook && (card.lorebook == null || card.lorebook!.entries.isEmpty)) {
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

    final firstMsgOutput = await _callLLM(firstMsgPrompt,
        maxLen: 4096, minLen: 512, onProgress: onProgress);
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
        onStatus?.call('Writing alternate greeting ${i + 1} of $altGreetingCount...');
        onProgress?.call(''); // Clear preview

        // Use the unique scenario for this alt; fall back to default if generation failed.
        final altScenario = (i < altScenarios.length && altScenarios[i].isNotEmpty)
            ? altScenarios[i]
            : card.scenario;

        final altPrompt = _buildGreetingPrompt(
          name: name,
          description: card.description,
          personality: card.personality,
          scenario: altScenario,
          length: greetingLength,
          tone: greetingTones.isNotEmpty ? greetingTones[(i + 1) % greetingTones.length] : 'Neutral',
          previousGreetings: [card.firstMessage, ...alts],
          characterContext: characterContext,
          userPersonaContext: userPersonaContext,
          interviewTranscript: interviewTranscript,
          worldLore: worldLore,
        );

        final altOutput = await _callLLM(altPrompt,
            maxLen: 4096, minLen: 512, onProgress: onProgress);
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

    onStatus?.call('Character generated!');
    return card;
  }

  // ═════════════════════════════════════════════════════════════
  //  Alternate Scenario Generation
  // ═════════════════════════════════════════════════════════════

  /// Generate [count] structurally distinct meeting scenarios for alt greetings.
  /// Each must be a completely different context from the default and from each other.
  /// Returns a list of scenario strings (may be shorter than [count] if parsing fails).
  Future<List<String>> _generateAltScenarios({
    required String name,
    required String concept,
    required String defaultScenario,
    required String personality,
    required int count,
    String? worldLore,
    void Function(String)? onProgress,
  }) async {
    final loreSection = (worldLore != null && worldLore.trim().isNotEmpty)
        ? '\n[ESTABLISHED WORLD LORE]:\n$worldLore\n\n(Use locations, situations, and systems specific to this world.)\n'
        : '';

    final prompt = '''Generate exactly $count completely different meeting scenarios for a roleplay character. Each scenario is where {{user}} and $name first encounter each other — or meet again in an unexpected context.

CHARACTER:
Name: $name
Concept: ${concept.length > 300 ? concept.substring(0, 300) + '...' : concept}
Personality: ${personality.length > 300 ? personality.substring(0, 300) + '...' : personality}

DEFAULT SCENARIO (do NOT repeat or closely resemble this):
$defaultScenario$loreSection

RULES:
- Each scenario must be a completely different TYPE of encounter (location, circumstances, and dynamic must all differ)
- No two scenarios can have the same setting or situation premise
- Scenarios should feel organic and character-appropriate — not random
- Each is 2-3 sentences: where they meet, why they're both there, and the immediate spark or tension
- Use {{user}} and {{char}} as placeholders
- Vary the energy: include a mix of (intimate, public, high-stakes, mundane-turned-interesting, unexpected)
- Scenarios must be self-contained — a writer can generate a full opening scene from just this text

Output ONLY a JSON object with a single key "scenarios" containing an array of exactly $count strings.
Example format: {"scenarios": ["Scenario one text.", "Scenario two text."]}

Respond with ONLY the JSON:''';

    final output = await _callLLM(prompt, maxLen: 1024, minLen: 100, isJsonMode: true, onProgress: onProgress);
    if (output == null) {
      debugPrint('CharacterGen: Alt scenario generation failed — using default scenario for all alts');
      return [];
    }

    try {
      final cleaned = _stripContent(output);
      final data = json.decode(cleaned) as Map<String, dynamic>;
      final raw = data['scenarios'];
      if (raw is List) {
        final scenarios = raw
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toList();
        debugPrint('CharacterGen: Generated ${scenarios.length} alt scenarios');
        return scenarios;
      }
    } catch (e) {
      debugPrint('CharacterGen: Alt scenario parse failed: $e — using default for all alts');
    }
    return [];
  }

  // ═════════════════════════════════════════════════════════════
  //  Character Interview (Voice Enrichment)
  // ═════════════════════════════════════════════════════════════

  static const _interviewQuestions = [
    'Describe your physical appearance in your own words. Be specific — what do you look like, and how do you carry yourself?',
    'Who are you, and what do you want more than anything?',
    'What are your goals and plans right now — what are you actively working toward?',
    'And how do you intend to achieve them? What is your approach or strategy — and what might get in your way?',
    'Tell me about a moment from your past that shaped who you are today.',
    'What are you most afraid of, and what brings you genuine joy?',
    'How do you treat people who have just met you versus people you trust completely?',
  ];

  static const _nsfwInterviewQuestion =
      'Describe your sex life — how often do you fuck, what\'s your favorite position, '
      'are you dominant or submissive, what kinks are you into, and what gets you off the hardest?';

  /// Run a cumulative in-character interview, returning the full transcript.
  /// Each answer is folded back into the next question's context — exactly as
  /// EllipsisLM does — so the model's "voice" deepens with each turn.
  /// When [nsfwEnabled] is true, an explicit sexual preference question is appended.
  Future<String> _runCharacterInterview({
    required CharacterCard card,
    required String name,
    bool nsfwEnabled = false,
    void Function(String)? onStatus,
    void Function(String)? onProgress,
    String? worldLore,
  }) async {
    final transcript = StringBuffer();
    // Seed the LLM with who this character is so the first answer is grounded
    final seed = 'You are ${name}.\n'
        'Your personality: ${card.personality.length > 400 ? card.personality.substring(0, 400) : card.personality}\n'
        'Your scenario: ${card.scenario.length > 200 ? card.scenario.substring(0, 200) : card.scenario}\n\n'
        '${worldLore != null && worldLore.trim().isNotEmpty ? "You exist in the following established world. Use its terminology, locations, and facts:\n$worldLore\n\n" : ""}'
        'Answer each question in first person, fully in-character. '
        'Be specific, vivid, and emotionally honest. Respond as ${name} would speak — '
        'use their vocabulary, cadence, and emotional register.';

    final questions = [
      ..._interviewQuestions,
      if (nsfwEnabled) _nsfwInterviewQuestion,
    ];

    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      onStatus?.call('Character interview (${i + 1}/${questions.length})...');
      onProgress?.call('');

      final prompt = '$seed\n\n'
          '${transcript.isNotEmpty ? 'Previous answers:\n$transcript\n\n' : ''}'
          'Question: $q\n\n'
          '${name}: ';

      final answer = await _callLLM(prompt, maxLen: 1200, minLen: 80, onProgress: onProgress);
      if (answer == null || answer.trim().isEmpty) {
        debugPrint('CharacterGen: Interview Q${i + 1} got empty answer — skipping');
        continue;
      }

      // Strip any think blocks from the answer before adding to transcript
      final cleanAnswer = answer
          .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
          .trim();

      transcript.writeln('Q: $q');
      transcript.writeln('A: $cleanAnswer');
      transcript.writeln();
      debugPrint('CharacterGen: Interview Q${i + 1} answered (${cleanAnswer.length} chars)');
    }

    return transcript.toString().trim();
  }

  /// Use the completed interview transcript to rewrite description, personality,
  /// and generate example dialogues with richer, voice-consistent prose grounded in the
  /// character's own words.
  Future<void> _enrichCardAndGenerateExamples({
    required CharacterCard card,
    required String name,
    required String interviewTranscript,
    void Function(String)? onProgress,
  }) async {
    final prompt = '''
You have just completed an in-character interview with $name.
Using the interview answers below as your source of truth, rewrite two fields and generate a third
for this character card. Output ONLY a JSON object with exactly three keys.
No markdown. No explanation. Just raw JSON.

INTERVIEW TRANSCRIPT:
$interviewTranscript

CURRENT DESCRIPTION (physical appearance only):
${card.description}

CURRENT PERSONALITY (inner traits):
${card.personality}

Rewrite these fields using the specific details, voice, and texture revealed in the interview:

- "description": (string) Third-person. Physical appearance ONLY: body, face, hair, eyes, clothing, posture, distinguishing marks. Use specific details that emerged in the interview — not generic adjectives. 2-3 paragraphs. Do NOT include personality, backstory, or scenario.
- "personality": (string) Third-person. Inner traits, motivations, fears, speech patterns, behavioral quirks, relationship style — grounded in what the character revealed. 2-3 paragraphs. Do NOT repeat physical appearance or scenario.
- "example_dialogue": (string) Generate 2-3 example dialogue exchanges showing {{char}}'s exact speech patterns, vocabulary, cadence, and emotional register revealed in the interview. Keep the <START>\\n{{user}}: ...\\n{{char}}: ... format. Each {{char}} response should feel authentically voiced — include verbal tics, slang, emotional reactions, and mannerisms the character demonstrated.

Use {{char}} for the character name and {{user}} for the user throughout.

Respond with ONLY the JSON:''';

    final output = await _callLLM(prompt, maxLen: 4096, minLen: 200, isJsonMode: true, onProgress: onProgress);
    if (output == null) {
      debugPrint('CharacterGen: Interview enrichment got no response — keeping original fields');
      return;
    }

    final cleaned = _stripContent(output);
    debugPrint('CharacterGen: Enrichment output cleaned (${cleaned.length} chars)');

    // Use regex extraction instead of json.decode — models routinely output
    // unescaped quotes (5'9", etc.) that break strict JSON parsing. The regex
    // extractor finds values by key boundaries, handling all malformed output.
    final data = _regexExtract(cleaned);
    debugPrint('CharacterGen: Enrichment extracted keys: ${data.keys.toList()}');

    final newDesc = (data['description']?.toString() ?? '').trim();
    final newPers = (data['personality']?.toString() ?? '').trim();
    final newExamples = (data['example_dialogue'] ??
            data['mes_example'] ??
            data['example_messages'] ??
            data['examples'])
        ?.toString().trim() ?? '';

    if (newDesc.isNotEmpty && newDesc.length >= card.description.length * 0.5) {
      card.description = newDesc;
      debugPrint('CharacterGen: Description enriched (${newDesc.length} chars)');
    }
    if (newPers.isNotEmpty && newPers.length >= card.personality.length * 0.5) {
      card.personality = newPers;
      debugPrint('CharacterGen: Personality enriched (${newPers.length} chars)');
    }
    if (newExamples.isNotEmpty && newExamples.length > 50) {
      card.mesExample = newExamples;
      debugPrint('CharacterGen: Example dialogue generated (${newExamples.length} chars)');
    } else {
      debugPrint('CharacterGen: No example dialogue in enrichment '
          '(keys: ${data.keys.toList()}, example len: ${newExamples.length})');
    }
  }

  // ═════════════════════════════════════════════════════════════
  //  LLM Calling
  // ═════════════════════════════════════════════════════════════

  /// Call the LLM and collect all tokens. Returns raw text or null.
  /// Retries up to [maxRetries] times with exponential backoff on failure.
  ///
  /// [isJsonMode] — When true, adds `}\n` to stop sequences so the model halts
  /// the moment the JSON object closes (safe for thinking models: they think
  /// freely, then produce the JSON, then hit `}\n` and stop).
  /// [grammar] — Optional GBNF grammar string for KoboldCPP local + non-thinking
  /// backends. Pass null to skip (all API backends ignore this).
  Future<String?> _callLLM(String prompt, {
    int maxLen = 8192,
    int minLen = 64,
    int maxRetries = 3,
    bool isJsonMode = false,
    void Function(String accumulated)? onProgress,
  }) async {
    final int myEpoch = _generationEpoch;
    final promptEstTokens = (prompt.length / 4).ceil();
    debugPrint('CharacterGen: Prompt size: ${prompt.length} chars (~$promptEstTokens tokens), maxLen: $maxLen');
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      if (_aborted || _generationEpoch != myEpoch) {
        debugPrint('CharacterGen: Aborting before attempt $attempt');
        return null;
      }

      String accumulated = '';
      int tokenCount = 0;
      bool repetitionDetected = false;
      try {
        if (_llmService is KoboldService) {
          await _llmService.ensureServerIdle();
        }
        if (_aborted || _generationEpoch != myEpoch) return null;

        final stops = ['<END>', '</END>'];
        // NOTE: We intentionally do NOT add '}\n' as a stop sequence for
        // JSON mode. Character cards use {{char}} and {{user}} template
        // markers — the API matches }\n inside }}\n and truncates the
        // output. JSON completion is handled by the balanced brace checker.

        await for (final token in _llmService.generateStream(GenerationParams(
          prompt: prompt,
          maxLength: maxLen,
          minLength: minLen,
          temperature: isJsonMode ? 0.7 : 0.85,
          repeatPenalty: 1.15,
          minP: 0.05,
          topP: isJsonMode ? 0.90 : 0.95,
          reasoningEnabled: _reasoningEnabled,
          stopSequences: stops,
        ))) {
          if (_aborted || _generationEpoch != myEpoch) {
            _llmService.abortGeneration();
            break;
          }
          accumulated += token;
          tokenCount++;

          // Degenerate output detection — fires every 50 tokens for fast catch.
          // Two strategies:
          //   1. Substring repeat: a 300-char tail appears earlier in the text
          //   2. Word-salad: low unique-word ratio (model spewing random words)
          if (tokenCount > 100 && tokenCount % 50 == 0 && accumulated.length > 400) {
            // Strategy 1: exact substring repeat
            final tail = accumulated.substring(accumulated.length - 300);
            final earlier = accumulated.substring(0, accumulated.length - 300);
            if (earlier.contains(tail)) {
              debugPrint('CharacterGen: Repetition loop detected at token $tokenCount — aborting');
              repetitionDetected = true;
              break;
            }

            // Strategy 2: unique word ratio in the last ~500 chars
            final recentText = accumulated.length > 500
                ? accumulated.substring(accumulated.length - 500)
                : accumulated;
            final words = recentText.toLowerCase().split(RegExp(r'\s+'));
            if (words.length > 20) {
              final uniqueRatio = words.toSet().length / words.length;
              if (uniqueRatio < 0.30) {
                debugPrint('CharacterGen: Word-salad detected at token $tokenCount '
                    '(unique ratio: ${(uniqueRatio * 100).toStringAsFixed(1)}%) — aborting');
                repetitionDetected = true;
                break;
              }
            }
          }

          if (isJsonMode) {
            // Strip think blocks (fuzzy — models misspell <think> at high temp)
            final tOpen = r'<(?:think|thinking|thnk|thik|tink|thin|hink|ink)>';
            final tClose = r'</(?:think|thinking|thnk|thik|tink|thin|hink|ink)>';
            final stripped = accumulated
                .replaceAll(RegExp(tOpen + r'[\s\S]*?' + tClose, caseSensitive: false), '')
                .replaceAll(RegExp(tOpen + r'[\s\S]*$', caseSensitive: false), '')
                .trim();
            if (stripped.startsWith('{')) {
              int depth = 0;
              bool inString = false;
              bool complete = false;
              for (int ci = 0; ci < stripped.length; ci++) {
                final ch = stripped[ci];
                if (ch == '"' && (ci == 0 || stripped[ci - 1] != '\\')) {
                  inString = !inString;
                } else if (!inString) {
                  if (ch == '{') {
                    // Skip doubled {{ (template markers like {{char}})
                    if (ci + 1 < stripped.length && stripped[ci + 1] == '{') {
                      ci++; // skip the second {
                      continue;
                    }
                    depth++;
                  } else if (ch == '}') {
                    // Skip doubled }} (template markers like {{char}})
                    if (ci + 1 < stripped.length && stripped[ci + 1] == '}') {
                      ci++; // skip the second }
                      continue;
                    }
                    depth--;
                    if (depth == 0) { complete = true; break; }
                  }
                }
              }
              if (complete) break;
            }
          }

          if (onProgress != null) {
            String preview = accumulated;
            // Fuzzy think-tag stripping for preview
            final tO = r'<(?:think|thinking|thnk|thik|tink|thin|hink|ink)>';
            final tC = r'</(?:think|thinking|thnk|thik|tink|thin|hink|ink)>';
            preview = preview.replaceAll(RegExp(tO + r'[\s\S]*?' + tC), '');
            preview = preview.replaceAll(RegExp(tO + r'[\s\S]*$'), '');
            onProgress(preview.trim());
          }
        }

        if (_aborted || _generationEpoch != myEpoch) return null;

        debugPrint('CharacterGen: Stream done. Tokens: $tokenCount, '
            'Raw: ${accumulated.length} chars${repetitionDetected ? ' (truncated due to repetition)' : ''}');

        if (accumulated.isNotEmpty) return accumulated;

        // Empty response — retry with diagnostics
        debugPrint('CharacterGen: Empty response on attempt $attempt/$maxRetries. '
            'Prompt ~$promptEstTokens tokens. If this exceeds your model\'s context window, '
            'try a shorter concept or reduce lore depth.');
      } catch (e) {
        if (_aborted || _generationEpoch != myEpoch) return null;
        debugPrint('CharacterGen: LLM error on attempt $attempt/$maxRetries: $e');
      }

      // Wait before retrying (exponential backoff: 2s, 4s, 8s)
      if (attempt < maxRetries) {
        final delay = Duration(seconds: 2 * (1 << (attempt - 1)));
        debugPrint('CharacterGen: Retrying in ${delay.inSeconds}s...');
        onProgress?.call('[Retrying in ${delay.inSeconds}s... (attempt ${attempt + 1}/$maxRetries)]');
        final deadline = DateTime.now().add(delay);
        while (DateTime.now().isBefore(deadline)) {
          if (_aborted || _generationEpoch != myEpoch) return null;
          await Future.delayed(const Duration(milliseconds: 250));
        }
        onProgress?.call(''); // Clear retry message
      }
    }

    debugPrint('CharacterGen: All $maxRetries attempts failed');
    return null;
  }

  // ═════════════════════════════════════════════════════════════
  //  Truncation Recovery
  // ═════════════════════════════════════════════════════════════

  /// Generate only the missing fields after a truncated base card output.
  /// Uses a focused prompt with no lorebook/image_prompt to fit in limited context.
  Future<CharacterCard?> _recoverMissingFields({
    required String name,
    required String concept,
    required String personalityKeywords,
    required List<String> missingFields,
    String apiSystemPrompt = '',
    String age = '',
    String sex = '',
    String relationship = '',
    String backstory = '',
    void Function(String accumulated)? onProgress,
  }) async {
    final keywordsLine = personalityKeywords.isNotEmpty
        ? 'Personality keywords: $personalityKeywords\n'
        : '';
    final ageLine = age.isNotEmpty ? 'Age: $age\n' : '';
    final sexLine = sex.isNotEmpty ? 'Sex: $sex\n' : '';
    final relationshipLine = relationship.isNotEmpty
        ? 'Relationship to {{user}}: $relationship\n'
        : '';
    final backstoryLine = backstory.isNotEmpty
        ? 'Backstory: $backstory\n'
        : '';

    // Build spec only for the missing keys
    final fieldSpecs = <String>[];
    for (final field in missingFields) {
      switch (field) {
        case 'personality':
          fieldSpecs.add('- "personality": (string) 1-2 paragraphs, third person, core traits + motivations + quirks');
          break;
        case 'scenario':
          fieldSpecs.add('- "scenario": (string) 1 paragraph, the default conversation setting');
          break;
      }
    }

    final prompt = '''Generate ONLY the following fields for a roleplay character as a JSON object. Output ONLY the JSON, no markdown, no explanation.

Character name: $name
Concept: $concept
$ageLine$sexLine$relationshipLine$backstoryLine$keywordsLine
Required JSON keys:
${fieldSpecs.join('\n')}

Use {{char}} for character name and {{user}} for user name. Respond with ONLY the JSON:''';

    debugPrint('CharacterGen: Recovery prompt for ${missingFields.length} fields');

    final output = await _callLLM(prompt, maxLen: 4096, isJsonMode: true, onProgress: onProgress);
    if (output == null) return null;

    final cleaned = _stripContent(output);
    return _parseCharacterJson(cleaned, name);
  }

  /// Generate lorebook entries as a separate call.
  /// Accepts the interview transcript to ground entries in the character's world.
  Future<void> _generateLorebookSeparately({
    required CharacterCard card,
    required String name,
    required String concept,
    required List<String> loreCategories,
    required String loreDepth,
    String interviewTranscript = '',
    String? worldLore,
    void Function(String accumulated)? onProgress,
  }) async {
    String countRange;
    switch (loreDepth) {
      case 'Light':
        countRange = '3-4';
        break;
      case 'Deep':
        countRange = '10-15';
        break;
      default:
        countRange = '5-8';
    }
    final categoryHint = loreCategories.isNotEmpty
        ? ' Focus on: ${loreCategories.join(", ")}.'
        : '';

    // Build per-category descriptions when categories are selected
    String categoryGuidance = '';
    if (loreCategories.isNotEmpty) {
      final guides = <String>[];
      for (final cat in loreCategories) {
        final desc = _loreCategoryDescriptions[cat];
        if (desc != null) guides.add('- $cat: $desc');
      }
      if (guides.isNotEmpty) {
        categoryGuidance = '\n\nCATEGORY GUIDE (generate entries matching these types):\n${guides.join('\n')}';
      }
    }

    // When we have an interview transcript, surface the world details
    // the character described so entries feel grounded in this specific world.
    final interviewSection = interviewTranscript.isNotEmpty
        ? '\nWORLD VOICE — The character described their world in their own words. '
          'Let these details inform the texture and specificity of lorebook entries:\n'
          '${interviewTranscript.length > 1200 ? interviewTranscript.substring(0, 1200) + "..." : interviewTranscript}\n'
        : '';
        
    final loreSection = (worldLore != null && worldLore.trim().isNotEmpty)
        ? '\n[ESTABLISHED WORLD LORE]:\n$worldLore\n\n(IMPORTANT: Prioritize writing entries for specific factions, locations, names, and magic systems mentioned in the established lore text over inventing new ones.)\n'
        : '';

    final prompt = '''Generate WORLD-BUILDING lorebook entries for a roleplay setting. Output ONLY a JSON object with a single key "lorebook" containing an array of $countRange entry objects.$categoryHint

The character who lives in this world:
Name: $name
Concept: ${concept.length > 500 ? '${concept.substring(0, 500)}...' : concept}
${card.description.trim().isNotEmpty ? 'Description: ${card.description.length > 300 ? '${card.description.substring(0, 300)}...' : card.description}' : ''}
${card.scenario.trim().isNotEmpty ? 'Scenario: ${card.scenario}' : ''}$interviewSection$loreSection$categoryGuidance

CRITICAL RULES:
1. Entries MUST describe the WORLD — places, factions, customs, magic systems, creatures, world events, items, NPCs
2. Do NOT create entries about the character's personal history, backstory, childhood, relationships, or biography
3. Each entry should be something that EXISTS IN THE WORLD independently of the character
4. Keys should be common words/phrases a user would naturally type during roleplay (e.g. "tavern, inn, drink" not "The Gilded Chalice Tavern")
5. Content should be 1-2 paragraphs of rich, descriptive world lore — specific and evocative, not generic
6. If the interview mentioned specific places, customs, or factions, make entries for those first

Each entry format: {"name": "title", "key": "trigger,keywords", "content": "1-2 paragraphs of world lore"}

Output ONLY the JSON:''';

    final output = await _callLLM(prompt, maxLen: 4096, onProgress: onProgress);
    if (output == null) return;

    final cleaned = _stripContent(output);
    try {
      // Try direct parse
      Map<String, dynamic>? data;
      try {
        data = json.decode(cleaned) as Map<String, dynamic>;
      } catch (_) {
        // Try newline fix
        final fixed = _fixJsonNewlines(cleaned)
            .replaceAll(RegExp(r',\s*}'), '}')
            .replaceAll(RegExp(r',\s*]'), ']');
        data = json.decode(fixed) as Map<String, dynamic>;
      }

      final lorebookData = data['lorebook'];
      if (lorebookData is List && lorebookData.isNotEmpty) {
        final entries = <LorebookEntry>[];
        for (final entry in lorebookData) {
          if (entry is Map<String, dynamic>) {
            entries.add(LorebookEntry(
              name: entry['name']?.toString() ?? '',
              key: entry['key']?.toString() ?? '',
              content: entry['content']?.toString() ?? '',
              enabled: true,
            ));
          }
        }
        if (entries.isNotEmpty) {
          card.lorebook = Lorebook(entries: entries);
          debugPrint('CharacterGen: Separate lorebook generated ${entries.length} entries');
        }
      }
    } catch (e) {
      debugPrint('CharacterGen: Separate lorebook parse failed: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════
  //  Prompt Builders
  // ═════════════════════════════════════════════════════════════

  /// Build prompt for the base card (everything except greetings).
  String _buildBasePrompt({
    required String name,
    required String concept,
    String personalityKeywords = '',
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
    bool generateDescription = false,
    String? worldLore,
  }) {
    final keywordsLine = personalityKeywords.isNotEmpty
        ? 'Personality keywords: $personalityKeywords\n'
        : '';
    final ageLine = age.isNotEmpty ? 'Age: $age\n' : '';
    final sexLine = sex.isNotEmpty ? 'Sex: $sex\n' : '';
    final relationshipLine = relationship.isNotEmpty
        ? 'Relationship to {{user}}: $relationship\n'
        : '';
    final backstoryLine = backstory.isNotEmpty
        ? 'Backstory: $backstory\n'
        : '';
    final scenarioLine = scenario.isNotEmpty
        ? 'Scenario/Setting: $scenario\n'
        : '';
    final loreLine = (worldLore != null && worldLore.trim().isNotEmpty)
        ? '\n[ESTABLISHED WORLD LORE/RULES]:\n$worldLore\n(Must strictly adhere to the above facts, terminology, and locations)\n'
        : '';

    // Build lorebook spec with depth and categories
    String lorebookSpec = '';
    if (generateLorebook) {
      String countRange;
      switch (loreDepth) {
        case 'Light':
          countRange = '3-4';
          break;
        case 'Deep':
          countRange = '10-15';
          break;
        default:
          countRange = '5-8';
      }
      final categoryHint = loreCategories.isNotEmpty
          ? ' focusing on: ${loreCategories.join(", ")}'
          : '';
      lorebookSpec = '- "lorebook": (array of $countRange objects) WORLD-BUILDING entries$categoryHint. Each entry describes the WORLD (places, factions, customs, magic, creatures, events) — NOT the character\'s personal history or biography. Each: {"name": "title", "key": "trigger,keywords", "content": "1-2 paragraphs of world lore"}\n';
    }

    // System prompt is intentionally left blank — not generated by AI.
    // The user's active system prompt or API default applies at chat time.
    const sysSpec = '';

    // Description spec — only included for guided mode
    final descriptionSpec = generateDescription
        ? '- "description": (string) $descriptionDetail, third person. Physical appearance ONLY: body type, height, skin tone, hair, eyes, clothing, distinguishing marks. Do NOT put these in description: personality/motives (those go in "personality"), scenario/setting (goes in "scenario"), NSFW/sexual details, backstory, or speech patterns. STRICTLY obey the word limit\n'
        : '';

    // Description exclusion note — only when NOT generating description
    final descriptionNote = generateDescription
        ? ''
        : 'Do NOT generate a "description" key — the description is handled separately. ';

    // Key order: critical small fields FIRST so they survive output truncation.
    // Lorebook (the largest field) goes LAST so it gets clipped first if the
    // model runs out of output tokens — we can regenerate it separately.
    return '''Create a roleplay character card as a single JSON object following the Tavern V2 card format. Do NOT analyze, plan, or explain. Output ONLY the JSON object starting with { and ending with }. No markdown. No lists. Just raw JSON.

Character name: $name
Concept: $concept
$ageLine$sexLine$relationshipLine$backstoryLine$scenarioLine$keywordsLine$loreLine
Required JSON keys (generate them IN THIS ORDER):
${descriptionSpec}- "personality": (string) 1-2 paragraphs, third person. ONLY inner traits, social style, motives, quirks, and behavioral tics. Do NOT repeat physical appearance or scenario/setting info here — those belong in other fields
- "scenario": (string) 3-5 sentences. Synthesize a vivid opening scene that naturally emerges from the character's concept, backstory, personality, and relationship to {{user}}. Ground it in a specific place, time, and situation — include sensory details (lighting, sounds, atmosphere). Establish dramatic tension: what's at stake, what just happened, or what's about to happen that forces {{user}} and {{char}} to interact. This is stage direction for the opening moment, NOT a character summary. Do NOT restate personality traits or backstory — only the immediate scene
$sysSpec
- "tags": (array of strings) 3-5 relevant tags
$lorebookSpec
FIELD RULES:
- Keep each field focused — do NOT leak content between fields (e.g. personality in description, backstory in scenario)
- Balance token length across fields — no single field should dominate. Aim for ~500-2200 tokens total across description, personality, and scenario
- ${descriptionNote}Do NOT include first_message or alternate_greetings — those are generated separately
- Use {{char}} for character name and {{user}} for user name throughout

Respond with ONLY the JSON:''';
  }

  /// Build prompt for a single greeting message.
  String _buildGreetingPrompt({
    required String name,
    required String description,
    required String personality,
    required String scenario,
    required String length,
    required String tone,
    required List<String> previousGreetings,
    String characterContext = '',
    String userPersonaContext = '',
    String interviewTranscript = '',
    String? worldLore,
  }) {
    String lengthEnforcement;
    switch (length) {
      case 'Short (1-2 paragraphs)':
        lengthEnforcement = 'Write at least 100 words. Each paragraph should be 3-5 sentences minimum.';
        break;
      case 'Long (4-6 paragraphs)':
        lengthEnforcement = 'Write at least 500 words across 4-6 full paragraphs. Each paragraph MUST be 4-6 sentences. Include detailed scene-setting, inner monologue, environmental descriptions, and character mannerisms. DO NOT stop early or summarize. Fill the space with vivid, immersive prose.';
        break;
      default:
        lengthEnforcement = 'Write at least 250 words across 2-4 paragraphs. Each paragraph should be 3-5 sentences.';
    }

    String toneSpec = '';
    switch (tone) {
      case 'Romantic':
        toneSpec = '\nTone: Romantic — Warm intimacy, emotional vulnerability, longing glances, and heartfelt connection. Focus on the emotional bond between {{char}} and {{user}}. Include tender physical awareness (proximity, warmth, touch) without being explicit.';
        break;
      case 'Spicy/NSFW':
        toneSpec = '\nTone: Spicy/NSFW — Sensual tension, physical chemistry, and charged atmosphere. Include suggestive descriptions, body language, and desire. Be bold with attraction and intimacy. Push boundaries while keeping literary quality.';
        break;
      case 'Flirty/Playful':
        toneSpec = '\nTone: Flirty/Playful — Light teasing, witty banter, confident energy, and playful tension. {{char}} should be charming and a little daring. Include smirks, raised eyebrows, and double meanings. Keep it fun, not heavy.';
        break;
      case 'Wholesome':
        toneSpec = '\nTone: Wholesome — Warm, cozy, and comforting. Focus on kindness, gentle humor, and genuine care. Think shared meals, soft laughter, safe spaces. The greeting should feel like a warm blanket — inviting and safe.';
        break;
      case 'Slice of Life':
        toneSpec = '\nTone: Slice of Life — Everyday mundane moments made interesting. Casual, grounded, realistic. Focus on small details: morning routines, grocery shopping, waiting for the bus. Beauty in the ordinary.';
        break;
      case 'Story/Narrative':
        toneSpec = '\nTone: Story/Narrative — Rich literary prose with strong scene-setting. Open like a novel chapter with atmospheric description, inner monologue, and world-building. Prioritize immersion and vivid imagery over action.';
        break;
      case 'Adventure':
        toneSpec = '\nTone: Adventure — Excitement, exploration, and the thrill of the unknown. {{char}} is in motion — discovering something, embarking on a journey, or inviting {{user}} along for the ride. High energy, forward momentum, wonder.';
        break;
      case 'Combat/Action':
        toneSpec = '\nTone: Combat/Action — Adrenaline, danger, and physical intensity. Open mid-fight, mid-chase, or in the aftermath of violence. Sharp pacing, visceral descriptions, and tactical awareness. {{char}} is in their element.';
        break;
      case 'Comedy/Humor':
        toneSpec = '\nTone: Comedy/Humor — Genuinely funny. Include witty observations, absurd situations, comic timing, or self-deprecating humor. {{char}} should make {{user}} want to laugh. Avoid being cringey — aim for clever over random.';
        break;
      case 'Suspense/Thriller':
        toneSpec = '\nTone: Suspense/Thriller — Tension, urgency, and unease. Something is wrong or about to go wrong. Use short sentences for pacing, environmental unease, and a sense that time is running out. End with a hook that demands a response.';
        break;
      case 'Dark/Mystery':
        toneSpec = '\nTone: Dark/Mystery — Brooding atmosphere, secrets, and moral ambiguity. Shadows, whispered conversations, hidden motives. {{char}} knows something {{user}} doesn\'t — or vice versa. Atmospheric and ominous.';
        break;
      case 'Melancholy':
        toneSpec = '\nTone: Melancholy — Bittersweet, introspective, and emotionally heavy. Focus on loss, nostalgia, quiet pain, or fading hope. Beautiful sadness. The greeting should ache a little — poetic but not melodramatic.';
        break;
      default: // 'Neutral'
        toneSpec = '';
    }

    final previousContext = previousGreetings.isNotEmpty
        ? '\n\nIMPORTANT: The following greetings have ALREADY been written. Write something COMPLETELY DIFFERENT — a new scenario, new setting, new mood. Do NOT repeat or paraphrase these:\n---\n${previousGreetings.map((g) => g.length > 200 ? '${g.substring(0, 200)}...' : g).join('\n---\n')}\n---'
        : '';

    // Build persona context section
    String personaSection;
    if (userPersonaContext.isNotEmpty) {
      personaSection = '''

{{user}} Persona (for context — you may reference these traits but NEVER act as {{user}}):
$userPersonaContext''';
    } else {
      personaSection = '';
    }

    // Build character context section
    String characterSection = '';
    if (characterContext.isNotEmpty) {
      characterSection = '''

Character Details (weave these naturally into the scene — SHOW through action, environment, and description, don't just list them):
$characterContext''';
    }

    // Inject interview transcript as voice reference — capped to avoid bloating context.
    // The LLM uses this to match the cadence, vocabulary, and emotional register
    // already established in the interview rather than inventing a new voice.
    String voiceSection = '';
    if (interviewTranscript.isNotEmpty) {
      final excerpt = interviewTranscript.length > 1000
          ? interviewTranscript.substring(0, 1000) + '...'
          : interviewTranscript;
      voiceSection = '''

== ESTABLISHED VOICE ==
The following are $name's own words from an in-character interview. Match this exact voice, vocabulary, cadence, and emotional register when writing the greeting — do NOT invent a different tone:
$excerpt''';
    }
    
    String loreSection = '';
    if (worldLore != null && worldLore.trim().isNotEmpty) {
      loreSection = '\n\n== ESTABLISHED WORLD LORE ==\nThe scene is taking place in this world. Strictly follow its rules, terminology, magic, and locations:\n$worldLore';
    }

    return '''Write an opening roleplay message as $name (first person: "I", "my", "me"). This is the very first moment of the story — set the scene and introduce who $name is through vivid prose. Output ONLY the message text.

== WHO $name IS ==
Description: $description
Personality: $personality
Scenario: $scenario$characterSection$personaSection$voiceSection$loreSection
$toneSpec

== NARRATIVE STRUCTURE (follow this order) ==
1. SCENE — Open with the environment. Where are we? What time of day? What's the atmosphere? Paint the world with sensory detail (sights, sounds, smells, textures). Minimum 1 full paragraph of scene-setting.
2. CHARACTER — Describe $name's physical appearance through action. Show race/species features, body, clothing, hair, distinguishing marks AS $name moves through the scene. The reader should be able to picture $name vividly. Minimum 1 full paragraph focused on $name's appearance and mannerisms.
3. CONTEXT — Through inner monologue, establish HOW $name and {{user}} know each other and WHY they are meeting. Weave in relevant backstory: How did they meet? How long have they known each other? What is their relationship? What does $name expect from this encounter? The reader should fully understand the situation WITHOUT having read any other character card fields. This section is CRITICAL — do NOT skip it.
4. ENCOUNTER — The moment $name notices or interacts with {{user}}. Include inner thoughts, emotional reactions, and end with spoken dialogue that invites {{user}} to respond. The dialogue MUST be consistent with the Scenario and the context established above — reference shared history, inside jokes, or established dynamics.

== RULES ==
- First person ONLY ("I", "my", "me") — never third person, never use "$name" to refer to yourself
- *Asterisks* for physical actions only. "Quotes" for dialogue. Plain text for narration/thoughts/description.
- Use {{user}} (with curly braces) when mentioning the other person — never vague references like "the stranger"
- NEVER write actions, thoughts, feelings, appearance, or dialogue for {{user}} — {{user}} is a blank slate
- Do NOT start the message by addressing {{user}} — start with scene description
- ALL dialogue and actions MUST be consistent with the Scenario. Do NOT contradict established facts

== LENGTH ==
$lengthEnforcement
This is MANDATORY — do NOT write less. Fill the space with rich, immersive prose.$previousContext

Begin:''';
  }

  /// Clean raw greeting output — remove quotes, labels, fix truncation.
String _cleanGreeting(String raw) {
  String cleaned = raw.trim();

  // Remove wrapping quotes if present
  if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
    cleaned = cleaned.substring(1, cleaned.length - 1);
  }

  // Remove common leading labels
  cleaned = cleaned
      .replaceAll(RegExp(r'^(First message|Opening message|Greeting):?\s*', caseSensitive: false), '')
      .trim();

  return cleaned;
}

/// Check if a greeting was truncated (cut off mid-sentence).
bool _isGreetingTruncated(String text) {
  if (text.isEmpty) return true;
  final trimmed = text.trimRight();
  if (trimmed.isEmpty) return true;

  // Check for unclosed formatting
  final asteriskCount = '*'.allMatches(trimmed).length;
  if (asteriskCount % 2 != 0) return true; // Unclosed *asterisk*
  final quoteCount = '"'.allMatches(trimmed).length;
  if (quoteCount % 2 != 0) return true; // Unclosed "quote"

  // Check if it ends with proper sentence-ending punctuation
  final lastChar = trimmed[trimmed.length - 1];
  final endsWithPunctuation = '.!?*"\u201D'.contains(lastChar);
  if (!endsWithPunctuation) return true;

  return false;
}

/// Editor pass: complete a truncated greeting.
Future<String?> editorCompletionPass(String greeting, {void Function(String)? onProgress}) async {
  if (greeting.trim().isEmpty) return null;
  if (!_isGreetingTruncated(greeting)) return null; // Not truncated

  final prompt = '''OUTPUT FORMAT: Respond with ONLY the complete greeting text. Your entire response must be the greeting and nothing else. Do NOT include analysis, reasoning, or commentary.

TASK: This greeting was cut off mid-sentence. Complete it naturally. Write the ENTIRE greeting from the beginning (copy the existing text) and add just enough to finish the final thought properly. Do NOT add significant new content — just complete the sentence/paragraph that was cut off.

FORMATTING:
- *Asterisks* ONLY for physical actions
- "Quotation marks" for spoken dialogue
- Plain text for narration and description
- Maintain the same voice, tense, and style

TRUNCATED GREETING:
$greeting''';

  final result = await _callLLM(prompt, maxLen: 4096, minLen: 128, onProgress: onProgress);
  if (result != null && result.trim().isNotEmpty) {
    final cleaned = _cleanEditorOutput(result);
    // Only accept if it's at least as long as original (completion, not replacement)
    if (cleaned.length >= greeting.length * 0.9) {
      return cleaned;
    }
  }
  return null;
}
  // ═════════════════════════════════════════════════════════════
  //  Editor Passes
  // ═════════════════════════════════════════════════════════════

  /// Anti-puppet check: find and fix lines that describe {{user}}.
  Future<String?> editorAntiPuppetCheck(String greeting, {void Function(String)? onProgress}) async {
    if (greeting.trim().isEmpty) return null;

    final prompt = '''OUTPUT FORMAT: Respond with ONLY the corrected greeting text. Start immediately with the first word of the greeting (usually *). Do NOT include analysis, reasoning, line-by-line breakdown, numbered lists, explanations of changes, or any other commentary. Your entire response must be the greeting and nothing else.

TASK: Fix "puppeting" in this greeting. Puppeting = describing {{user}}'s actions, thoughts, feelings, appearance, body, or dialogue.

FIXES TO APPLY:
- "you feel nervous" → rephrase as {{char}}'s observation or delete
- "your heart races" → delete
- "your hair / your eyes / your jaw" → delete physical descriptions of {{user}}
- "your movements fluid" → delete or rephrase as {{char}}'s impression
- "you sit down" → let {{char}} gesture to a seat instead
- If NO puppeting exists, return the greeting UNCHANGED

FORMATTING — PRESERVE EXACTLY:
- *Asterisks* ONLY for physical actions (things the character does)
- "Quotation marks" for spoken dialogue
- Plain text for narration, description, and inner thoughts — no special formatting
- Keep same length, tone, style. Rephrase from {{char}}'s perspective.

$greeting''';

    final result = await _callLLM(prompt, maxLen: 4096, minLen: 128, onProgress: onProgress);
    if (result != null && result.trim().isNotEmpty) {
      final cleaned = _cleanEditorOutput(result);
      if (cleaned.length > greeting.length * 0.4) {
        return cleaned;
      }
    }
    return null;
  }

  /// Consistency check: verify greeting matches character profile.
  Future<String?> editorConsistencyCheck(
    String greeting,
    String description,
    String personality,
    String scenario, {
    void Function(String)? onProgress,
  }) async {
    if (greeting.trim().isEmpty) return null;

    final prompt = '''OUTPUT FORMAT: Respond with ONLY the corrected greeting text. Start immediately with the first word of the greeting (usually *). Do NOT include analysis, reasoning, or any commentary. Your entire response must be the greeting and nothing else.

TASK: Check this greeting for consistency with the character profile. Fix contradictions in personality, appearance, setting, or tone. If consistent, return UNCHANGED.

FORMATTING — PRESERVE EXACTLY:
- *Asterisks* ONLY for physical actions (things the character does)
- "Quotation marks" for spoken dialogue
- Plain text for narration, description, and inner thoughts — no special formatting

CHARACTER: $description | $personality | $scenario

$greeting''';

    final result = await _callLLM(prompt, maxLen: 4096, minLen: 128, onProgress: onProgress);
    if (result != null && result.trim().isNotEmpty) {
      final cleaned = _cleanEditorOutput(result);
      if (cleaned.length > greeting.length * 0.4) {
        return cleaned;
      }
    }
    return null;
  }

  /// Quality polish: improve prose quality and immersiveness.
  Future<String?> editorQualityPolish(String greeting, {void Function(String)? onProgress}) async {
    if (greeting.trim().isEmpty) return null;

    final prompt = '''OUTPUT FORMAT: Respond with ONLY the polished greeting text. Start immediately with the first word of the greeting (usually *). Do NOT include analysis, reasoning, or any commentary. Your entire response must be the greeting and nothing else.

TASK: Polish this greeting's prose. Improve vivid descriptions, sensory details, sentence rhythm, immersiveness. Keep same meaning, length, voice, and {{user}}/{{char}} placeholders. NEVER add puppeting of {{user}}.

FORMATTING — ENFORCE STRICTLY:
- *Asterisks* ONLY for physical actions (things the character does)
- "Quotation marks" for spoken dialogue
- Plain text for narration, description, and inner thoughts — no special formatting
- If narration is incorrectly wrapped in *asterisks*, unwrap it to plain text

$greeting''';

    final result = await _callLLM(prompt, maxLen: 4096, minLen: 128, onProgress: onProgress);
    if (result != null && result.trim().isNotEmpty) {
      final cleaned = _cleanEditorOutput(result);
      if (cleaned.length > greeting.length * 0.4) {
        return cleaned;
      }
    }
    return null;
  }

  /// Strip analysis preamble/postamble from editor output.
  /// Models often include reasoning/analysis before the actual corrected greeting.
  String _cleanEditorOutput(String raw) {
    String text = _stripContent(raw).trim();

    // Strategy 1: Look for explicit section markers that precede the actual greeting.
    // The actual greeting typically follows markers like "polished version:", etc.
    final sectionMarkers = RegExp(
      r'(polished version|corrected version|corrected greeting|revised greeting|'
      r'polished greeting|here is the|here.s the|the polished|the corrected|'
      r'now let me write|final version|edited version|cleaned version|'
      r'output:|result:)\s*:?\s*$',
      caseSensitive: false,
      multiLine: true,
    );
    final markerMatch = sectionMarkers.allMatches(text).lastOrNull;
    if (markerMatch != null) {
      final afterMarker = text.substring(markerMatch.end).trim();
      if (afterMarker.isNotEmpty) {
        text = afterMarker;
      }
    }

    // Strategy 2: If text still has analysis lines (Current:, Enhancement:, Line X:, etc.)
    // split into paragraphs and keep only the ones that look like prose, not analysis.
    final analysisLinePattern = RegExp(
      r'^(Current:|Enhancement:|Original:|Revised?:|Rewrite:|'
      r'Line \d|Paragraph \d|Instance \d|\d+\.\s+"|\d+\.\s+\*|'
      r'- ".*" →|Check:|Note:|Summary:|Wait,|Actually,|Let me|Looking at|'
      r'So the|I need to|Better:|Try:|Hmm|The issue|'
      r'Enhancement|puppeting|This is)',
      caseSensitive: false,
    );

    final lines = text.split('\n');
    bool hasAnalysis = lines.any((l) => analysisLinePattern.hasMatch(l.trim()));

    if (hasAnalysis) {
      // Find the last large block of consecutive non-analysis lines
      List<String> bestBlock = [];
      List<String> currentBlock = [];

      for (final line in lines) {
        if (analysisLinePattern.hasMatch(line.trim()) || 
            (line.trim().isEmpty && currentBlock.isEmpty)) {
          // Analysis line or leading blank — save best block and reset
          if (currentBlock.length > bestBlock.length) {
            bestBlock = List.from(currentBlock);
          }
          currentBlock = [];
        } else {
          currentBlock.add(line);
        }
      }
      // Check final block
      if (currentBlock.length > bestBlock.length) {
        bestBlock = currentBlock;
      }

      if (bestBlock.length >= 3) {
        text = bestBlock.join('\n');
      }
    }

    // Strategy 3: Strip any remaining trailing analysis
    final trailingAnalysis = RegExp(
      r'\n\s*(Note:|Summary:|Changes? made|I (?:changed|removed|fixed|revised)|'
      r'The (?:changes|edits|fixes)|Wait,|Actually,|Let me check)[\s\S]*$',
      caseSensitive: false,
    );
    text = text.replaceAll(trailingAnalysis, '');

    return _cleanGreeting(text.trim());
  }

  // ═════════════════════════════════════════════════════════════
  //  Content Stripping
  // ═════════════════════════════════════════════════════════════

  /// Strip thinking tags, markdown wrappers, and other LLM artifacts.
  String _stripContent(String raw) {
    return JsonSanitizer.sanitize(raw);
  }

  // ═════════════════════════════════════════════════════════════
  //  JSON Parsing (with multiple fallback strategies)
  // ═════════════════════════════════════════════════════════════

  /// Parse the cleaned JSON into a [CharacterCard].
  /// Tries three strategies: direct decode → newline fix → regex extraction.
  CharacterCard? _parseCharacterJson(String jsonStr, String fallbackName) {
    // Strategy 1: Direct JSON parse
    try {
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      debugPrint('CharacterGen: Direct JSON parse succeeded');
      return _buildCard(data, fallbackName);
    } catch (e) {
      debugPrint('CharacterGen: Direct parse failed: $e');
    }

    // Strategy 2: Fix newlines inside strings
    try {
      String fixed = _fixJsonNewlines(jsonStr);
      fixed = fixed
          .replaceAll(RegExp(r',\s*}'), '}')
          .replaceAll(RegExp(r',\s*]'), ']');
      final data = json.decode(fixed) as Map<String, dynamic>;
      debugPrint('CharacterGen: Newline-fixed parse succeeded');
      return _buildCard(data, fallbackName);
    } catch (e) {
      debugPrint('CharacterGen: Newline-fixed parse failed: $e');
    }

    // Strategy 3: Regex-based extraction (handles unescaped quotes in prose)
    try {
      final data = _regexExtract(jsonStr);
      if (data.isNotEmpty) {
        debugPrint('CharacterGen: Regex extraction succeeded (${data.length} keys)');
        return _buildCard(data, fallbackName);
      }
    } catch (e) {
      debugPrint('CharacterGen: Regex extraction failed: $e');
    }

    debugPrint('CharacterGen: All parse strategies failed');
    return null;
  }

  /// Regex-based key extraction for malformed JSON.
  ///
  /// Since we know the expected keys, we find each key and extract
  /// the value text between keys. This handles unescaped quotes,
  /// literal newlines, and other LLM mangling.
  Map<String, dynamic> _regexExtract(String raw) {
    final result = <String, dynamic>{};
    final knownKeys = [
      'description', 'personality', 'scenario', 'first_message',
      'alternate_greetings', 'example_dialogue', 'system_prompt',
      'tags', 'image_prompt', 'lorebook',
    ];

    for (int i = 0; i < knownKeys.length; i++) {
      final key = knownKeys[i];
      // Find "key": or "key" :
      final keyPattern = RegExp('"$key"\\s*:\\s*');
      final keyMatch = keyPattern.firstMatch(raw);
      if (keyMatch == null) continue;

      final valueStart = keyMatch.end;

      // Determine if value is a string, array, or other
      final firstChar = raw.substring(valueStart).trimLeft();
      if (firstChar.startsWith('[')) {
        // Array value — find matching ]
        final arrStart = raw.indexOf('[', valueStart);
        final arrEnd = _findMatchingBracket(raw, arrStart, '[', ']');
        if (arrEnd > arrStart) {
          final arrStr = raw.substring(arrStart, arrEnd + 1);
          try {
            // Fix newlines and attempt parse
            final fixed = _fixJsonNewlines(arrStr)
                .replaceAll(RegExp(r',\s*]'), ']');
            result[key] = json.decode(fixed);
          } catch (_) {
            // Fall back to splitting on simple patterns
            result[key] = _extractArrayStrings(arrStr);
          }
        }
      } else if (firstChar.startsWith('"')) {
        // String value — find end by looking for next known key or end of object
        final strStart = raw.indexOf('"', valueStart);
        String? value = _extractStringValue(raw, strStart, knownKeys, i);
        if (value != null) {
          result[key] = value;
        }
      }
    }

    return result;
  }

  /// Extract a string value starting at [start] (the opening quote).
  /// Looks for the next known key as the boundary.
  String? _extractStringValue(String raw, int start, List<String> keys, int currentIdx) {
    if (start < 0 || start >= raw.length) return null;

    // Look past the opening quote
    final contentStart = start + 1;

    // Find the end by looking for the next key pattern or closing brace
    int? nextBoundary;
    for (int j = currentIdx + 1; j < keys.length; j++) {
      final nextKeyPattern = RegExp('"${keys[j]}"\\s*:');
      final nextMatch = nextKeyPattern.firstMatch(raw.substring(contentStart));
      if (nextMatch != null) {
        nextBoundary = contentStart + nextMatch.start;
        break;
      }
    }

    // If no next key found, look for final }
    nextBoundary ??= raw.lastIndexOf('}');
    if (nextBoundary <= contentStart) return null;

    // Extract and clean the value
    var value = raw.substring(contentStart, nextBoundary);

    // Strip trailing: comma, quote, whitespace
    value = value.replaceAll(RegExp(r'[\s,]*"?\s*,?\s*$'), '');
    // Strip trailing quote
    if (value.endsWith('"')) value = value.substring(0, value.length - 1);

    // Unescape JSON escapes
    value = value
        .replaceAll('\\n', '\n')
        .replaceAll('\\t', '\t')
        .replaceAll('\\"', '"')
        .replaceAll('\\\\', '\\');

    return value.trim();
  }

  /// Extract string items from a JSON array that may have malformed quotes.
  List<String> _extractArrayStrings(String arrStr) {
    final results = <String>[];
    // Remove brackets
    var inner = arrStr.trim();
    if (inner.startsWith('[')) inner = inner.substring(1);
    if (inner.endsWith(']')) inner = inner.substring(0, inner.length - 1);

    // Split on ", " pattern (quotes followed by comma)
    final parts = inner.split(RegExp(r'"\s*,\s*"'));
    for (var part in parts) {
      part = part.trim();
      if (part.startsWith('"')) part = part.substring(1);
      if (part.endsWith('"')) part = part.substring(0, part.length - 1);
      if (part.isNotEmpty) results.add(part);
    }
    return results;
  }

  /// Find matching closing bracket, accounting for nesting.
  int _findMatchingBracket(String s, int start, String open, String close) {
    int depth = 0;
    bool inStr = false;
    for (int i = start; i < s.length; i++) {
      final ch = s[i];
      if (ch == '"' && (i == 0 || s[i - 1] != '\\')) {
        inStr = !inStr;
      } else if (!inStr) {
        if (ch == open) depth++;
        if (ch == close) {
          depth--;
          if (depth == 0) return i;
        }
      }
    }
    return -1;
  }

  /// Build a [CharacterCard] from parsed JSON data, including lorebook.
  CharacterCard _buildCard(Map<String, dynamic> data, String fallbackName) {
    final card = CharacterCard(
      name: fallbackName,
      description: _getString(data, 'description'),
      personality: _getString(data, 'personality'),
      scenario: _getString(data, 'scenario'),
      firstMessage: _getString(data, 'first_message'),
      mesExample: _getString(data, 'example_dialogue'),
      systemPrompt: _getString(data, 'system_prompt'),
      alternateGreetings: _getStringList(data, 'alternate_greetings'),
      tags: _getStringList(data, 'tags'),
    );

    // Parse lorebook entries if present
    final lorebookData = data['lorebook'];
    if (lorebookData is List && lorebookData.isNotEmpty) {
      final entries = <LorebookEntry>[];
      for (final entry in lorebookData) {
        if (entry is Map<String, dynamic>) {
          entries.add(LorebookEntry(
            name: entry['name']?.toString() ?? '',
            key: entry['key']?.toString() ?? '',
            content: entry['content']?.toString() ?? '',
            enabled: true,
          ));
        }
      }
      if (entries.isNotEmpty) {
        card.lorebook = Lorebook(entries: entries);
        debugPrint('CharacterGen: Parsed ${entries.length} lorebook entries');
      }
    }

    return card;
  }

  /// Fix literal newlines/tabs inside JSON string values.
  String _fixJsonNewlines(String input) {
    final buf = StringBuffer();
    bool inString = false;
    for (int i = 0; i < input.length; i++) {
      final ch = input[i];

      if (ch == '"' && (i == 0 || input[i - 1] != '\\')) {
        inString = !inString;
        buf.write(ch);
      } else if (inString) {
        switch (ch) {
          case '\n':
            buf.write('\\n');
            break;
          case '\r':
            buf.write('\\r');
            break;
          case '\t':
            buf.write('\\t');
            break;
          default:
            buf.write(ch);
        }
      } else {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  /// Safely extract a String from a JSON map.
  String _getString(Map<String, dynamic> data, String key) {
    final val = data[key];
    if (val is String) return val;
    if (val != null) return val.toString();
    return '';
  }

  /// Safely extract a List<String> from a JSON map.
  /// Strips whitespace and newlines from each element.
  List<String> _getStringList(Map<String, dynamic> data, String key) {
    final val = data[key];
    if (val is List) {
      return val
          .map((e) => e.toString().replaceAll(RegExp(r'[\n\r]+'), ' ').trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  }

  /// Generates a tailored, highly specific image prompt based on the FINAL character card.
  /// Grounds the prompt heavily in the character's physical description and current scenario.
  Future<String?> _generateImagePrompt({
    required String name,
    required String description,
    required String scenario,
    required String artStyle,
    required String imageGenPromptParadigm,
    void Function(String)? onProgress,
  }) async {
    final formatInstruction = imageGenPromptParadigm == 'tags'
        ? 'Output ONLY flat comma-separated visual tags. NO prose, NO sentences, NO names. ONLY tags in this format: "skin tone, gender, hair color + style, eye color, body type, outfit pieces, pose, setting, expression, lighting, camera angle, $artStyle style". Keep under 60 words.'
        : 'Output A rich, natural language descriptive paragraph detailing the character\'s physical appearance in the scene. Do NOT use comma-separated tags. Do NOT use names. Keep under 100 words. Describe the scene as a $artStyle style illustration.';

    final prompt = '''Write an image generation prompt for an illustration of this character.
You MUST follow the requested format perfectly. Do NOT include introductory text, markdown, or JSON. Just the raw prompt string.

== CONTEXT ==
Character description: $description
Current scenario setting: $scenario

== INSTRUCTIONS ==
Ground the image entirely in the visual details from the description, and use the scenario to dictate the background environment, lighting, and pose. Do NOT use the character's name in the output.

$formatInstruction

Begin:''';

    final output = await _callLLM(prompt, maxLen: 1024, minLen: 20, onProgress: onProgress);
    if (output == null) return null;
    
    // Clean string just in case
    return output.trim().replaceAll(RegExp(r'^"|"$'), '').trim();
  }
}
