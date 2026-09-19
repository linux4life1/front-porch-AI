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
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show Pockets;

part 'chargen/character_gen_llm.dart';
part 'chargen/character_gen_prompts.dart';
part 'chargen/character_gen_steps.dart';
part 'chargen/character_gen_steps2.dart';
part 'chargen/character_gen_parsing.dart';
part 'chargen/character_gen_enhance.dart';
part 'chargen/character_gen_porch_life.dart';
part 'chargen/character_gen_generate.dart';

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
    'Now describe your physical appearance in your own words — what you look like, '
    'how you carry yourself, and what you are wearing and carrying in this opening '
    'scene. Be specific.';

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

  /// Greeting + example-dialog voice. Default first-person present matches
  /// the historical baked-in prompts. Set at the start of each generate run.
  NarrativeVoice _narrativeVoice = NarrativeVoice.defaults;
  String _narrativeSex = '';

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
}
