// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../character_gen_service.dart';

extension GenSteps on CharacterGenService {
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

    final prompt =
        '''Generate exactly $count completely different meeting scenarios for a roleplay character. Each scenario is where {{user}} and $name first encounter each other — or meet again in an unexpected context.

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

    final output = await _callLLM(
      prompt,
      maxLen: 1024,
      minLen: 100,
      isJsonMode: true,
      onProgress: onProgress,
    );
    if (output == null) {
      debugPrint(
        'CharacterGen: Alt scenario generation failed — using default scenario for all alts',
      );
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
      debugPrint(
        'CharacterGen: Alt scenario parse failed: $e — using default for all alts',
      );
    }
    return [];
  }

  // ═════════════════════════════════════════════════════════════
  //  Character Interview (Voice Enrichment)
  // ═════════════════════════════════════════════════════════════

  /// Run a cumulative in-character interview, returning the full transcript.
  /// Each answer is folded back into the next question's context — exactly as
  /// EllipsisLM does — so the model's "voice" deepens with each turn.
  /// When [nsfwEnabled] is true, an explicit sexual preference question is appended.
  Future<String> _runCharacterInterview({
    required CharacterCard card,
    required String name,
    bool nsfwEnabled = false,
    String relationship = '',
    void Function(String)? onStatus,
    void Function(String)? onProgress,
    String? worldLore,
  }) async {
    final transcript = StringBuffer();
    // Seed the LLM with who this character is so the first answer is grounded
    final seed =
        'You are $name.\n'
        'Your personality: ${card.personality.length > 400 ? card.personality.substring(0, 400) : card.personality}\n'
        'Your scenario: ${card.scenario.length > 200 ? card.scenario.substring(0, 200) : card.scenario}\n\n'
        '${worldLore != null && worldLore.trim().isNotEmpty ? "You exist in the following established world. Use its terminology, locations, and facts:\n$worldLore\n\n" : ""}'
        'Answer each question in first person, fully in-character. Be specific, '
        'vivid, and emotionally honest — but keep each answer TIGHT: a few sharp '
        'sentences, under ~150 words. Depth over length; do not ramble. Respond '
        'as $name would speak — use their vocabulary, cadence, and emotional '
        'register.';

    // Skip the relationship question for strangers/one-shots — inventing shared
    // history (what they want from {{user}}, unspoken tension) actively hurts a
    // "you just met" card. Empty OR a stranger-like preset counts as no relationship.
    final relLower = relationship.trim().toLowerCase();
    final hasRelationship = relLower.isNotEmpty &&
        relLower != 'stranger' &&
        relLower != 'strangers' &&
        relLower != 'none';

    // Voice → motive → wound → (relationship) → social → pressure → joy →
    // (NSFW) → appearance. See the question constants for the rationale.
    final questions = <String>[
      _qVoice,
      _qWho,
      _qWound,
      if (hasRelationship) _relationshipQuestion(relationship),
      _qSocial,
      _qPressure,
      _qJoy,
      if (nsfwEnabled) _nsfwInterviewQuestion,
      _qAppearance,
    ];

    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      onStatus?.call('Character interview (${i + 1}/${questions.length})...');
      onProgress?.call('');

      final prompt =
          '$seed\n\n'
          '${transcript.isNotEmpty ? 'Previous answers:\n$transcript\n\n' : ''}'
          'Question: $q\n\n'
          '$name: ';

      // Tight cap: interview answers used to run to ~1200 tokens each, ballooning
      // the cumulative prompt to ~12k by the last question (slow on local models).
      // A few sharp sentences is all the enrichment/voice steps need.
      final answer = await _callLLM(
        prompt,
        maxLen: 350,
        minLen: 50,
        onProgress: onProgress,
      );
      if (answer == null || answer.trim().isEmpty) {
        debugPrint(
          'CharacterGen: Interview Q${i + 1} got empty answer — skipping',
        );
        continue;
      }

      // Strip any think blocks from the answer before adding to transcript
      final cleanAnswer = answer
          .replaceAll(
            RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
            '',
          )
          .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
          .trim();

      transcript.writeln('Q: $q');
      transcript.writeln('A: $cleanAnswer');
      transcript.writeln();
      debugPrint(
        'CharacterGen: Interview Q${i + 1} answered (${cleanAnswer.length} chars)',
      );
    }

    return transcript.toString().trim();
  }

  /// Use the completed interview transcript to rewrite description, personality,
  /// AND scenario with richer, voice-consistent prose grounded in the character's
  /// own words (the scenario keeps its setup but gains the revealed stakes +
  /// relationship texture). Example dialogue is a separate dedicated step.
  Future<void> _enrichCardFromInterview({
    required CharacterCard card,
    required String name,
    required String interviewTranscript,
    bool preserveUserScenario = false,
    void Function(String)? onProgress,
  }) async {
    final prompt =
        '''
You have just completed an in-character interview with $name.
Using the interview answers below as your source of truth, rewrite these three fields
for this character card. Output ONLY a JSON object with exactly three keys.
No markdown. No explanation. Just raw JSON.

INTERVIEW TRANSCRIPT:
$interviewTranscript

CURRENT DESCRIPTION (physical appearance only):
${card.description}

CURRENT PERSONALITY (inner traits):
${card.personality}

CURRENT SCENARIO (the opening situation — keep its setup):
${card.scenario}

Rewrite these fields using the specific details, voice, and texture revealed in the interview:

- "description": (string) Third-person. Physical appearance ONLY: body, face, hair, eyes, clothing, posture, distinguishing marks. Use specific concrete details that emerged in the interview — not generic adjectives like "beautiful" or "attractive." Replace vague descriptors with precise ones ("calloused hands" not "strong hands", "a crooked nose from an old break" not "an interesting face"). 2-3 paragraphs. Do NOT include personality, backstory, or scenario.
- "personality": (string) Third-person. Write 2-3 rich paragraphs covering ALL of the following dimensions:
  * Core traits and their contradictions (e.g. "fiercely loyal but slow to trust")
  * Speech patterns and verbal habits (catchphrases, how they curse, whether they ramble or speak tersely)
  * Emotional triggers — what makes them angry, what softens them, what makes them shut down
  * How they behave differently around strangers vs. people they trust
  * Defense mechanisms — how they protect themselves emotionally
  * A distinctive behavioral quirk or habit that makes them memorable
  Ground every trait in what the character actually revealed in the interview. Do NOT repeat physical appearance or scenario.
- "scenario": (string) Keep the SAME situation, place, and time as the CURRENT SCENARIO above — do NOT relocate or restart the story. Sharpen it with what the interview revealed: the immediate stakes and tension, and (when a relationship exists) what {{char}} wants from {{user}} right now and what is unspoken between them. This is stage-direction for the opening moment — end on a clear dramatic question that gives {{user}} a reason to respond. 2-4 sentences. Do NOT restate personality or physical appearance.

Use {{char}} for the character name and {{user}} for the user throughout.

Respond with ONLY the JSON:''';

    final output = await _callLLM(
      prompt,
      maxLen: 4096,
      minLen: 200,
      isJsonMode: true,
      onProgress: onProgress,
    );
    if (output == null) {
      debugPrint(
        'CharacterGen: Interview enrichment got no response — keeping original fields',
      );
      return;
    }

    final cleaned = _stripContent(output);
    debugPrint(
      'CharacterGen: Enrichment output cleaned (${cleaned.length} chars)',
    );

    // Use regex extraction instead of json.decode — models routinely output
    // unescaped quotes (5'9", etc.) that break strict JSON parsing. The regex
    // extractor finds values by key boundaries, handling all malformed output.
    final data = _regexExtract(cleaned);
    debugPrint(
      'CharacterGen: Enrichment extracted keys: ${data.keys.toList()}',
    );

    final newDesc = (data['description']?.toString() ?? '').trim();
    final newPers = (data['personality']?.toString() ?? '').trim();

    if (newDesc.isNotEmpty && newDesc.length >= card.description.length * 0.5) {
      card.description = newDesc;
      debugPrint(
        'CharacterGen: Description enriched (${newDesc.length} chars)',
      );
    }
    if (newPers.isNotEmpty && newPers.length >= card.personality.length * 0.5) {
      card.personality = newPers;
      debugPrint(
        'CharacterGen: Personality enriched (${newPers.length} chars)',
      );
    }
    // Scenario is intentionally CONCISE (2-4 sentences) so it can be shorter
    // than the base — use an absolute floor, not the 0.5x ratio, to accept a
    // tight rewrite while still rejecting an empty/garbage response. Never touch
    // a scenario the USER wrote verbatim (a local model would drift it).
    final newScenario = (data['scenario']?.toString() ?? '').trim();
    if (!preserveUserScenario && newScenario.length >= 60) {
      card.scenario = newScenario;
      debugPrint(
        'CharacterGen: Scenario enriched (${newScenario.length} chars)',
      );
    }
  }

  /// Generate example dialogue as a dedicated step using the interview transcript.
  /// Outputs raw text in `<START>` format — not JSON — to avoid parsing issues
  /// that plagued the old bundled approach.
  Future<void> _generateExampleDialogue({
    required CharacterCard card,
    required String name,
    required String interviewTranscript,
    void Function(String)? onProgress,
  }) async {
    final prompt =
        '''Write example dialogue exchanges for a roleplay character named $name.
These examples teach the AI how $name speaks — their vocabulary, sentence structure, emotional reactions, and mannerisms.

SOURCE MATERIAL — $name's own words from an in-character interview:
$interviewTranscript

CHARACTER PERSONALITY:
${card.personality}

WRITE exactly 3 example exchanges in this EXACT format (copy it precisely):

<START>
{{user}}: [a question, comment, or action that prompts a response]
{{char}}: [an in-character response showing $name's authentic voice — 2-4 sentences minimum]

<START>
{{user}}: [a different situation — vary the emotional context]
{{char}}: [response showing a different side of $name — longer responses are better]

<START>
{{user}}: [a third scenario — ideally emotionally charged or revealing]
{{char}}: [response that reveals $name's deeper personality — include inner thoughts with *asterisks* for actions]

RULES:
- Each {{char}} response MUST be 2-6 sentences — never one-liners
- Show RANGE: one casual, one emotional, one that reveals depth
- Use the EXACT speech patterns from the interview — if they use slang, contractions, or unusual phrasing, replicate it
- Include *action descriptions* and emotional reactions, not just dialogue
- {{char}} responses should feel like they come from a real person with opinions, not a generic AI
- Use {{char}} and {{user}} as placeholders — never real names

Output ONLY the example dialogue. No commentary, no JSON, no explanation. Start directly with <START>:''';

    final output = await _callLLM(
      prompt,
      maxLen: 3072,
      minLen: 200,
      onProgress: onProgress,
    );
    if (output == null || output.trim().isEmpty) {
      debugPrint('CharacterGen: Example dialogue generation got no response');
      return;
    }

    // Clean the output — strip think tags and any preamble before first <START>
    String cleaned = output
        .replaceAll(
          RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
        .trim();

    // Find the first <START> tag and keep everything from there
    final startIdx = cleaned.indexOf('<START>');
    if (startIdx >= 0) {
      cleaned = cleaned.substring(startIdx);
    } else {
      // Try case-insensitive
      final startIdxCI = cleaned.toLowerCase().indexOf('<start>');
      if (startIdxCI >= 0) {
        cleaned = cleaned.substring(startIdxCI);
      }
    }

    // Validate: must contain at least one <START> and one {{char}}: response
    if (cleaned.contains('<START>') && cleaned.contains('{{char}}')) {
      card.mesExample = cleaned.trim();
      debugPrint(
        'CharacterGen: Example dialogue generated (${cleaned.length} chars)',
      );
    } else {
      debugPrint(
        'CharacterGen: Example dialogue output invalid — missing <START> or {{char}} markers',
      );
    }
  }
}
