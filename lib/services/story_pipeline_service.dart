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
import 'package:front_porch_ai/models/story_project.dart';
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/database/database.dart' hide StoryProject;

/// Orchestrates the multi-agent AI novel-writing pipeline for Porch Stories.
///
/// Each stage constructs a specialized prompt, calls the LLM via [LLMService],
/// parses the structured JSON response, and updates the [StoryProject] state.
/// Supports three prompt complexity tiers for different model capabilities.
class StoryPipelineService extends ChangeNotifier {
  final StoryRepository _repository;
  final LLMService _llmService;
  final MemoryService
  _memoryService; // ignore: unused_field - Reserved for future story RAG / memory injection
  final AppDatabase _db;

  bool _isRunning = false;
  String _currentStep = '';
  String _statusMessage = '';
  String _streamingText = '';
  int _tokenCount = 0;

  bool get isRunning => _isRunning;
  String get currentStep => _currentStep;
  String get statusMessage => _statusMessage;
  String get streamingText => _streamingText;
  int get tokenCount => _tokenCount;

  StoryPipelineService(
    this._repository,
    this._llmService,
    this._memoryService,
    this._db,
  );

  /// Public method for the UI to preview what chat history will be imported.
  /// Always pulls full messages from the DB (not RAG embeddings which are windowed summaries).
  Future<List<String>> getChatPreviewMessages(StoryProject project) async {
    if (!project.useChatHistory || project.chatHistoryCharacterIds.isEmpty) {
      return [];
    }
    final messages = <String>[];
    try {
      final resolvedIds = await _resolveSessionCharacterIds(
        project.chatHistoryCharacterIds,
      );
      for (final charId in resolvedIds) {
        final sessions = await _db.getSessionsForCharacter(charId);
        for (final session in sessions) {
          final msgs = await _db.getMessagesForSession(session.id);
          for (final msg in msgs) {
            try {
              final swipes = jsonDecode(msg.swipes) as List;
              final text = swipes.isNotEmpty
                  ? swipes[msg.swipeIndex.clamp(0, swipes.length - 1)]
                  : '';
              if (text.toString().trim().isNotEmpty) {
                messages.add('${msg.sender}: $text');
              }
            } catch (_) {}
          }
          messages.add('--- (session break) ---');
        }
      }
    } catch (e) {
      debugPrint('[StoryPipeline] Chat preview error: $e');
    }
    return messages;
  }

  /// Resolve character IDs to actual session characterIds.
  /// The stored IDs might be embed-IDs, DB PKs, or filename-based IDs.
  /// This method cross-references by character name to find ALL session IDs.
  Future<Set<String>> _resolveSessionCharacterIds(
    List<String> storedIds,
  ) async {
    final resolved = <String>{};
    resolved.addAll(storedIds);

    try {
      final allChars = await _db.select(_db.characters).get();
      final allSessions = await _db.select(_db.sessions).get();

      for (final storedId in storedIds) {
        // Find this character in the Characters table
        final matchingChar = allChars.where((c) => c.id == storedId);
        if (matchingChar.isEmpty) continue;

        final charName = matchingChar.first.name;

        // Find ALL sessions whose characterId maps to a character with the same name
        for (final sess in allSessions) {
          if (sess.characterId == null) continue;
          final sessChar = allChars.where((c) => c.id == sess.characterId);
          if (sessChar.isNotEmpty && sessChar.first.name == charName) {
            resolved.add(sess.characterId!);
          }
        }
      }
    } catch (e) {
      debugPrint('[StoryPipeline] ID resolution error: $e');
    }

    // Remove the original stored IDs if they don't match any sessions
    // (only keep IDs that actually have sessions)
    return resolved;
  }

  void _setStatus(String step, String message) {
    _currentStep = step;
    _statusMessage = message;
    notifyListeners();
  }

  // ── JSON UTILITIES ──────────────────────────────────────────────────

