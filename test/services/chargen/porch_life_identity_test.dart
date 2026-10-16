// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The AI creator's Porch Life seed must survive two transports (tools args
// and messy text JSON) and must NEVER leak intimate lists when 18+ is off.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/character_gen/character_gen.dart';
import 'package:front_porch_ai/services/character_gen_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';

import 'support/marker_chargen_llm.dart';

void main() {
  group('parsePorchLifeIdentity', () {
    test('reads tool-shaped arguments', () {
      final id = parsePorchLifeIdentity({
        'ambitions': ['open a bakery'],
        'likes': ['thunderstorms'],
        'dislikes': ['being interrupted'],
        'worn': ['flour-dusted apron'],
        'carrying': ['shop keys'],
        'intimate_into': ['slow mornings'],
        'intimate_not_into': ['an audience'],
      }, nsfw: true);

      expect(id.ambitions, ['open a bakery']);
      expect(id.worn, ['flour-dusted apron']);
      expect(id.carrying, ['shop keys']);
      expect(id.intimateInto, ['slow mornings']);
      expect(id.intimateNotInto, ['an audience']);
    });

    test('drops intimate lists when 18+ is off', () {
      final id = parsePorchLifeIdentity({
        'ambitions': ['get out of this town'],
        'worn': ['leather jacket'],
        'intimate_into': ['should never land'],
        'intimate_not_into': ['also never'],
      }, nsfw: false);

      expect(id.ambitions, ['get out of this town']);
      expect(id.worn, ['leather jacket']);
      expect(id.intimateInto, isEmpty);
      expect(id.intimateNotInto, isEmpty);
    });

    test('salvages arrays from mangled JSON text', () {
      const blob = '''
here you go
{"ambitions": ["stay solvent"], "likes": ["hot coffee"], "worn": ["sundress (rain-soaked)"], "carrying": ["car keys"]}
thanks
''';
      final id = parsePorchLifeIdentity(blob, nsfw: false);
      expect(id.ambitions, ['stay solvent']);
      expect(id.worn, ['sundress (rain-soaked)']);
      expect(id.carrying, ['car keys']);
    });

    test('drops {{user}} belongings and caps the list', () {
      final id = parsePorchLifeIdentity({
        'carrying': [
          "{{user}}'s wallet",
          'car keys',
          for (var i = 0; i < 12; i++) 'thing $i',
        ],
      }, nsfw: false);
      expect(id.carrying, isNot(contains("{{user}}'s wallet")));
      expect(id.carrying.length, lessThanOrEqualTo(8));
      expect(id.carrying.first, 'car keys');
    });

    test('isEmpty is all seven lists empty — mute JSON included', () {
      expect(const PorchLifeIdentity().isEmpty, isTrue);
      expect(parsePorchLifeIdentity('{}', nsfw: false).isEmpty, isTrue);
      expect(parsePorchLifeIdentity('thanks', nsfw: false).isEmpty, isTrue);
      expect(
        parsePorchLifeIdentity({
          'ambitions': ['stay fed'],
        }, nsfw: false).isEmpty,
        isFalse,
      );
    });
  });

  group('applyPorchLifeProposal', () {
    final authored = FrontPorchExtensions(
      ambitions: const ['old goal'],
      inventory: const {
        'worn': ['old coat'],
      },
    );

    test('mute/empty proposal does not drop authored old coat', () {
      final out = applyPorchLifeProposal(authored, const PorchLifeIdentity());
      final id = porchLifeIdentityOf(out);
      expect(id.ambitions, ['old goal']);
      expect(id.worn, ['old coat']);
    });

    test('ambitions-only proposal does not replace authored worn', () {
      final out = applyPorchLifeProposal(
        authored,
        const PorchLifeIdentity(ambitions: ['stay fed']),
      );
      final id = porchLifeIdentityOf(out);
      expect(id.ambitions, ['stay fed']);
      expect(id.worn, ['old coat']);
    });
  });

  group('generateCharacter seeds Porch Life', () {
    test('text-JSON floor lands on the card', () async {
      final llm = _PorchLifeLlm(tools: false);
      final gen = CharacterGenService(llm);
      final card = await gen.generateCharacter(
        name: 'Nina',
        concept: 'a tired pickpocket who just wants a sandwich',
        generateLorebook: false,
        altGreetingCount: 0,
        generateDescription: true,
        nsfwEnabled: false,
      );

      expect(card, isNotNull);
      expect(llm.askedForTools, isTrue);
      expect(card!.frontPorchExtensions?.ambitions, ['stay fed']);
      expect(card.frontPorchExtensions?.inventory['worn'], isNotEmpty);
    });

    test('tools transport wins and 18+ lists land only when asked', () async {
      final llm = _PorchLifeLlm(tools: true);
      final gen = CharacterGenService(llm);
      final card = await gen.generateCharacter(
        name: 'Nina',
        concept: 'a tired pickpocket',
        generateLorebook: false,
        altGreetingCount: 0,
        generateDescription: true,
        nsfwEnabled: true,
      );

      expect(card, isNotNull);
      expect(llm.textFallbackCalls, 0);
      expect(card!.frontPorchExtensions?.intimateInto, ['slow mornings']);
      expect(card.frontPorchExtensions?.ambitions, ['stay fed']);
    });
  });

  group('opening scene read (identityDone)', () {
    test('mood and time are read and validated', () {
      final ok = parsePorchLifeIdentity({
        'character_emotion': ' Wary ',
        'emotion_intensity': 'Strong',
        'time_of_day': 'late morning',
        'story_start_time': '7:05',
      }, nsfw: false);
      expect(ok.characterEmotion, 'wary');
      expect(ok.emotionIntensity, 'strong');
      expect(ok.timeOfDay, 'late_morning');
      expect(ok.storyStartTime, '07:05');

      final bad = parsePorchLifeIdentity({
        'character_emotion': '{{user}} is sad',
        'emotion_intensity': 'extreme',
        'time_of_day': 'noonish',
        'story_start_time': '25:00',
      }, nsfw: false);
      expect(bad.characterEmotion, '');
      expect(bad.emotionIntensity, '');
      expect(bad.timeOfDay, '');
      expect(bad.storyStartTime, '');
    });

    test('mood and time survive mangled text', () {
      const blob =
          'ok {"worn": ["coat"], "character_emotion": "tired", '
          '"time_of_day": "evening", "story_start_time": "19:30", "x": "a"b"}';
      final id = parsePorchLifeIdentity(blob, nsfw: false);
      expect(id.worn, ['coat']);
      expect(id.characterEmotion, 'tired');
      expect(id.timeOfDay, 'evening');
      expect(id.storyStartTime, '19:30');
    });

    Set<String> keys(List<Map<String, dynamic>> schema) =>
        ((schema.single['function'] as Map)['parameters'] as Map)['properties']
            .keys
            .cast<String>()
            .toSet();

    test('identityDone asks only what the greeting decides', () {
      expect(keys(porchLifeToolSchema(nsfw: true, identityDone: true)), {
        'worn',
        'carrying',
        'character_emotion',
        'emotion_intensity',
        'time_of_day',
        'story_start_time',
      });
    });

    test('the default schema keeps its keys', () {
      expect(keys(porchLifeToolSchema(nsfw: true)), {
        'ambitions',
        'likes',
        'dislikes',
        'worn',
        'carrying',
        'intimate_into',
        'intimate_not_into',
      });
    });

    test('an empty read keeps the lists the facts pass wrote, and the '
        'mood and time land', () async {
      final llm = MarkerChargenLlm(
        toolAnswers: {
          kPorchLifeToolName: {
            'worn': ['rain-soaked coat'],
            'carrying': <String>[],
            'character_emotion': 'wary',
            'emotion_intensity': 'moderate',
            'time_of_day': 'evening',
            'story_start_time': '19:30',
          },
        },
      );
      final card = CharacterCard(
        name: 'Nina',
        firstMessage: 'I shake the rain off.',
        frontPorchExtensions: FrontPorchExtensions(
          ambitions: const ['stay fed'],
          likes: const ['hot coffee'],
          inventory: const {
            'carrying': ['shop keys'],
          },
        ),
      );
      await GenStages(GenRunState(llm)).porchLife.seedIdentity(
        card: card,
        name: 'Nina',
        interviewTranscript: '',
        nsfwEnabled: false,
        identityDone: true,
      );
      final ext = card.frontPorchExtensions!;
      expect(ext.ambitions, ['stay fed']);
      expect(ext.likes, ['hot coffee']);
      expect(porchLifeIdentityOf(ext).worn, ['rain-soaked coat']);
      expect(porchLifeIdentityOf(ext).carrying, ['shop keys']);
      expect(ext.characterEmotion, 'wary');
      expect(ext.emotionIntensity, 'moderate');
      expect(ext.timeOfDay, 'evening');
      expect(ext.storyStartTime, '19:30');
    });
  });
}

