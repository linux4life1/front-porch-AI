// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The AI creator's Porch Life seed must survive two transports (tools args
// and messy text JSON) and must NEVER leak intimate lists when 18+ is off.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/character_gen_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';

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
