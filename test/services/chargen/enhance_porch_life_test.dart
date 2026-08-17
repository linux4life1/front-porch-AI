// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Enhance proposes Porch Life the same way it proposes description: only
// when selected, and the result rides frontPorchExtensions so Review can
// keep or accept. Unticked = no extra call and the original lists stay off
// the working card.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_gen_service.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/llm_service.dart';

const _grounding = 'User: hey Nina\nNina: wipe the flour off and come in';

void main() {
  test('porchLife selected stamps a proposal on the result card', () async {
    final llm = _EnhancePorchLlm();
    final gen = CharacterGenService(llm);
    final result = await gen.enhanceCharacter(
      source: CharacterCard(
        name: 'Nina',
        description: 'A baker.',
        personality: 'Hungry and kind.',
        firstMessage: 'I wipe flour off the apron.',
        frontPorchExtensions: FrontPorchExtensions(
          ambitions: const ['old goal'],
          inventory: const {
            'worn': ['old coat'],
          },
        ),
      ),
      selection: const EnhanceSelection(
        description: false,
        personality: false,
        exampleDialogue: false,
        porchLife: true,
      ),
      chatGrounding: _grounding,
    );

    expect(result, isNotNull);
    expect(
      llm.prompts.any((p) => p.contains('Seed Porch Life identity')),
      isTrue,
    );
    expect(result!.frontPorchExtensions?.ambitions, ['stay fed']);
    expect(porchLifeIdentityOf(result.frontPorchExtensions).worn, [
      'flour-dusted apron',
    ]);
  });

  test(
    'porchLife off does not seed and leaves extensions off the result',
    () async {
      final llm = _EnhancePorchLlm();
      final gen = CharacterGenService(llm);
      final result = await gen.enhanceCharacter(
        source: CharacterCard(
          name: 'Nina',
          description: 'A baker.',
          personality: 'Hungry and kind.',
          firstMessage: 'I wipe flour off the apron.',
          frontPorchExtensions: FrontPorchExtensions(
            ambitions: const ['old goal'],
          ),
        ),
        selection: const EnhanceSelection(
          description: false,
          personality: false,
          exampleDialogue: true,
        ),
        chatGrounding: _grounding,
      );

      expect(result, isNotNull);
      expect(
        llm.prompts.any((p) => p.contains('Seed Porch Life identity')),
        isFalse,
      );
      expect(result!.frontPorchExtensions, isNull);
    },
  );

  for (final mute in ['{}', 'thanks']) {
    test(
      'mute "$mute" empties the proposal identity, not the source card',
      () async {
        final source = CharacterCard(
          name: 'Nina',
          description: 'A baker.',
          personality: 'Hungry and kind.',
          firstMessage: 'I wipe flour off the apron.',
          frontPorchExtensions: FrontPorchExtensions(
            ambitions: const ['old goal'],
            inventory: const {
              'worn': ['old coat'],
            },
          ),
        );
        final llm = _EnhancePorchLlm(porchReply: mute);
        final gen = CharacterGenService(llm);
        final result = await gen.enhanceCharacter(
          source: source,
          selection: const EnhanceSelection(
            description: false,
            personality: false,
            exampleDialogue: false,
            porchLife: true,
          ),
          chatGrounding: _grounding,
        );

        expect(result, isNotNull);
        expect(
          llm.prompts.any((p) => p.contains('Seed Porch Life identity')),
          isTrue,
        );
        expect(
          porchLifeIdentityOf(result!.frontPorchExtensions).isEmpty,
          isTrue,
        );
        expect(source.frontPorchExtensions?.ambitions, ['old goal']);
        expect(porchLifeIdentityOf(source.frontPorchExtensions).worn, [
          'old coat',
        ]);
      },
    );
  }
}

class _EnhancePorchLlm extends LLMService {
  _EnhancePorchLlm({this.porchReply});

  /// When set, the Porch Life seed yields this text instead of a valid JSON
  /// proposal — mute (`{}`) and garbage (`thanks`) both parse to isEmpty.
  final String? porchReply;
  final prompts = <String>[];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    prompts.add(params.prompt);
    if (params.prompt.contains('Seed Porch Life identity')) {
      yield porchReply ??
          '{"ambitions":["stay fed"],"likes":["hot coffee"],'
              '"dislikes":["being interrupted"],"worn":["flour-dusted apron"],'
              '"carrying":["shop keys"]}';
      return;
    }
    if (params.prompt.contains('Write example dialogue exchanges')) {
      yield '<START>\n{{user}}: hi\n{{char}}: come in.';
      return;
    }
    yield 'I talk like the kitchen taught me: short, warm, and tired.';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'enhance-porch-test';
}