/// Answers every chargen stage with a valid base card, and the Porch Life
/// extract with either a tool call or a text JSON object.
class _PorchLifeLlm extends LLMService {
  _PorchLifeLlm({required this.tools});

  final bool tools;
  bool askedForTools = false;
  int textFallbackCalls = 0;

  static const _card = '''
{"description":"A wiry woman in a flour-dusted apron.","personality":"Hungry, sharp, kind under it.","scenario":"{{char}} is counting tips at the counter.","first_message":"I wipe flour off the apron and nod you in.","example_dialogue":"{{user}}: hi\\n{{char}}: yeah.","tags":["baker"]}
''';

  static const _porch = {
    'ambitions': ['stay fed'],
    'likes': ['hot coffee'],
    'dislikes': ['being interrupted'],
    'worn': ['flour-dusted apron'],
    'carrying': ['shop keys'],
    'intimate_into': ['slow mornings'],
    'intimate_not_into': ['an audience'],
  };

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.prompt.contains('Seed Porch Life identity')) {
      textFallbackCalls++;
      yield '{"ambitions":["stay fed"],"likes":["hot coffee"],"dislikes":["being interrupted"],"worn":["flour-dusted apron"],"carrying":["shop keys"]}';
      return;
    }
    yield _card;
  }

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> toolSchemas,
  ) async {
    askedForTools = true;
    if (!tools) return null;
    return LlmToolResponse(
      calls: [
        LlmToolCall(name: kPorchLifeToolName, arguments: Map.from(_porch)),
      ],
      text: '',
    );
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'porch-life-test';
}
