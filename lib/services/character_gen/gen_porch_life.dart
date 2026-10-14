// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_gen/gen_llm_caller.dart';
import 'package:front_porch_ai/services/character_gen/gen_run_state.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show Pockets, StoryClock;
import 'package:front_porch_ai/services/llm_service.dart';

/// After the greeting exists, seed ambitions / tastes / wardrobe (and
/// intimate prefs when 18+ is on) onto the card. Tools first when the
/// backend speaks them; text JSON is the floor. Failure is silent — the
/// Porch Life step stays editable either way.
class GenPorchLife {
  GenPorchLife(this._state, this._llm);

  final GenRunState _state;
  final GenLlmCaller _llm;

  /// Read the opening scene and write it onto [card]. [identityDone]: the
  /// identity facts pass already wrote the lists, so this asks only for the
  /// outfit, pockets, mood and time. Either way an empty answer keeps what
  /// the card had: a mute read never wipes a list.
  Future<void> seedIdentity({
    required CharacterCard card,
    required String name,
    required String interviewTranscript,
    required bool nsfwEnabled,
    bool identityDone = false,
    void Function(String)? onProgress,
  }) async {
    final identity = await readIdentity(
      card: card,
      name: name,
      interviewTranscript: interviewTranscript,
      nsfwEnabled: nsfwEnabled,
      identityDone: identityDone,
      onProgress: onProgress,
    );
    if (identity == null) return;
    final prior =
        card.frontPorchExtensions ??
        FrontPorchExtensions(needsSimEnabled: true);
    final merged = mergePorchLifeIdentity(porchLifeIdentityOf(prior), identity);
    final outfitRead = identity.worn.isNotEmpty || identity.carrying.isNotEmpty;
    String? scene(String v) => v.isEmpty ? null : v;
    card.frontPorchExtensions = prior.copyWith(
      ambitions: merged.ambitions,
      likes: merged.likes,
      dislikes: merged.dislikes,
      intimateInto: merged.intimateInto,
      intimateNotInto: merged.intimateNotInto,
      inventory: outfitRead || prior.inventory.isEmpty
          ? Pockets.cardJsonFrom(worn: merged.worn, carrying: merged.carrying)
          : null,
      characterEmotion: scene(identity.characterEmotion),
      emotionIntensity: scene(identity.emotionIntensity),
      timeOfDay: scene(identity.timeOfDay),
      storyStartTime: scene(identity.storyStartTime),
    );
    debugPrint(
      'CharacterGen: Porch Life seeded '
      'ambitions=${identity.ambitions.length} worn=${identity.worn.length} '
      'carrying=${identity.carrying.length} '
      'intimate=${identity.intimateInto.length} '
      'mood=${identity.characterEmotion} time=${identity.timeOfDay}',
    );
  }

  /// The extraction itself: what [card]'s first message shows (and the
  /// interview implies), read by the model. Null when it answered nothing.
  /// The Greetings step's outfit re-read runs this same pass.
  Future<PorchLifeIdentity?> readIdentity({
    required CharacterCard card,
    required String name,
    required String interviewTranscript,
    required bool nsfwEnabled,
    bool identityDone = false,
    void Function(String)? onProgress,
  }) async {
    final excerpt = capInterview(interviewTranscript);
    final greeting = card.firstMessage.length > 800
        ? '${card.firstMessage.substring(0, 800)}...'
        : card.firstMessage;
    final intimateBlock = nsfwEnabled
        ? '- "intimate_into": 2-5 short suggestive tastes for 18+ scenes\n'
              '- "intimate_not_into": 2-4 hard limits / not interested\n'
        : 'Do NOT emit intimate_into or intimate_not_into.\n';
    final keys = identityDone
        ? _openingSceneKeys(card.scenario)
        : '''Keys (arrays of short phrases, one thing per string):
- "ambitions": 2-4 long-term goals across the whole story, not today's to-do
- "likes": 3-6 small specific things they warm to
- "dislikes": 2-4 things that make them bristle
- "worn": what they are wearing as the greeting opens. "sundress (rain-soaked)" is the shape
- "carrying": pockets and hands in that same opening beat
$intimateBlock''';

    final prompt =
        '''Seed Porch Life identity lists for $name. Output ONLY a JSON object.
No markdown. No explanation.

OPENING GREETING (wardrobe MUST match what this scene shows):
$greeting

APPEARANCE / PERSONALITY (excerpt):
${card.description.length > 500 ? card.description.substring(0, 500) : card.description}

${card.personality.length > 400 ? card.personality.substring(0, 400) : card.personality}

INTERVIEW (their own words):
$excerpt

$keys
Rules: no {{user}}'s belongings. No paragraphs. Invent only what the scene already implies.

Respond with ONLY the JSON:''';

    Map<String, dynamic>? data;

    // Tools first — this is a short typed list, the shape tools exist for.
    // The rest of chargen stays text-only (streaming preview + long prose).
    try {
      final toolsResp = await _state.llm.generateWithTools(
        GenerationParams(
          prompt: prompt,
          maxLength: 512,
          minLength: 16,
          temperature: 0.5,
          reasoningEnabled: false,
          reasoningMaxTokens: 0,
          mandatoryReasoningHeadroom: true,
          toolChoice: kPorchLifeToolName,
        ),
        porchLifeToolSchema(nsfw: nsfwEnabled, identityDone: identityDone),
      );
      if (toolsResp != null) {
        for (final call in toolsResp.calls) {
          if (call.name == kPorchLifeToolName) {
            data = Map<String, dynamic>.from(call.arguments);
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('CharacterGen: Porch Life tools miss ($e) — text floor');
    }

    if (data == null) {
      final output = await _llm.call(
        prompt,
        maxLen: 768,
        minLen: 16,
        isJsonMode: true,
        onProgress: onProgress,
      );
      if (output != null) data = {'raw': output};
    }
    if (data == null) return null;

    return data.containsKey('raw')
        ? parsePorchLifeIdentity(data['raw'], nsfw: nsfwEnabled)
        : parsePorchLifeIdentity(data, nsfw: nsfwEnabled);
  }

  /// The keys the greeting decides, once the facts pass wrote the lists.
  String _openingSceneKeys(String scenario) =>
      '''SCENARIO (when and where the greeting takes place):
$scenario

Keys:
- "worn": array, what they are wearing as the greeting opens. "sundress (rain-soaked)" is the shape
- "carrying": array, pockets and hands in that same opening beat
- "character_emotion": one word for how they feel as the greeting opens
- "emotion_intensity": mild, moderate or strong
- "time_of_day": one of ${StoryClock.periods.join(', ')}
- "story_start_time": the clock as the greeting opens, 24-hour "HH:MM"
''';
}