  /// Strip <think>...</think> blocks from reasoning-model output.
  static String _stripThinkTags(String text) {
    // Handle both complete and unclosed think tags
    // Complete: <think>...</think> (including multiple blocks)
    var result = text.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
      '',
    );
    // Also handle <reasoning>...</reasoning> blocks (some models use this)
    result = result.replaceAll(
      RegExp(r'<reasoning>[\s\S]*?</reasoning>', caseSensitive: false),
      '',
    );
    // Unclosed (model still reasoning): <think>... without closing tag
    final openTagIdx = result.indexOf(RegExp(r'<think>', caseSensitive: false));
    if (openTagIdx != -1) {
      // Find the JSON start after the think block
      final jsonStart = result.indexOf('{', openTagIdx);
      if (jsonStart != -1) {
        // Only keep from the first { onward
        result = result.substring(jsonStart);
      }
    }
    return result.trim();
  }

  /// Extract JSON from LLM output — handles think tags, code blocks, raw JSON, etc.
  static String cleanJson(String text) {
    if (text.isEmpty) return '';

    // Step 1: Strip <think>...</think> reasoning blocks
    var cleaned = _stripThinkTags(text);
    debugPrint(
      '[StoryPipeline] After stripping think tags: ${cleaned.length} chars (was ${text.length})',
    );

    // Step 2: Try to extract from code block
    final codeBlockMatch = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
    ).firstMatch(cleaned);
    if (codeBlockMatch != null) return codeBlockMatch.group(1)!.trim();

    // Step 3: Strip any text before the first { (e.g. "Here is the JSON:")
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return cleaned.substring(start, end + 1);
    }

    return cleaned.trim();
  }

  /// Attempt to repair truncated JSON by closing open brackets/braces.
  static String _repairTruncatedJson(String json) {
    var openBraces = 0;
    var openBrackets = 0;
    var inString = false;
    var escaped = false;

    for (int i = 0; i < json.length; i++) {
      final c = json[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\') {
        escaped = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (c == '{') openBraces++;
      if (c == '}') openBraces--;
      if (c == '[') openBrackets++;
      if (c == ']') openBrackets--;
    }

    // If we're inside a string, close it
    var repaired = json;
    if (inString) repaired += '"';

    // Close open brackets and braces
    for (int i = 0; i < openBrackets; i++) {
      repaired += ']';
    }
    for (int i = 0; i < openBraces; i++) {
      repaired += '}';
    }

    return repaired;
  }

  /// Parse JSON with fallback for malformed/truncated responses.
  static Map<String, dynamic>? parseJson(String raw) {
    final cleaned = cleanJson(raw);
    if (cleaned.isEmpty) return null;

    // Try direct parse first
    try {
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {}

    // Try repairing truncated JSON
    try {
      final repaired = _repairTruncatedJson(cleaned);
      debugPrint('[StoryPipeline] Attempting repaired JSON parse...');
      return jsonDecode(repaired) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[StoryPipeline] JSON parse error: $e');
      debugPrint(
        '[StoryPipeline] Cleaned text (first 500): ${cleaned.length > 500 ? cleaned.substring(0, 500) : cleaned}',
      );
      return null;
    }
  }

  // ── STORY ARCHETYPES ────────────────────────────────────────────────

  static const _genres = [
    "Space Opera",
    "Cyberpunk",
    "High Fantasy",
    "Urban Fantasy",
    "Post-Apocalyptic",
    "Dystopian",
    "Gothic Horror",
    "Cosmic Horror",
    "Hard Boiled Noir",
    "Western",
    "Steampunk",
    "Romantic Comedy",
    "Political Thriller",
    "Espionage",
    "Superhero",
    "Slice of Life",
    "Historical Drama",
    "Military Sci-Fi",
    "Whodunit",
    "Survival Thriller",
  ];

  static const _styles = [
    "Moody & Atmospheric",
    "Fast-paced & Kinetic",
    "Witty & Satirical",
    "Dark & Gritty",
    "Optimistic & Whimsical",
    "Intellectual & Philosophical",
    "Minimalist & Stark",
    "Lyrical & Poetic",
    "Suspenseful & Tense",
    "Melancholic & Reflective",
    "Campy & Over-the-top",
    "Brutal & Unflinching",
  ];

  static const _concepts = [
    "a lone wanderer seeks redemption for a past sin",
    "a team of specialists pulls off the ultimate heist",
    "a detective investigates a murder that shouldn't be possible",
    "strangers are trapped together in a confined location",
    "a chosen one rejects their destiny",
    "an artificial intelligence discovers emotions",
    "a magical artifact ruins the life of its owner",
    "two enemies are forced to work together to survive",
    "a civilization faces imminent collapse from an unseen threat",
    "a character wakes up with no memory in a strange world",
    "a forbidden romance alters the course of history",
    "a small lie spirals out of control into a global conspiracy",
    "an explorer discovers a land that defies the laws of physics",
    "a soldier questions the morality of their orders",
    "a family secret threatens to destroy a dynasty",
    "a scientist's experiment goes horribly wrong",
    "an underdog competes in a high-stakes tournament",
    "a ghost tries to solve their own murder",
    "a time traveler tries to fix a mistake but makes it worse",
    "a peaceful community is invaded by a superior force",
  ];

  /// Generate random story concept archetypes for the user to choose from.
  static List<Map<String, String>> generateArchetypes({int count = 10}) {
    final options = <Map<String, String>>[];
    final rng = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < count; i++) {
      final genre = _genres[(rng + i * 7) % _genres.length];
      final style = _styles[(rng + i * 13) % _styles.length];
      final concept = _concepts[(rng + i * 3) % _concepts.length];
      options.add({
        'label': '$genre / $style / ${concept.substring(0, 30)}...',
        'value': 'A $genre story written in a $style style, wherein $concept.',
      });
    }
    return options;
  }

  // ── PROMPT TEMPLATES ────────────────────────────────────────────────

  String _jsonInstruction(PromptTier tier) {
    switch (tier) {
      case PromptTier.frontier:
        return 'Output ONLY valid JSON. No markdown, no explanation, no text before or after the JSON.';
      case PromptTier.largLocal:
        return 'IMPORTANT: Your response must be ONLY valid JSON. Start with { and end with }. No other text.';
      case PromptTier.smallLocal:
        return 'RESPOND WITH JSON ONLY. START WITH { END WITH }. NO OTHER TEXT ALLOWED.';
    }
  }

  /// Build a compact block of user preferences to inject into prompts.
  String _getUserPrefsBlock(StoryProject project) {
    final parts = <String>[];
    parts.add('POV: ${project.pov}');
    if (project.selectedGenres.isNotEmpty) {
      parts.add('Genre: ${project.selectedGenres.join(", ")}');
    }
    if (project.selectedMoods.isNotEmpty) {
      parts.add('Mood: ${project.selectedMoods.join(", ")}');
    }
    if (project.writingStyle.isNotEmpty) {
      parts.add('Writing Style: ${project.writingStyle}');
    }
    parts.add('Prose Length: ${project.proseLength}');
    parts.add('Narrative Pace: ${project.narrativePace}');
    parts.add('Dialogue Density: ${project.dialogueDensity}');
    parts.add('Maturity Rating: ${project.maturityRating}');
    parts.add('Number of Acts: ${project.actCount}');
    return 'USER PREFERENCES:\n${parts.join("\n")}';
  }

  String _getStoryArchitectPrompt(StoryProject project) {
    final tier = project.promptTier;
    final prefs = _getUserPrefsBlock(project);
    if (tier == PromptTier.smallLocal) {
      return '''Create a story bible from the concept. Match the user's preferences.

$prefs

${_jsonInstruction(tier)}

Output this JSON structure:
{
  "concept": "refined summary",
  "status_quo": "the normal world before plot begins",
  "inciting_incident": "event that breaks status quo",
  "themes": "core ideas explored",
  "pov": "${project.pov}",
  "style": {"genre": "...", "mood": "...", "writing_guide": "tone instructions"},
  "threads": [{"id": "t1", "name": "Main Arc", "description": "..."}],
  "protagonist": {"name": "...", "role": "Protagonist", "description": "...", "voice_sample": "sample dialogue", "details": {"history": "...", "goals": "...", "evolution": "..."}},
  "world_lore": [{"topic": "Setting", "detail": "...", "related_to": ["..."]}]
}''';
    }
    return '''You are a Lead Narrative Designer. Input: A concept. Task: Deconstruct this into a rich Story Bible.

$prefs

REQUIREMENTS:
1. STATUS QUO: Define the "Normal World" before the plot begins.
2. INCITING INCIDENT: Define the specific event that breaks the status quo.
3. PROTAGONIST: Deep dive into personality, flaws, and specific voice.
4. THEMES: What philosophical or emotional questions are being explored?
5. STYLE: Match the user's requested genre, mood, and writing style preferences listed above.
6. POV: Use the POV specified above (${project.pov}).

${_jsonInstruction(tier)}

Output JSON:
{
  "concept": "Refined summary",
  "status_quo": "Description of the normal world...",
  "inciting_incident": "The specific event...",
  "themes": "The core ideas being explored...",
  "pov": "${project.pov}",
  "style": {
    "genre": "...",
    "mood": "...",
    "writing_guide": "Instructions for the writer agent on tone/voice"
  },
  "threads": [
    { "id": "t1", "name": "Main Arc", "description": "..." },
    { "id": "t2", "name": "Relationship Arc", "description": "..." },
    { "id": "t3", "name": "Subplot Arc", "description": "..." }
  ],
  "protagonist": {
    "name": "Name",
    "role": "Protagonist",
    "description": "Physical & Personality",
    "voice_sample": "Dialogue sample",
    "details": {
      "history": "Backstory...",
      "story_events": "Start...",
      "goals": "...",
      "evolution": "..."
    }
  },
  "world_lore": [{ "topic": "Setting", "detail": "...", "related_to": ["Related Topic"] }]
}''';
  }

  String _getActStructurePrompt(int actCount, PromptTier tier) {
    final actExamples = List.generate(actCount, (i) {
      final n = i + 1;
      return '    {"number": $n, "title": "...", "description": "full act description", "focus_thread_ids": ["t1"], "knots": [{"description": "event", "interaction": "how threads interact"}]}';
    }).join(',\n');

    if (tier == PromptTier.smallLocal) {
      return '''Create a $actCount-act story structure.
The first act is setup, the last act is resolution. Middle acts are confrontation and rising action.

${_jsonInstruction(tier)}

Output JSON:
{
  "acts": [
$actExamples
  ]
}''';
    }

    String actGuidance;
    if (actCount == 1) {
      actGuidance =
          'Act 1: Complete arc -- setup, confrontation, and resolution in a single act.';
    } else if (actCount == 2) {
      actGuidance =
          'Act 1 (Setup): Establish the world and characters, end with the inciting crisis.\nAct 2 (Resolution): Confrontation, climax, and resolution.';
    } else if (actCount == 3) {
      actGuidance =
          'Act I (The Thesis): The Status Quo. Must end with a one-way door decision.\nAct II (The Antithesis): The Crucible. Must have a midpoint shift and end at "All Hope Is Lost."\nAct III (The Synthesis): The protagonist proves they have changed. Climax where external and internal goals collide.';
    } else if (actCount == 4) {
      actGuidance =
          'Act 1 (Setup): Establish the world and characters.\nAct 2 (Rising Action): Complications mount, alliances shift.\nAct 3 (Crisis): Everything falls apart, darkest hour.\nAct 4 (Resolution): The protagonist transforms and resolves the conflict.';
    } else {
      actGuidance =
          'Act 1 (Setup): Establish the world and characters.\nAct 2 (Complication): Initial obstacles and discoveries.\nAct 3 (Midpoint Shift): Everything changes, new stakes.\nAct 4 (Crisis): Darkest hour, all seems lost.\nAct 5 (Resolution): Transformation, climax, and resolution.';
    }

    return '''You are an author developing story structure. Define exactly $actCount Acts.

$actGuidance

THREAD REQUIREMENT: Define 2-3 "Convergence Events" (Knots) per act where threads intersect.

${_jsonInstruction(tier)}

Output JSON:
{
  "acts": [
$actExamples
  ]
}''';
  }

  String _getSceneWeaverPrompt(int actNumber, PromptTier tier) {
    final sceneCount = actNumber == 2
        ? '4-6'
        : (actNumber == 1 ? '3-5' : '3-4');

    if (tier == PromptTier.smallLocal) {
      return '''Create $sceneCount scenes for Act $actNumber. Each scene needs: number, title, description, location, cast, and a valence score (-10 to +10).

${_jsonInstruction(tier)}

Output JSON:
{
  "scenes": [
    {"number": 1, "title": "...", "description": "what happens", "active_thread_ids": ["t1"], "location": "...", "cast_names": ["Hero"], "valence": 0, "causality": {"interaction_type": "Isolation", "description": "..."}}
  ],
  "new_characters": [{"name": "...", "role": "...", "description": "..."}]
}''';
    }
    return '''You are an author creating scenes for ACT $actNumber.

Generate $sceneCount scenes. Each scene must:
- Have a clear purpose (advance plot, reveal character, or both)
- Follow causality: each scene occurs because of the previous one
- Manage tension: oscillate between high/low intensity, with rising overall trend
- Be clear about location, setting, and characters present
${actNumber == 1 ? '- Scene 1 MUST introduce the protagonist and the world to the reader. Ground the reader in who, where, and what.\n- Early scenes should establish characters before throwing them into conflict.' : ''}

THREAD INTERACTION:
- Isolation: Only advances one thread
- Collision: Two threads conflict
- Resonance: Two threads thematically align

Assign valence (-10 to +10) to each scene for emotional charge.

${_jsonInstruction(tier)}

Output JSON:
{
  "scenes": [
    { "number": 1, "title": "Scene Title", "description": "detailed plot events and authorial intent", "active_thread_ids": ["t1"], "location": "Setting", "cast_names": ["Hero"], "valence": 0, "causality": { "interaction_type": "Isolation", "description": "Establishes Hero's situation." } }
  ],
  "new_characters": [ { "name": "...", "role": "...", "description": "..." } ]
}''';
  }

  String _getBeatDirectorPrompt(PromptTier tier) {
    if (tier == PromptTier.smallLocal) {
      return '''Break this scene into 6-8 beats. Each beat is a small narrative unit with action and emotional change.

${_jsonInstruction(tier)}

Output JSON:
{
  "beats": [
    {"number": 1, "type": "Action", "description": "what happens and why", "emotional_shift": "how mood changes", "valence": 0, "pacing": 1}
  ]
}''';
    }
    return '''You are the architect of a single narrative scene. Break it into 6-10 distinct beats.

For each beat consider:
- Someone wants something. Someone opposes it. Something changes.
- Assign a tactic (active verb) so characters are active, not passive
- Create a gap between expectation and reality
- Ensure emotional change within each beat
- Vary types: Action, Reaction, Dialogue, Revelation, Resolution

PACING: 0=Slow (atmospheric), 1=Balanced (dialogue-heavy), 2=Fast (action/conflict)
VALENCE: -10 to +10, oscillating to maintain tension

${_jsonInstruction(tier)}

Output JSON:
{
  "beats": [
    { "number": 1, "type": "Action/Reaction/Dialogue", "description": "what happens, who is involved, authorial intent", "emotional_shift": "How the mood changes", "valence": 4, "pacing": 1 }
  ]
}''';
  }

  String _getDrafterPrompt(StoryProject project) {
    final pov = project.pov;
    final tier = project.promptTier;
    final pace = project.narrativePace;
    final dialogue = project.dialogueDensity;
    final style = project.writingStyle.isNotEmpty
        ? '\n- Match the "${project.writingStyle}" writing style.'
        : '';
    if (tier == PromptTier.smallLocal) {
      return '''Write 400-600 words of prose for the current beat. Use $pov POV consistently. Use short paragraphs (2-4 sentences each). Include dialogue where characters are present. Flow from the previous beat and end naturally before the next beat.''';
    }
    return '''You are an award-winning author working on your next novel. Write the prose for the CURRENT BEAT in 400-600 words.

CRITICAL RULES:
- Use $pov point of view consistently. NEVER switch POV mid-scene.
- Use SHORT PARAGRAPHS -- 2-4 sentences maximum per paragraph. Insert blank lines between paragraphs.
- Dialogue density: $dialogue. ${dialogue == 'Dialogue-Heavy'
        ? 'Most of the prose should be character dialogue.'
        : dialogue == 'Sparse'
        ? 'Use dialogue sparingly; focus on internal narrative and description.'
        : 'Balance dialogue with narration.'}
- Narrative pace: $pace. ${pace == 'Slow Burn'
        ? 'Linger on atmosphere and sensory details.'
        : pace == 'Fast-Paced'
        ? 'Keep sentences tight. Favor action verbs. No lingering.'
        : 'Mix reflection with forward momentum.'}$style
- The text must flow smoothly from the previous beat
- End just before the next beat begins
- Show, don't tell -- use vivid sensory details
- Each character must have a distinct voice in dialogue
- Characters must be actively pursuing their goals''';
  }

  String _getEditorPrompt(StoryProject project) {
    final pov = project.pov;
    final tier = project.promptTier;
    final povCheck = pov == 'First Person'
        ? 'ENFORCE FIRST PERSON POV. If any text uses third person for the narrator, rewrite it to first person.'
        : 'ENFORCE ${pov.toUpperCase()} POV. If any text uses first person ("I", "my", "me") for narration, rewrite it to third person.';
    if (tier == PromptTier.smallLocal) {
      return '''Polish this prose draft. Fix any POV shifts (must be $pov). Break long paragraphs. Fix weak verbs, cut exposition, ensure distinct character voices. Return ONLY the polished prose text.''';
    }
    return '''You are a Ruthless Editor. Polish the following draft.

Rules:
1. $povCheck
2. BREAK UP WALL-OF-TEXT. No paragraph should exceed 4 sentences. Insert paragraph breaks.
3. Cut exposition. Show through action and dialogue.
4. Strengthen verbs -- replace passive voice and weak verbs.
5. Ensure character voice matches their personality.
6. Fix filter words (e.g., "He saw the box" -> "The box sat on the table").
7. Check continuity: no references to future events.
8. Give each character a distinct voice.
9. Ensure characters actively pursue goals.
10. Remove repetition and crutch words (e.g., "the particular", "the specific", "the weight of").
11. Ensure clear cause and effect with emotional state shifts.
12. Character reactions: visceral -> emotional -> intellectual -> action/speech.
13. ELIMINATE REPETITION: Flag and rewrite any repeated phrases, metaphors, adjectives, or sentence patterns. Each paragraph must feel fresh.

Return ONLY the polished prose text, nothing else.''';
  }

  String _getArchivistPrompt(PromptTier tier) {
    if (tier == PromptTier.smallLocal) {
      return '''Analyze the text. Return JSON with cast_updates (history/goals changes) and lore_updates (new facts about the world). Max 4 lore items.

${_jsonInstruction(tier)}

Output JSON:
{
  "cast_updates": [{"name": "...", "append_history": "...", "append_story_events": "...", "update_goals": "..."}],
  "lore_updates": [{"topic": "...", "detail": "...", "related_to": ["..."]}]
}''';
    }
    return '''You are the Story Archivist. Analyze the just-written text and return UPDATES.

1. CAST UPDATES:
- Did a character reveal new backstory?
- Did a major event happen to them?
- Did their goal change?

2. LORE UPDATES:
- New location or object described in detail?
- Max 1-4 items. Do NOT duplicate existing lore.

${_jsonInstruction(tier)}

Output JSON:
{
  "cast_updates": [
    { "name": "Hero", "append_history": "...", "append_story_events": "...", "update_goals": "..." }
  ],
  "lore_updates": [
    { "topic": "...", "detail": "...", "related_to": ["..."] }
  ]
}''';
  }

  String _getBeatValidatorPrompt(PromptTier tier) {
    return '''You are a Script Doctor. Check if the written prose allows the next planned beat to happen.

If YES: Return {"valid": true, "reason": "", "rectified_beats": []}
If NO: Return {"valid": false, "reason": "why it's invalid", "rectified_beats": [rewritten future beats]}

${_jsonInstruction(tier)}''';
  }

  // ── PIPELINE STAGES ─────────────────────────────────────────────────

  /// Call the LLM and get a text response. Streams tokens to _streamingText for UI.
  Future<String> _callLLM(
    String prompt, {
    int maxLength = 4096,
    double temp = 0.8,
  }) async {
    // Prepend an anti-thinking instruction for reasoning models
    final fullPrompt =
        'Do NOT use <think> tags or chain-of-thought reasoning. Respond directly.\n\n$prompt';

    final params = GenerationParams(
      prompt: fullPrompt,
      maxLength: maxLength,
      temperature: temp,
      topP: 0.9,
      minP: 0.05,
      repeatPenalty: 1.1,
    );

    _streamingText = '';
    _tokenCount = 0;
    notifyListeners();

    final buffer = StringBuffer();
    int notifyCounter = 0;
    await for (final token in _llmService.generateStream(params)) {
      buffer.write(token);
      _streamingText = buffer.toString();
      _tokenCount++;
      notifyCounter++;
      // Throttle UI updates to every 3 tokens to avoid jank
      if (notifyCounter >= 3) {
        notifyCounter = 0;
        notifyListeners();
      }
    }
    // Final update
    _streamingText = buffer.toString();
    notifyListeners();
    return buffer.toString();
  }

  /// Get chat history context for characters.
  /// Uses the distilled timeline when available; falls back to raw messages.
  Future<String> _getChatHistoryContext(StoryProject project) async {
    if (!project.useChatHistory || project.chatHistoryCharacterIds.isEmpty) {
      return '';
    }

    // Prefer the distilled timeline (structured, compressed, LLM-friendly)
    if (project.distilledTimeline.isNotEmpty) {
      debugPrint(
        '[StoryPipeline] Using distilled timeline (${project.distilledTimeline.length} chars)',
      );
      return '\n\n## CANON EVENT TIMELINE (distilled from character chat history)\n'
          'The following is a CHRONOLOGICAL TIMELINE of events extracted from actual conversations '
          'between the user and characters. These events are CANON -- they HAPPENED. The story MUST '
          'be built around this timeline. Each event represents a key plot point, revelation, emotional '
          'beat, or relationship development. The story is a novelization of these events:\n'
          '${project.distilledTimeline}\n';
    }

    // Fallback: raw messages (slower, noisier, but works if distillation hasn't run)
    debugPrint(
      '[StoryPipeline] No distilled timeline, falling back to raw messages',
    );
    try {
      final allMessages = <String>[];
      final resolvedIds = await _resolveSessionCharacterIds(
        project.chatHistoryCharacterIds,
      );
      for (final charId in resolvedIds) {
        final sessions = await _db.getSessionsForCharacter(charId);
        if (sessions.isEmpty) continue;
        for (final session in sessions) {
          final messages = await _db.getMessagesForSession(session.id);
          for (final msg in messages) {
            try {
              final swipes = jsonDecode(msg.swipes) as List;
              final text = swipes.isNotEmpty
                  ? swipes[msg.swipeIndex.clamp(0, swipes.length - 1)]
                  : '';
              if (text.toString().trim().isNotEmpty) {
                allMessages.add('${msg.sender}: $text');
              }
            } catch (_) {}
          }
          allMessages.add('---');
        }
      }

      if (allMessages.isEmpty) return '';
      final fullHistory = allMessages.join('\n');
      debugPrint(
        '[StoryPipeline] Loaded ${allMessages.length} raw messages as fallback',
      );
      return '\n\n## CANON CHAT HISTORY (raw messages)\n'
          'These events are CANON. The story MUST follow them:\n$fullHistory\n';
    } catch (e) {
      debugPrint('[StoryPipeline] Chat history error: $e');
      return '';
    }
  }

  // ── CHAT DISTILLER ─────────────────────────────────────────────

  /// Stage 0: Chat Distiller — raw chat messages → structured event timeline.
  /// Loads all messages from DB, chunks them, and uses the LLM to extract
  /// a chronological timeline of plot-critical events. Result is stored on
  /// `project.distilledTimeline`.
  Future<void> runChatDistiller(StoryProject project) async {
    if (!project.useChatHistory || project.chatHistoryCharacterIds.isEmpty) {
      return;
    }

    _isRunning = true;
    _setStatus('Chat Distiller', 'Loading chat messages...');

    try {
      // 1. Load all raw messages from DB
      final allMessages = <String>[];
      final resolvedIds = await _resolveSessionCharacterIds(
        project.chatHistoryCharacterIds,
      );
      debugPrint(
        '[StoryPipeline] Resolved ${project.chatHistoryCharacterIds} -> $resolvedIds',
      );

      for (final charId in resolvedIds) {
        final sessions = await _db.getSessionsForCharacter(charId);
        debugPrint(
          '[StoryPipeline] Found ${sessions.length} sessions for "$charId"',
        );
        for (final session in sessions) {
          final msgs = await _db.getMessagesForSession(session.id);
          debugPrint(
            '[StoryPipeline] Session ${session.id}: ${msgs.length} messages',
          );
          for (final msg in msgs) {
            try {
              final swipes = jsonDecode(msg.swipes) as List;
              final text = swipes.isNotEmpty
                  ? swipes[msg.swipeIndex.clamp(0, swipes.length - 1)]
                  : '';
              if (text.toString().trim().isNotEmpty) {
                allMessages.add('${msg.sender}: $text');
              }
            } catch (_) {}
          }
        }
      }

      if (allMessages.isEmpty) {
        debugPrint('[StoryPipeline] No messages to distill');
        _isRunning = false;
        notifyListeners();
        return;
      }

      debugPrint(
        '[StoryPipeline] Distilling ${allMessages.length} messages...',
      );

      // 2. Chunk messages into groups of ~50
      const chunkSize = 50;
      final chunks = <List<String>>[];
      for (int i = 0; i < allMessages.length; i += chunkSize) {
        chunks.add(
          allMessages.sublist(i, (i + chunkSize).clamp(0, allMessages.length)),
        );
      }

      // 3. Distill each chunk
      final chunkTimelines = <String>[];
      for (int i = 0; i < chunks.length; i++) {
        _setStatus(
          'Chat Distiller',
          'Distilling chunk ${i + 1}/${chunks.length} (${allMessages.length} messages total)...',
        );
        final chunkText = chunks[i].join('\n');

        final prompt =
            '''You are a story analyst. Read the following conversation between a user and an AI character and extract a CHRONOLOGICAL TIMELINE of plot-significant events.

For each event, write a single concise entry in this format:
[EVENT N] Description of what happened, who was involved, the emotional tone, and any revelations or relationship changes.

RULES:
- Extract ONLY plot-critical events: key actions, decisions, revelations, emotional turning points, relationship changes, conflicts, and resolutions.
- IGNORE: greetings, filler, out-of-character (OOC) discussion, meta-conversation, and small talk.
- Maintain CHRONOLOGICAL ORDER as they appear in the conversation.
- Be SPECIFIC: include character names, locations, and details that matter for storytelling.
- Capture the character's personality, speech patterns, and emotional states.
- Note any world-building details (places, factions, lore, rules of the world).

CONVERSATION CHUNK (messages ${i * chunkSize + 1}-${(i * chunkSize) + chunks[i].length} of ${allMessages.length}):
$chunkText

Extract the timeline now. Output ONLY the timeline entries, nothing else.''';

        final response = await _callLLM(prompt, maxLength: 4096, temp: 0.3);
        final cleaned = _stripThinkTags(response).trim();
        if (cleaned.isNotEmpty) {
          chunkTimelines.add(cleaned);
        }
      }

      // 4. If multiple chunks, do a final merge pass
      String finalTimeline;
      if (chunkTimelines.length > 1) {
        _setStatus(
          'Chat Distiller',
          'Merging ${chunkTimelines.length} timeline chunks...',
        );
        final mergePrompt =
            '''You are a story analyst. Below are timeline chunks extracted from different parts of a long conversation. Merge them into a SINGLE CHRONOLOGICAL TIMELINE.

Remove any duplicate events. Maintain chronological order. Keep the [EVENT N] format and renumber sequentially.

${chunkTimelines.asMap().entries.map((e) => '--- CHUNK ${e.key + 1} ---\n${e.value}').join('\n\n')}

Output the merged, deduplicated, chronologically ordered timeline. Output ONLY the timeline entries.''';

        final mergeResponse = await _callLLM(
          mergePrompt,
          maxLength: 8192,
          temp: 0.2,
        );
        finalTimeline = _stripThinkTags(mergeResponse).trim();
      } else {
        finalTimeline = chunkTimelines.isNotEmpty ? chunkTimelines.first : '';
      }

      // 5. Store on project
      project.distilledTimeline = finalTimeline;
      await _repository.saveProject(project);

      final eventCount = RegExp(
        r'\[EVENT \d+\]',
      ).allMatches(finalTimeline).length;
      debugPrint(
        '[StoryPipeline] Distilled ${allMessages.length} messages into $eventCount events',
      );
      _setStatus(
        'Chat Distiller',
        'Distilled $eventCount events from ${allMessages.length} messages!',
      );
    } catch (e) {
      _setStatus('Chat Distiller', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  /// Build character card context from snapshotted character definitions.
  String _getCharacterCardContext(StoryProject project) {
    if (project.characterCardSnapshots.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln(
      '\n\n## Character Definitions (from imported character cards)',
    );
    buffer.writeln(
      'These are the CORE characters of the story. Use their names, personalities, ',
    );
    buffer.writeln(
      'descriptions, and relationships faithfully. You MAY create additional supporting ',
    );
    buffer.writeln(
      'NPCs, antagonists, and side characters to enrich the story, but the characters ',
    );
    buffer.writeln('below should be the central figures.\n');

    for (int i = 0; i < project.characterCardSnapshots.length; i++) {
      final snap = project.characterCardSnapshots[i];
      final role = snap['role'] ?? 'Supporting';
      final isSelfInsert = snap['self_insert'] == 'true';
      final roleLabel = isSelfInsert ? '$role — User Self-Insert' : role;
      buffer.writeln(
        '### Character ${i + 1}: ${snap['name'] ?? 'Unknown'} ($roleLabel)',
      );
      if (snap['description']?.isNotEmpty == true) {
        buffer.writeln('Description: ${snap['description']}');
      }
      if (snap['personality']?.isNotEmpty == true) {
        buffer.writeln('Personality: ${snap['personality']}');
      }
      if (snap['scenario']?.isNotEmpty == true) {
        buffer.writeln('Scenario: ${snap['scenario']}');
      }
      if (snap['first_message']?.isNotEmpty == true) {
        buffer.writeln('Opening: ${snap['first_message']}');
      }
      if (snap['system_prompt']?.isNotEmpty == true) {
        buffer.writeln('System context: ${snap['system_prompt']}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Stage 1: Story Architect — concept → story bible.
  Future<void> runStoryArchitect(StoryProject project) async {
    _isRunning = true;
    _setStatus('Story Architect', 'Generating story bible from concept...');

    try {
      final chatContext = await _getChatHistoryContext(project);
      final charContext = _getCharacterCardContext(project);
      final systemPrompt = _getStoryArchitectPrompt(project);

      final prompt =
          '''$systemPrompt

Input Concept: ${project.concept}
$charContext
$chatContext

IMPORTANT: If character definitions are provided above, use them as the CORE CAST of the story. 
Their personalities, descriptions, and relationships should be faithfully reflected in the story 
bible. You are encouraged to create additional supporting characters, antagonists, and NPCs to 
enrich the world -- but the imported characters must remain central to the narrative.
${chatContext.isNotEmpty ? '\nCRITICAL: Chat history is provided above. This is the SOURCE TRUTH for the story. The plot, character arcs, and key events MUST follow what happened in these conversations. The story bible should structure these chat events into a coherent narrative arc -- do NOT invent a completely different plot. You are novelizing what happened, not writing a new story.' : ''}''';

      final response = await _callLLM(prompt, maxLength: 8192);
      final json = parseJson(response);

      if (json == null) {
        throw Exception('Failed to parse story bible JSON from AI response');
      }

      // Update project from response
      project.concept = json['concept'] ?? project.concept;
      project.statusQuo = json['status_quo'] ?? '';
      project.incitingIncident = json['inciting_incident'] ?? '';
      project.themes = json['themes'] ?? '';

      if (json['style'] != null) {
        project.style = StoryStyle.fromJson(json['style']);
      }

      if (json['threads'] != null) {
        project.threads = (json['threads'] as List)
            .map((t) => StoryThread.fromJson(t))
            .toList();
      }

      // Pre-populate cast from character card snapshots with user-assigned roles
      if (project.characterCardSnapshots.isNotEmpty) {
        project.cast = project.characterCardSnapshots.map((snap) {
          return StoryCastMember(
            name: snap['name'] ?? 'Unknown',
            role: snap['role'] ?? 'Supporting',
            description: snap['description'] ?? snap['personality'] ?? '',
          );
        }).toList();
      } else if (json['protagonist'] != null) {
        // Fallback: use LLM-generated protagonist only when no snapshots exist
        project.cast = [StoryCastMember.fromJson(json['protagonist'])];
      }

      // Add world lore
      if (json['world_lore'] != null) {
        project.lore = (json['world_lore'] as List)
            .map((l) => StoryLoreEntry.fromJson(l))
            .toList();
      }

      await _repository.saveProject(project);
      _setStatus('Story Architect', 'Story bible created!');
    } catch (e) {
      _setStatus('Story Architect', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  /// Stage 2: Act Structurer — story bible → 3 acts.
  Future<void> runActStructurer(StoryProject project) async {
    _isRunning = true;
    _setStatus(
      'Act Structurer',
      'Designing ${project.actCount}-act structure...',
    );

    try {
      final systemPrompt = _getActStructurePrompt(
        project.actCount,
        project.promptTier,
      );
      final prompt =
          '''$systemPrompt

Story Concept: ${project.concept}
Status Quo: ${project.statusQuo}
Inciting Incident: ${project.incitingIncident}
Themes: ${project.themes}
Style: ${jsonEncode(project.style.toJson())}
Threads: ${jsonEncode(project.threads.map((t) => t.toJson()).toList())}''';

      final response = await _callLLM(prompt, maxLength: 8192);
      final json = parseJson(response);

      if (json == null || json['acts'] == null) {
        throw Exception('Failed to parse act structure from AI response');
      }

      project.acts = (json['acts'] as List)
          .map((a) => StoryAct.fromJson(a))
          .toList();

      await _repository.saveProject(project);
      _setStatus(
        'Act Structurer',
        '${project.actCount}-act structure created!',
      );
    } catch (e) {
      _setStatus('Act Structurer', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  /// Stage 3: Scene Weaver — act → scenes.
  Future<void> runSceneWeaver(StoryProject project, int actIndex) async {
    _isRunning = true;
    final actNum = actIndex + 1;
    _setStatus('Scene Weaver', 'Weaving scenes for Act $actNum...');

    try {
      final act = project.acts[actIndex];
      final systemPrompt = _getSceneWeaverPrompt(actNum, project.promptTier);
      final previousContext = _getPreviousActsContext(project, actIndex);
      final chatContext = await _getChatHistoryContext(project);
      final prompt =
          '''$systemPrompt

Story Concept: ${project.concept}
Themes: ${project.themes}
Style: ${jsonEncode(project.style.toJson())}
Threads: ${jsonEncode(project.threads.map((t) => t.toJson()).toList())}
$previousContext
$chatContext
ACT $actNum: ${act.title}
${act.description}

Existing Cast: ${project.cast.map((c) => '${c.name} (${c.role})').join(', ')}
${actIndex > 0 ? '\nIMPORTANT: This is Act $actNum. Maintain continuity with the events described in the STORY SO FAR section above. Build upon established plot threads and character developments.' : ''}
${chatContext.isNotEmpty ? '\nCRITICAL: The chat history above is CANON. Scenes MUST dramatize the events from these conversations. Map chat events to specific scenes in this act.' : ''}''';

      final response = await _callLLM(prompt, maxLength: 8192);
      final json = parseJson(response);

      if (json == null || json['scenes'] == null) {
        throw Exception('Failed to parse scenes from AI response');
      }

      project.scenes[actIndex] = (json['scenes'] as List)
          .map((s) => StoryScene.fromJson(s))
          .toList();

      // Add any new characters
      if (json['new_characters'] != null) {
        for (final nc in json['new_characters'] as List) {
          final newChar = StoryCastMember.fromJson(nc);
          if (!project.cast.any((c) => c.name == newChar.name)) {
            project.cast.add(newChar);
          }
        }
      }

      await _repository.saveProject(project);
      _setStatus(
        'Scene Weaver',
        'Act $actNum scenes created! (${project.scenes[actIndex]?.length ?? 0} scenes)',
      );
    } catch (e) {
      _setStatus('Scene Weaver', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  /// Stage 4: Beat Director — scene → beats.
  Future<void> runBeatDirector(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) async {
    _isRunning = true;
    final scene = project.scenes[actIndex]![sceneIndex];
    _setStatus('Beat Director', 'Breaking down "${scene.title}" into beats...');

    try {
      final systemPrompt = _getBeatDirectorPrompt(project.promptTier);
      final prompt =
          '''$systemPrompt

Scene: ${scene.title}
Description: ${scene.description}
Location: ${scene.location}
Characters: ${scene.castNames.join(', ')}
Active Threads: ${scene.activeThreadIds.join(', ')}
Scene Valence: ${scene.valence}''';

      final response = await _callLLM(prompt, maxLength: 6144);
      debugPrint(
        '[BeatDirector] Raw response (first 500): ${response.length > 500 ? response.substring(0, 500) : response}',
      );
      final json = parseJson(response);

      if (json == null || json['beats'] == null) {
        debugPrint(
          '[BeatDirector] Parse failed. Keys found: ${json?.keys.toList()}',
        );
        throw Exception('Failed to parse beats from AI response');
      }

      final beatsList = json['beats'] as List;
      debugPrint('[BeatDirector] Found ${beatsList.length} beats');
      if (beatsList.isNotEmpty) {
        debugPrint(
          '[BeatDirector] First beat keys: ${(beatsList.first as Map).keys.toList()}',
        );
        debugPrint('[BeatDirector] First beat: ${beatsList.first}');
      }

      final sId = '$actIndex-$sceneIndex';
      project.beats[sId] = beatsList.map((b) => StoryBeat.fromJson(b)).toList();

      await _repository.saveProject(project);
      _setStatus(
        'Beat Director',
        '"${scene.title}" broken into ${project.beats[sId]?.length ?? 0} beats!',
      );
    } catch (e) {
      _setStatus('Beat Director', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  /// Stage 5+6: Drafter + Editor — beat → prose.
  Future<void> runDraftAndEdit(
    StoryProject project,
    int actIndex,
    int sceneIndex,
    int beatIndex,
  ) async {
    _isRunning = true;
    final sId = '$actIndex-$sceneIndex';
    final bId = '$sId-$beatIndex';
    final beat = project.beats[sId]![beatIndex];
    final scene = project.scenes[actIndex]![sceneIndex];

    _setStatus('Drafter', 'Writing beat ${beatIndex + 1}: ${beat.type}...');

    try {
      // Gather context
      final prevBeatText = beatIndex > 0
          ? project.prose['$sId-${beatIndex - 1}']?.final_ ?? ''
          : '';
      final nextBeat = beatIndex + 1 < (project.beats[sId]?.length ?? 0)
          ? project.beats[sId]![beatIndex + 1]
          : null;

      // Build character voices
      final voices = scene.castNames
          .map((name) {
            final char = project.cast.where((c) => c.name == name).firstOrNull;
            return char != null
                ? '${char.name} (${char.role}): ${char.description}'
                : name;
          })
          .join('\n');

      // Build drafter prompt
      final drafterPrompt =
          '''${_getDrafterPrompt(project)}

## Scene: ${scene.title}
${scene.description}

## Current Beat (${beat.type})
${beat.description}

## Emotional Shift: ${beat.emotionalShift}
## Pacing: ${beat.pacing == 0
              ? 'SLOW — atmospheric, sensory details'
              : beat.pacing == 1
              ? 'BALANCED — dialogue-heavy'
              : 'FAST — action, rapid decisions'}
## Valence: ${beat.valence}

## Characters Present
$voices

## Style & Tone
${project.style.writingGuide}

${prevBeatText.isNotEmpty ? '## Previous Beat Text (continue from here)\n$prevBeatText' : '## This is the FIRST beat of the scene.'}

${nextBeat != null ? '## Next Beat Preview (end just before this)\n${nextBeat.description}' : '## This is the LAST beat of the scene. Bring it to a satisfying close.'}

Write the prose now. Return ONLY the prose text, no commentary.''';

      final draft = await _callLLM(drafterPrompt, maxLength: 1024, temp: 0.85);

      // Store draft
      project.prose[bId] = BeatProse(draft: draft.trim());
      notifyListeners();

      // Editor pass
      _setStatus('Editor', 'Polishing beat ${beatIndex + 1}...');

      final editorPrompt =
          '''${_getEditorPrompt(project)}

## Context
Scene: ${scene.title}
Beat: ${beat.description}
Previous beat text: ${prevBeatText.isNotEmpty ? prevBeatText.substring(0, (prevBeatText.length).clamp(0, 500)) : 'Start of scene'}
${nextBeat != null ? 'Next beat plan: ${nextBeat.description}' : 'This is the final beat.'}

## Draft to Polish:
${draft.trim()}

Return ONLY the polished prose text.''';

      final edited = await _callLLM(editorPrompt, maxLength: 1024, temp: 0.6);
      project.prose[bId] = BeatProse(
        draft: draft.trim(),
        final_: edited.trim(),
      );

      await _repository.saveProject(project);
      _setStatus('Editor', 'Beat ${beatIndex + 1} complete!');
    } catch (e) {
      _setStatus('Editor', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  /// Stage 7: Archivist — update cast/lore after prose is written.
  Future<void> runArchivist(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) async {
    _isRunning = true;
    _setStatus('Archivist', 'Archiving world updates...');

    try {
      final sId = '$actIndex-$sceneIndex';
      final sceneText = StringBuffer();
      for (int i = 0; i < (project.beats[sId]?.length ?? 0); i++) {
        final prose = project.prose['$sId-$i'];
        if (prose?.final_ != null) sceneText.writeln(prose!.final_);
      }

      if (sceneText.isEmpty) return;

      final prompt =
          '''${_getArchivistPrompt(project.promptTier)}

## Text to Analyze:
${sceneText.toString().substring(0, sceneText.length.clamp(0, 3000))}

## Current Cast: ${project.cast.map((c) => c.name).join(', ')}
## Existing Lore: ${project.lore.map((l) => l.topic).join(', ')}''';

      final response = await _callLLM(prompt, maxLength: 2048);
      final json = parseJson(response);

      if (json != null) {
        // Apply cast updates
        if (json['cast_updates'] != null) {
          for (final up in json['cast_updates'] as List) {
            final name = up['name'];
            final idx = project.cast.indexWhere((c) => c.name == name);
            if (idx != -1) {
              final char = project.cast[idx];
              if (up['append_history'] != null) {
                char.details['history'] =
                    '${char.details['history'] ?? ''}\n${up['append_history']}';
              }
              if (up['append_story_events'] != null) {
                char.details['story_events'] =
                    '${char.details['story_events'] ?? ''}\n- ${up['append_story_events']}';
              }
              if (up['update_goals'] != null) {
                char.details['goals'] = up['update_goals'];
              }
            }
          }
        }

        // Apply lore updates
        if (json['lore_updates'] != null) {
          for (final up in json['lore_updates'] as List) {
            final entry = StoryLoreEntry.fromJson(up);
            entry.validFromAct = actIndex + 1;
            entry.validFromScene =
                (project.scenes[actIndex]?.indexOf(
                      project.scenes[actIndex]!.firstWhere(
                        (s) => true,
                        orElse: () => project.scenes[actIndex]!.first,
                      ),
                    ) ??
                    0) +
                1;
            if (!project.lore.any((l) => l.topic == entry.topic)) {
              project.lore.add(entry);
            }
          }
        }

        await _repository.saveProject(project);
      }

      _setStatus('Archivist', 'World updated!');
    } catch (e) {
      _setStatus('Archivist', 'Error: $e');
      // Non-fatal — don't rethrow
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  /// Stage 8: Beat Validator — check continuity.
  Future<bool> runBeatValidator(
    StoryProject project,
    int actIndex,
    int sceneIndex,
    int beatIndex,
  ) async {
    final sId = '$actIndex-$sceneIndex';
    final nextBeatIndex = beatIndex + 1;
    if (nextBeatIndex >= (project.beats[sId]?.length ?? 0)) return true;

    _setStatus('Validator', 'Checking continuity...');

    try {
      final prose = project.prose['$sId-$beatIndex']?.final_ ?? '';
      final nextBeat = project.beats[sId]![nextBeatIndex];
      final scene = project.scenes[actIndex]![sceneIndex];

      final prompt =
          '''${_getBeatValidatorPrompt(project.promptTier)}

Scene Goal: ${scene.description}
Written Prose Summary: ${prose.substring(0, prose.length.clamp(0, 500))}
Next Beat Plan: ${nextBeat.description}''';

      final response = await _callLLM(prompt, maxLength: 2048);
      final json = parseJson(response);

      if (json != null &&
          json['valid'] == false &&
          json['rectified_beats'] != null) {
        // Replace future beats with rectified versions
        final rectified = (json['rectified_beats'] as List)
            .map((b) => StoryBeat.fromJson(b))
            .toList();

        final currentBeats = project.beats[sId]!;
        final keptBeats = currentBeats.sublist(0, beatIndex + 1);
        project.beats[sId] = [...keptBeats, ...rectified];

        await _repository.saveProject(project);
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('[StoryPipeline] Validator error: $e');
      return true; // Continue if validator fails
    }
  }

  /// Auto-write all beats in a scene sequentially.
  Future<void> autoWriteScene(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) async {
    final sId = '$actIndex-$sceneIndex';
    final beats = project.beats[sId];
    if (beats == null || beats.isEmpty) return;

    for (int i = 0; i < beats.length; i++) {
      final bId = '$sId-$i';
      if (project.prose[bId]?.final_ != null) continue; // Skip already written

      await runDraftAndEdit(project, actIndex, sceneIndex, i);

      // Run validator after each beat (except the last)
      if (i < beats.length - 1) {
        await runBeatValidator(project, actIndex, sceneIndex, i);
      }
    }

    // Run archivist after the full scene
    await runArchivist(project, actIndex, sceneIndex);
  }

  /// Build a "Story So Far" context from all previously generated acts.
  /// This is critical for maintaining story continuity across act boundaries.
  String _getPreviousActsContext(StoryProject project, int currentActIndex) {
    if (currentActIndex == 0) return '';

    final buffer = StringBuffer();
    buffer.writeln(
      '\n\n## STORY SO FAR (Events from previous acts — maintain continuity!)',
    );
    buffer.writeln(
      'The following is a summary of everything that has happened in the story ',
    );
    buffer.writeln(
      'up to this point. You MUST maintain consistency with these established ',
    );
    buffer.writeln('events, character developments, and plot threads.\n');

    for (int prevAct = 0; prevAct < currentActIndex; prevAct++) {
      final act = project.acts[prevAct];
      final scenes = project.scenes[prevAct] ?? [];

      buffer.writeln('### Act ${act.number}: ${act.title}');
      buffer.writeln(act.description);

      if (scenes.isNotEmpty) {
        buffer.writeln('\nScenes:');
        for (int s = 0; s < scenes.length; s++) {
          final scene = scenes[s];
          buffer.writeln(
            '  ${s + 1}. ${scene.title} (${scene.location}) — ${scene.description}',
          );
          buffer.writeln('     Characters: ${scene.castNames.join(", ")}');

          // Include prose excerpts for rich context
          final sId = '$prevAct-$s';
          final beats = project.beats[sId] ?? [];
          final proseExcerpts = <String>[];
          for (int b = 0; b < beats.length; b++) {
            final bId = '$sId-$b';
            final prose = project.prose[bId]?.final_;
            if (prose != null && prose.isNotEmpty) {
              // Include a meaningful excerpt
              final excerpt = prose.length > 300
                  ? '${prose.substring(0, 300)}...'
                  : prose;
              proseExcerpts.add(excerpt);
            }
          }
          if (proseExcerpts.isNotEmpty) {
            buffer.writeln('     What happened: ${proseExcerpts.join(" ")}');
          }
        }
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Generate a complete act end-to-end in minimal LLM calls:
  ///   1. Scene Weaver (scenes + beats in one call)
  ///   2. Combined prose for the entire act (one call)
  /// This reduces ~20+ calls per act down to just 2-3.
  Future<void> generateFullAct(StoryProject project, int actIndex) async {
    _isRunning = true;
    final act = project.acts[actIndex];

    try {
      // Step 1: Generate scenes (always sequential — single call needed first)
      if (project.scenes[actIndex] == null ||
          project.scenes[actIndex]!.isEmpty) {
        _setStatus(
          'Act ${act.number}: Scenes',
          'Generating scenes for "${act.title}"...',
        );
        await runSceneWeaver(project, actIndex);
      }

      final scenes = project.scenes[actIndex] ?? [];
      if (scenes.isEmpty) {
        throw Exception('No scenes generated for Act ${act.number}');
      }

      // Generate beats for each scene sequentially
      for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
        final sId = '$actIndex-$sceneIdx';
        if (project.beats[sId] == null || project.beats[sId]!.isEmpty) {
          _setStatus(
            'Act ${act.number}: Beats',
            'Planning beats for scene ${sceneIdx + 1}/${scenes.length}...',
          );
          await runBeatDirector(project, actIndex, sceneIdx);
        }
      }

      // Write prose for each scene sequentially (beats reference previous beats)
      for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
        _setStatus(
          'Act ${act.number}: Writing',
          'Writing scene ${sceneIdx + 1}/${scenes.length}...',
        );
        await _writeSceneProseCombined(project, actIndex, sceneIdx);
      }

      _setStatus('Act ${act.number} Complete', 'Ready for review');
      await _repository.saveProject(project);
    } catch (e) {
      _setStatus('Error', 'Act ${act.number} failed: $e');
      rethrow;
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  /// Public method to regenerate prose for a single scene (after clearing old prose).
  Future<void> regenerateSceneProse(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) async {
    _isRunning = true;
    _setStatus('Rewriting', 'Regenerating scene ${sceneIndex + 1} prose...');
    try {
      await _writeSceneProseCombined(project, actIndex, sceneIndex);
      _setStatus('Complete', 'Scene rewrite finished!');
    } catch (e) {
      _setStatus('Error', 'Scene rewrite failed: $e');
      rethrow;
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  /// Write prose for a scene beat-by-beat with individual LLM calls.
  Future<void> _writeSceneProseCombined(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) async {
    final sId = '$actIndex-$sceneIndex';
    final scenes = project.scenes[actIndex] ?? [];
    if (sceneIndex >= scenes.length) return;
    final scene = scenes[sceneIndex];
    final beats = project.beats[sId] ?? [];
    if (beats.isEmpty) return;

    // Skip if all beats already have prose
    final allWritten = beats.asMap().entries.every((e) {
      final bId = '$sId-${e.key}';
      return project.prose[bId]?.final_ != null;
    });
    if (allWritten) return;

    final act = project.acts[actIndex];
    final tier = project.promptTier;

    final castInfo = scene.castNames.isNotEmpty
        ? 'Characters present: ${scene.castNames.join(", ")}'
        : '';

    // Build previous scene context for continuity
    String previousSceneText = '';
    if (sceneIndex > 0) {
      // Get the last beat's prose from the previous scene
      final prevSId = '$actIndex-${sceneIndex - 1}';
      final prevBeats = project.beats[prevSId] ?? [];
      for (int b = prevBeats.length - 1; b >= 0; b--) {
        final prevProse = project.prose['$prevSId-$b']?.final_;
        if (prevProse != null && prevProse.isNotEmpty) {
          previousSceneText = prevProse.length > 600
              ? prevProse.substring(prevProse.length - 600)
              : prevProse;
          break;
        }
      }
    } else if (actIndex > 0) {
      // First scene of a new act — get the last scene's last beat from the previous act
      final prevActScenes = project.scenes[actIndex - 1] ?? [];
      if (prevActScenes.isNotEmpty) {
        final lastSceneIdx = prevActScenes.length - 1;
        final prevSId = '${actIndex - 1}-$lastSceneIdx';
        final prevBeats = project.beats[prevSId] ?? [];
        for (int b = prevBeats.length - 1; b >= 0; b--) {
          final prevProse = project.prose['$prevSId-$b']?.final_;
          if (prevProse != null && prevProse.isNotEmpty) {
            previousSceneText = prevProse.length > 600
                ? prevProse.substring(prevProse.length - 600)
                : prevProse;
            break;
          }
        }
      }
    }

    final isFirstScene = actIndex == 0 && sceneIndex == 0;
    final pov = project.pov;
    final pace = project.narrativePace;
    final dialogue = project.dialogueDensity;
    final styleGuide = project.writingStyle.isNotEmpty
        ? 'Writing Style: ${project.writingStyle}.'
        : '';
    final maturity = project.maturityRating;

    // Generate each beat individually for maximum prose length
    String runningContext =
        previousSceneText; // Carries forward from scene to scene

    for (int beatIdx = 0; beatIdx < beats.length; beatIdx++) {
      final bId = '$sId-$beatIdx';

      // Skip if already finalized
      if (project.prose[bId]?.final_ != null) {
        // Still update running context so the next beat stays continuous
        runningContext = project.prose[bId]!.final_!;
        if (runningContext.length > 600) {
          runningContext = runningContext.substring(
            runningContext.length - 600,
          );
        }
        continue;
      }

      final beat = beats[beatIdx];
      final isFirstBeat = beatIdx == 0;
      final isOpeningBeat = isFirstScene && isFirstBeat;

      // Update status so UI shows per-beat progress
      _setStatus(
        'Writing',
        'Scene ${sceneIndex + 1}, Beat ${beatIdx + 1}/${beats.length}: ${beat.type}...',
      );

      // Build forward-context for the last beat so it transitions into the next scene
      String forwardHint = '';
      final isLastBeat = beatIdx == beats.length - 1;
      if (isLastBeat) {
        // Look for the next scene in this act, or the first scene of the next act
        StoryScene? nextScene;
        if (sceneIndex + 1 < scenes.length) {
          nextScene = scenes[sceneIndex + 1];
        } else if (actIndex + 1 < project.acts.length) {
          final nextActScenes = project.scenes[actIndex + 1] ?? [];
          if (nextActScenes.isNotEmpty) nextScene = nextActScenes[0];
        }
        if (nextScene != null) {
          forwardHint =
              '\nTRANSITION HINT — The NEXT scene is: "${nextScene.title}" at ${nextScene.location}.\n${nextScene.description}\nEnd this beat in a way that naturally leads into the next scene. Do NOT start the next scene — just set up the transition.';
        }
      }

      final prompt =
          '''You are a skilled novelist writing one section of a larger scene.

Story: ${project.concept}
Act ${act.number}: ${act.title} -- ${act.description}
Scene ${scene.number}: ${scene.title}
Location: ${scene.location}
$castInfo
Scene description: ${scene.description}
${_getPreviousActsContext(project, actIndex)}

YOUR CURRENT TASK: Write the prose for Beat ${beatIdx + 1} of ${beats.length} in this scene.
Beat type: ${beat.type}
Beat description: ${beat.description}
${isOpeningBeat ? '''

IMPORTANT -- THIS IS THE OPENING OF THE NOVEL:
- Introduce the protagonist naturally through action and description.
- Ground the reader in the world: where are we? what era? what is the atmosphere?
- Do NOT assume the reader knows anything about the characters or setting.
- Open with a hook that draws the reader in immediately.''' : ''}

CONTENT MATURITY: $maturity
${maturity == 'Explicit'
              ? 'This is an UNRESTRICTED adult story. Write graphic violence, sexual content, dark themes, and profanity naturally as the story demands. Do NOT censor, fade to black, or skip over explicit scenes. Write them in full vivid detail.'
              : maturity == 'Mature'
              ? 'This is a mature adult story. Include realistic violence, strong language, and suggestive/sexual themes where appropriate. You may be moderately graphic but avoid excessive gratuitous detail.'
              : 'This is a clean story suitable for all audiences. No graphic violence, sexual content, or strong language.'}

WRITING RULES:
1. Use $pov point of view consistently. ${pov == 'First Person' ? 'The narrator IS the protagonist. Use "I", "my", "me".' : 'NEVER use first person ("I", "my").'}
2. Use SHORT PARAGRAPHS -- 2-4 sentences maximum per paragraph. Separate paragraphs with blank lines.
3. Dialogue density: $dialogue. ${dialogue == 'Dialogue-Heavy'
              ? 'Characters should talk frequently. Dialogue drives the scene.'
              : dialogue == 'Sparse'
              ? 'Minimal dialogue. Focus on internal narrative and action.'
              : 'Balance dialogue with prose.'}
4. Narrative pace: $pace. ${pace == 'Slow Burn'
              ? 'Linger on atmosphere and sensory details.'
              : pace == 'Fast-Paced'
              ? 'Tight sentences. Favor action. No lingering.'
              : 'Balance reflection with momentum.'}
5. Write 400-800 words of rich, detailed prose for this beat.
6. Vary sentence length. Mix short punchy sentences with longer descriptive ones.
$styleGuide
${runningContext.isNotEmpty ? '\nCONTINUITY — The story so far ends with:\n"""\n...$runningContext\n"""\nYour prose MUST continue seamlessly from this text. The reader should feel zero discontinuity.' : ''}
$forwardHint

Output ONLY the prose text for this single beat, nothing else. No labels, no headers.''';

      final response = await _callLLM(
        prompt,
        maxLength: tier == PromptTier.smallLocal ? 4096 : 8192,
        temp: 0.85,
      );
      final cleanedResponse = _stripThinkTags(response).trim();

      project.prose[bId] = BeatProse(
        draft: cleanedResponse,
        final_: cleanedResponse,
      );

      // Update running context for the next beat
      runningContext = cleanedResponse;
      if (runningContext.length > 600) {
        runningContext = runningContext.substring(runningContext.length - 600);
      }

      // Save after each beat so progress isn't lost if something crashes
      await _repository.saveProject(project);
    }
  }

  /// Autopilot: run the entire pipeline from concept to finished prose.
  Future<void> runAutopilot(StoryProject project) async {
    try {
      // 1. Story Architect
      await runStoryArchitect(project);

      // 2. Act Structure
      await runActStructurer(project);

      // 3. Generate each act end-to-end
      for (int actIdx = 0; actIdx < project.acts.length; actIdx++) {
        await generateFullAct(project, actIdx);
      }

      _setStatus('Complete', 'Story generation finished!');
    } catch (e) {
      _setStatus('Error', 'Pipeline failed: $e');
      rethrow;
    }
  }

  // ── EXPORT ──────────────────────────────────────────────────────────

  /// Export the full story as plain text.
  String exportAsText(StoryProject project) {
    final buffer = StringBuffer();
    buffer.writeln(project.title.toUpperCase());
    buffer.writeln('=' * project.title.length);
    buffer.writeln();

    for (int actIdx = 0; actIdx < project.acts.length; actIdx++) {
      final act = project.acts[actIdx];
      buffer.writeln('\n${'─' * 40}');
      buffer.writeln('ACT ${act.number}: ${act.title.toUpperCase()}');
      buffer.writeln('${'─' * 40}\n');

      final scenes = project.scenes[actIdx] ?? [];
      for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
        final scene = scenes[sceneIdx];
        buffer.writeln('\nChapter ${scene.number}: ${scene.title}\n');

        final sId = '$actIdx-$sceneIdx';
        final beats = project.beats[sId] ?? [];
        for (int beatIdx = 0; beatIdx < beats.length; beatIdx++) {
          final bId = '$sId-$beatIdx';
          final prose = project.prose[bId];
          if (prose?.final_ != null) {
            buffer.writeln(prose!.final_);
            buffer.writeln();
          }
        }
      }
    }

    return buffer.toString();
  }

  /// Export the full story as Markdown.
  String exportAsMarkdown(StoryProject project) {
    final buffer = StringBuffer();
    buffer.writeln('# ${project.title}\n');

    for (int actIdx = 0; actIdx < project.acts.length; actIdx++) {
      final act = project.acts[actIdx];
      buffer.writeln('## Act ${act.number}: ${act.title}\n');

      final scenes = project.scenes[actIdx] ?? [];
      for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
        final scene = scenes[sceneIdx];
        buffer.writeln('### Chapter ${scene.number}: ${scene.title}\n');

        final sId = '$actIdx-$sceneIdx';
        final beats = project.beats[sId] ?? [];
        for (int beatIdx = 0; beatIdx < beats.length; beatIdx++) {
          final bId = '$sId-$beatIdx';
          final prose = project.prose[bId];
          if (prose?.final_ != null) {
            buffer.writeln(prose!.final_);
            buffer.writeln();
          }
        }
      }
    }

    return buffer.toString();
  }
}
