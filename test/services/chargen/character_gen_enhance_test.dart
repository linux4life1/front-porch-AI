// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// AI Enhance pipeline: which stages fire per field selection, whether the chat
// grounding actually reaches the prompts (the call-site pin — deleting the
// injection must turn this suite red), and whether unselected fields survive
// the shared enrichment call untouched.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_gen_service.dart';
import 'package:front_porch_ai/services/chargen/chat_grounding.dart';
import 'package:front_porch_ai/services/llm_service.dart';

const _grounding = 'User: hello Nina\nNina: well well, look who wandered in';

const _newDescription =
    'A tall woman with calloused hands and a crooked smile, always in the same '
    'worn leather jacket she refuses to replace no matter the season.';
const _newPersonality =
    'Sharp-tongued but secretly soft; she deflects sincerity with bar jokes '
    'and only drops the act around people who have earned it over months.';
const _newScenario =
    'The bar is closing and {{char}} has locked the door with {{user}} still '
    'inside, a bottle of the good stuff already on the counter between them.';

/// Scripted LLM that answers by prompt shape and records every prompt.
class _RoutedLlm extends LLMService {
  final List<String> prompts = [];
  CharacterGenService? abortAfterFirst;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    prompts.add(params.prompt);
    if (abortAfterFirst != null && prompts.length == 1) {
      abortAfterFirst!.abort();
    }
    yield _answer(params.prompt);
  }

  String _answer(String p) {
    if (p.contains('rewrite these three fields')) {
      return jsonEncode({
        'description': _newDescription,
        'personality': _newPersonality,
        'scenario': _newScenario,
      });
    }
    if (p.contains('Write example dialogue exchanges')) {
      return '<START>\n{{user}}: rough night?\n{{char}}: *she slides a glass '
          'over* Rough decade, sugar. But you buying me a drink helps.';
    }
    if (p.contains('completely different meeting scenarios')) {
      return jsonEncode({
        'scenarios': ['A rainy rooftop where {{user}} finds {{char}} feeding strays.'],
      });
    }
    if (p.contains('WORLD-BUILDING lorebook entries')) {
      return jsonEncode({
        'lorebook': [
          {
            'name': 'The Bar',
            'key': 'bar, drinks',
            'secondary': '',
            'content': 'A dim dockside bar where every regular owes her a favor.',
            'category': 'premise',
          },
        ],
      });
    }
    if (p.contains('Write an opening roleplay message')) {
      if (p.contains('COMPLETELY DIFFERENT')) {
        return 'Get out.';
      }
      return 'The neon buzzed over the empty stools as I counted the till. '
          '"We\'re closed," I said — then saw it was {{user}} at the door.';
    }
    // Interview answer.
    return 'I talk like the bar taught me: fast, warm, and armored. Ask the '
        'regulars — they know my voice better than my name.';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'routed-test';
}

CharacterCard _sourceCard() => CharacterCard(
      name: 'Nina',
      description: 'Original description of Nina.',
      personality: 'Original personality of Nina.',
      scenario: 'Original scenario: a quiet bar after hours, {{user}} walks in.',
      firstMessage: 'Original first message.',
      mesExample: '<START>\n{{user}}: hi\n{{char}}: original example',
      alternateGreetings: ['Original alt greeting.'],
    );

