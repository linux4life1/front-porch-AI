// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../character_gen_service.dart';

/// After the greeting exists, seed ambitions / tastes / wardrobe (and
/// intimate prefs when 18+ is on) onto the card. Tools first when the
/// backend speaks them; text JSON is the floor. Failure is silent — the
/// Porch Life step stays editable either way.
extension GenPorchLife on CharacterGenService {
  Future<void> _seedPorchLifeIdentity({
    required CharacterCard card,
    required String name,
    required String interviewTranscript,
    required bool nsfwEnabled,
    void Function(String)? onProgress,
  }) async {
    final excerpt = interviewTranscript.length > 1400
        ? '${interviewTranscript.substring(0, 1400)}...'
        : interviewTranscript;
    final greeting = card.firstMessage.length > 800
        ? '${card.firstMessage.substring(0, 800)}...'
        : card.firstMessage;
    final intimateBlock = nsfwEnabled
        ? '- "intimate_into": 2-5 short suggestive tastes for 18+ scenes\n'
              '- "intimate_not_into": 2-4 hard limits / not interested\n'
        : 'Do NOT emit intimate_into or intimate_not_into.\n';

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

Keys (arrays of short phrases, one thing per string):
- "ambitions": 2-4 long-term goals across the whole story, not today's to-do
- "likes": 3-6 small specific things they warm to
- "dislikes": 2-4 things that make them bristle
- "worn": what they are wearing as the greeting opens. "sundress (rain-soaked)" is the shape
- "carrying": pockets and hands in that same opening beat
$intimateBlock
Rules: no {{user}}'s belongings. No paragraphs. Invent only what the scene already implies.

Respond with ONLY the JSON:''';

    Map<String, dynamic>? data;

    // Tools first — this is a short typed list, the shape tools exist for.
    // The rest of chargen stays text-only (streaming preview + long prose).
    try {
      final toolsResp = await _llmService.generateWithTools(
        GenerationParams(
          prompt: prompt,
          maxLength: 512,
          minLength: 16,
          temperature: 0.5,
          reasoningEnabled: false,
          reasoningMaxTokens: 0,
          toolChoice: kPorchLifeToolName,
        ),
        porchLifeToolSchema(nsfw: nsfwEnabled),
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
      final output = await _callLLM(
        prompt,
        maxLen: 768,
        minLen: 16,
        isJsonMode: true,
        onProgress: onProgress,
      );
      if (output != null) data = {'raw': output};
    }
    if (data == null) return;

    final identity = data.containsKey('raw')
        ? parsePorchLifeIdentity(data['raw'], nsfw: nsfwEnabled)
        : parsePorchLifeIdentity(data, nsfw: nsfwEnabled);
    final prior =
        card.frontPorchExtensions ??
        FrontPorchExtensions(needsSimEnabled: true);
    card.frontPorchExtensions = prior.copyWith(
      ambitions: identity.ambitions,
      likes: identity.likes,
      dislikes: identity.dislikes,
      intimateInto: identity.intimateInto,
      intimateNotInto: identity.intimateNotInto,
      inventory: Pockets.cardJsonFrom(
        worn: identity.worn,
        carrying: identity.carrying,
      ),
    );
    debugPrint(
      'CharacterGen: Porch Life seeded '
      'ambitions=${identity.ambitions.length} worn=${identity.worn.length} '
      'carrying=${identity.carrying.length} intimate=${identity.intimateInto.length}',
    );
  }
}
