// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../character_gen_service.dart';

extension GenSteps2 on CharacterGenService {
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
    final backstoryLine = backstory.isNotEmpty ? 'Backstory: $backstory\n' : '';

    // Build spec only for the missing keys
    final fieldSpecs = <String>[];
    for (final field in missingFields) {
      switch (field) {
        case 'personality':
          fieldSpecs.add(
            '- "personality": (string) 1-2 paragraphs, third person, core traits + motivations + quirks',
          );
          break;
        case 'scenario':
          fieldSpecs.add(
            '- "scenario": (string) 1 paragraph, the default conversation setting',
          );
          break;
      }
    }

    final prompt =
        '''Generate ONLY the following fields for a roleplay character as a JSON object. Output ONLY the JSON, no markdown, no explanation.

Character name: $name
Concept: $concept
$ageLine$sexLine$relationshipLine$backstoryLine$keywordsLine
Required JSON keys:
${fieldSpecs.join('\n')}

Use {{char}} for character name and {{user}} for user name. Respond with ONLY the JSON:''';

    debugPrint(
      'CharacterGen: Recovery prompt for ${missingFields.length} fields',
    );

    final output = await _callLLM(
      prompt,
      maxLen: 4096,
      isJsonMode: true,
      onProgress: onProgress,
    );
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
        categoryGuidance =
            '\n\nCATEGORY GUIDE (generate entries matching these types):\n${guides.join('\n')}';
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

    // Opt-in dynamic-macro rule (rule 9) — only when the creator's toggle is on.
    final macroRule = _includeDynamicMacros
        ? '\n10. LIVING DETAIL (optional, sparing): in "custom" or "location" entries ONLY — never premise/faction/history — you MAY drop in ONE {{pick:...}} macro for a small detail that should vary each visit, so the world feels alive. EXACT syntax, double braces: {{pick:option one, option two, option three}}. Example content: "The tavern board today reads {{pick:mutton stew, fish pie, spiced wine}}." At most one per entry, only where a rotating detail is natural; most entries need none. (A {{roll:d6}} for a small random count is also allowed.)'
        : '';

    final prompt =
        '''Generate WORLD-BUILDING lorebook entries for a roleplay setting. Output ONLY a JSON object with a single key "lorebook" containing an array of $countRange entry objects.$categoryHint

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
7. Include EXACTLY ONE entry with "category":"premise" — a 1-2 paragraph portrait of the world's core setting, tone, and what makes it distinct. It is the always-present backdrop, so write it to read well on its own; set its "key" to a few broad theme words.
8. "secondary" (OPTIONAL context keywords): for faction/location/figure/history/item entries you MAY add words that must appear ALONGSIDE a main key for the entry to surface — this keeps it out of unrelated scenes (e.g. a sea-captain entry fires only when "captain" AND "ship" or "crew" come up). Use "" when the entry should fire on its main keys alone. The premise entry never needs it. Put interchangeable ambient flavor — rumors, gossip, minor local events — in "custom" with broad scene keys; only one will surface at a time.
9. INTERCONNECT the lore: when one entry naturally relates to another (a faction and the ritual it guards, a location and the figure who rules it, an item and where it came from), NAME that other entry — using its key word — inside this entry's content. Bringing up one then naturally surfaces the other, so the world reads as connected lore rather than a list of isolated facts.$macroRule

CATEGORY — tag EVERY entry with exactly one of:
- premise  : the world's core setting/tone/backdrop (EXACTLY ONE entry)
- faction  : groups, orders, powers, organizations
- location : specific places
- figure   : notable NPCs / named individuals in the world
- history  : past events, wars, cataclysms
- item     : notable objects, artifacts, technologies
- custom   : customs, rumors, ambient flavor

Each entry format: {"name": "short title", "category": "premise|faction|location|figure|history|item|custom", "key": "trigger,keywords", "secondary": "context,words", "content": "1-2 paragraphs of world lore"}

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
        final fixed = _fixJsonNewlines(
          cleaned,
        ).replaceAll(RegExp(r',\s*}'), '}').replaceAll(RegExp(r',\s*]'), ']');
        data = json.decode(fixed) as Map<String, dynamic>;
      }

      final lorebookData = data['lorebook'];
      if (lorebookData is List && lorebookData.isNotEmpty) {
        final generated = <GeneratedLoreEntry>[];
        for (final entry in lorebookData) {
          if (entry is Map<String, dynamic>) {
            generated.add(
              GeneratedLoreEntry(
                name: entry['name']?.toString() ?? '',
                key: entry['key']?.toString() ?? '',
                content: entry['content']?.toString() ?? '',
                category: entry['category']?.toString() ?? '',
                secondary: entry['secondary']?.toString() ?? '',
              ),
            );
          }
        }
        // The model wrote prose + a category; the engine mechanics (premise
        // anchor, priority tiers, contextual firing, variety, interconnection)
        // are assigned deterministically here. See lorebook_mechanics.dart.
        final lorebook = buildSmartLorebook(generated);
        if (lorebook != null) {
          card.lorebook = lorebook;
          debugPrint(
            'CharacterGen: Separate lorebook generated '
            '${lorebook.entries.length} entries',
          );
        }
      }
    } catch (e) {
      debugPrint('CharacterGen: Separate lorebook parse failed: $e');
    }
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

    final prompt =
        '''Write an image generation prompt for an illustration of this character.
You MUST follow the requested format perfectly. Do NOT include introductory text, markdown, or JSON. Just the raw prompt string.

== CONTEXT ==
Character description: $description
Current scenario setting: $scenario

== INSTRUCTIONS ==
Ground the image entirely in the visual details from the description, and use the scenario to dictate the background environment, lighting, and pose. Do NOT use the character's name in the output.

$formatInstruction

Begin:''';

    final output = await _callLLM(
      prompt,
      maxLen: 1024,
      minLen: 20,
      onProgress: onProgress,
    );
    if (output == null) return null;

    // Strip any reasoning the model still emitted (a hybrid thinking model can
    // ignore the reasoning-off signal), THEN trim wrapping quotes. Every other
    // CharacterGen consumer strips <think>; without it here the raw reasoning
    // block leaked into the portrait-prompt seed shown in the creator.
    final cleaned = stripThinkBlocks(output);
    return cleaned.replaceAll(RegExp(r'^"|"$'), '').trim();
  }
}