void main() {
  test('dialogue-only run fires interview + dialogue and nothing else',
      () async {
    final llm = _RoutedLlm();
    final gen = CharacterGenService(llm);
    final source = _sourceCard();
    final result = await gen.enhanceCharacter(
      source: source,
      selection: const EnhanceSelection(
        description: false,
        personality: false,
        exampleDialogue: true,
      ),
      chatGrounding: _grounding,
    );

    expect(result, isNotNull);
    // 7 interview questions (no relationship, nsfw off) + 1 dialogue call.
    expect(llm.prompts.where((p) => p.contains('Question:')).length, 7);
    expect(
      llm.prompts.where((p) => p.contains('Write example dialogue exchanges')),
      hasLength(1),
    );
    expect(
      llm.prompts.where((p) => p.contains('rewrite these three fields')),
      isEmpty,
      reason: 'enrichment must be skipped when no persona field is selected',
    );
    expect(
      llm.prompts.where((p) => p.contains('Write an opening roleplay message')),
      isEmpty,
    );
    expect(
      llm.prompts.where((p) => p.contains('WORLD-BUILDING lorebook entries')),
      isEmpty,
    );

    // Only the selected field changed.
    expect(result!.mesExample, contains('Rough decade'));
    expect(result.description, source.description);
    expect(result.personality, source.personality);
    expect(result.scenario, source.scenario);
    // Untouched carriers pass through verbatim.
    expect(result.firstMessage, source.firstMessage);
    expect(result.alternateGreetings, source.alternateGreetings);
    expect(result.lorebook, isNull);
  });

  test('CALL-SITE PIN: chat grounding reaches every stage prompt', () async {
    final llm = _RoutedLlm();
    final gen = CharacterGenService(llm);
    final result = await gen.enhanceCharacter(
      source: _sourceCard(),
      selection: const EnhanceSelection(
        exampleDialogue: true,
        greetings: true,
        lorebook: true,
      ),
      chatGrounding: _grounding,
    );
    expect(result, isNotNull);

    for (final p in llm.prompts.where((p) => p.contains('Question:'))) {
      expect(p, contains('ACTUALLY been played'),
          reason: 'interview seed lost its grounding section');
      expect(p, contains(_grounding));
    }
    final enrich =
        llm.prompts.singleWhere((p) => p.contains('rewrite these three fields'));
    expect(enrich, contains('REAL CHAT EXCERPTS'));
    expect(enrich, contains(_grounding));

    final dialogue = llm.prompts
        .singleWhere((p) => p.contains('Write example dialogue exchanges'));
    expect(dialogue, contains('REAL CHAT LINES'));
    expect(dialogue, contains(_grounding));

    // Greetings ride the existing characterContext seam...
    for (final p in llm.prompts
        .where((p) => p.contains('Write an opening roleplay message'))) {
      expect(p, contains('Character Details (weave these naturally'));
      expect(p, contains(_grounding));
    }
    // ...and the lorebook rides the existing worldLore seam.
    final lore = llm.prompts
        .singleWhere((p) => p.contains('WORLD-BUILDING lorebook entries'));
    expect(lore, contains('[ESTABLISHED WORLD LORE]'));
    expect(lore, contains(_grounding));
  });

  test('unselected description/personality revert after shared enrichment',
      () async {
    final llm = _RoutedLlm();
    final gen = CharacterGenService(llm);
    final source = _sourceCard();
    final result = await gen.enhanceCharacter(
      source: source,
      selection: const EnhanceSelection(
        description: true,
        personality: false,
        exampleDialogue: false,
      ),
      chatGrounding: _grounding,
    );

    expect(result, isNotNull);
    expect(result!.description, _newDescription);
    expect(result.personality, source.personality,
        reason: 'unselected personality must revert to the source value');
    expect(result.scenario, source.scenario,
        reason: 'unselected scenario rides the preserveUserScenario gate');
  });

  test('selected scenario is rewritten', () async {
    final llm = _RoutedLlm();
    final gen = CharacterGenService(llm);
    final result = await gen.enhanceCharacter(
      source: _sourceCard(),
      selection: const EnhanceSelection(scenario: true),
      chatGrounding: _grounding,
    );
    expect(result!.scenario, _newScenario);
  });

  test('greetings run regenerates first message + one alt (source had one)',
      () async {
    final llm = _RoutedLlm();
    final gen = CharacterGenService(llm);
    final result = await gen.enhanceCharacter(
      source: _sourceCard(),
      selection: const EnhanceSelection(
        description: false,
        personality: false,
        exampleDialogue: false,
        greetings: true,
      ),
      chatGrounding: _grounding,
    );
    expect(result!.firstMessage, contains('neon buzzed'));
    expect(result.alternateGreetings, hasLength(1));
    expect(
      llm.prompts.where((p) => p.contains('Write an opening roleplay message')),
      hasLength(2),
    );
  });

  test('abort mid-interview returns null', () async {
    final llm = _RoutedLlm();
    final gen = CharacterGenService(llm);
    llm.abortAfterFirst = gen;
    final result = await gen.enhanceCharacter(
      source: _sourceCard(),
      selection: const EnhanceSelection(),
      chatGrounding: _grounding,
    );
    expect(result, isNull);
  });

  test('empty selection returns null without any LLM call', () async {
    final llm = _RoutedLlm();
    final gen = CharacterGenService(llm);
    final result = await gen.enhanceCharacter(
      source: _sourceCard(),
      selection: const EnhanceSelection(
        description: false,
        personality: false,
        exampleDialogue: false,
      ),
      chatGrounding: _grounding,
    );
    expect(result, isNull);
    expect(llm.prompts, isEmpty);
  });

  test('source card is never mutated', () async {
    final llm = _RoutedLlm();
    final gen = CharacterGenService(llm);
    final source = _sourceCard();
    await gen.enhanceCharacter(
      source: source,
      selection: const EnhanceSelection(),
      chatGrounding: _grounding,
    );
    expect(source.description, 'Original description of Nina.');
    expect(source.personality, 'Original personality of Nina.');
    expect(source.mesExample, contains('original example'));
  });

  test(
    'greetings rewrite to Get out drops leftover source furious',
    () async {
      final llm = _RoutedLlm();
      final gen = CharacterGenService(llm);
      final furious = GreetingRealismSeed(characterEmotion: 'furious');
      final source = CharacterCard(
        name: 'Nina',
        description: 'Original description of Nina.',
        personality: 'Original personality of Nina.',
        scenario:
            'Original scenario: a quiet bar after hours, {{user}} walks in.',
        firstMessage: 'Original first message.',
        mesExample: '<START>\n{{user}}: hi\n{{char}}: original example',
        alternateGreetings: ['Stay.'],
        frontPorchExtensions: FrontPorchExtensions(greetingSeeds: [furious]),
      );
      final result = await gen.enhanceCharacter(
        source: source,
        selection: const EnhanceSelection(
          description: false,
          personality: false,
          exampleDialogue: false,
          greetings: true,
          porchLife: true,
        ),
        chatGrounding: _grounding,
      );
      expect(result, isNotNull);
      expect(result!.alternateGreetings, ['Get out.']);
      expect(
        result.frontPorchExtensions!.greetingSeeds,
        isEmpty,
        reason:
            "['Get out.'] omit seeds must not reuse unpaired source [furious]",
      );
      expect(
        greetingOverlayAt(result.frontPorchExtensions!.greetingSeeds, 1),
        isNull,
        reason: 'Get out overlay is not leftover furious',
      );
      expect(
        source.frontPorchExtensions!.greetingSeeds.single!.characterEmotion,
        'furious',
        reason: 'source leftover must stay on the original card',
      );
    },
  );

  test(
    'character_gen_enhance copyWith leftover furious does not land on Get out',
    () {
      final leftover = GreetingRealismSeed(characterEmotion: 'furious');
      final sourceExt = FrontPorchExtensions(greetingSeeds: [leftover]);
      final card = CharacterCard(
        name: 'Nina',
        alternateGreetings: ['Get out.'],
      );
      expect(
        sourceExt.copyWith().greetingSeeds.single!.characterEmotion,
        'furious',
        reason: 'bare copyWith keeps leftover source [furious]',
      );
      card.frontPorchExtensions = sourceExt.copyWith(
        greetingSeeds: compactRewrittenGreetingAlts(
          card.alternateGreetings,
          card.frontPorchExtensions?.greetingSeeds,
        ).seeds,
      );
      expect(card.alternateGreetings, ['Get out.']);
      expect(
        card.frontPorchExtensions!.greetingSeeds,
        isEmpty,
        reason:
            "copyWith(['Get out.'], omit seeds) must not load leftover [furious]",
      );
      expect(
        greetingOverlayAt(card.frontPorchExtensions!.greetingSeeds, 1),
        isNull,
        reason: 'Get out overlay is not leftover furious',
      );
      expect(leftover.characterEmotion, 'furious');
    },
  );

  test(
    'character_gen_enhance copyWith authored seeds still pair on Get out',
    () {
      final leftover = GreetingRealismSeed(characterEmotion: 'furious');
      final sourceExt = FrontPorchExtensions(greetingSeeds: [leftover]);
      final authored = [GreetingRealismSeed(characterEmotion: 'cold')];
      final card = CharacterCard(
        name: 'Nina',
        alternateGreetings: ['Get out.'],
        frontPorchExtensions: FrontPorchExtensions(greetingSeeds: authored),
      );
      card.frontPorchExtensions = sourceExt.copyWith(
        greetingSeeds: compactRewrittenGreetingAlts(
          card.alternateGreetings,
          card.frontPorchExtensions?.greetingSeeds,
        ).seeds,
      );
      expect(card.alternateGreetings, ['Get out.']);
      expect(
        card.frontPorchExtensions!.greetingSeeds.single!.characterEmotion,
        'cold',
      );
      expect(
        greetingOverlayAt(card.frontPorchExtensions!.greetingSeeds, 1)!
            .characterEmotion,
        'cold',
      );
    },
  );
}
