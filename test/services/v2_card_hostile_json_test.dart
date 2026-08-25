// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A card downloaded from a community site is a stranger's upload. One
// wrong-typed element used to throw out of the whole `parseCardJson` factory,
// which returned null — and the file importer then persisted a filename-named
// EMPTY character while telling the user "Character imported successfully!".
// These guards pin the coercion, field by field.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';

void main() {
  late V2CardService service;

  setUp(() => service = V2CardService());

  Map<String, dynamic> cardWith(Map<String, dynamic> extra) => {
    'spec': 'chara_card_v2',
    'data': {
      'name': 'Marisol',
      'description': 'A woman who runs the corner bakery.',
      'first_mes': 'You again.',
      ...extra,
    },
  };

  test('a null element inside tags does not lose the card', () {
    final card = service.parseCardJson(
      jsonEncode(
        cardWith({
          'tags': ['romance', null, 'slice-of-life'],
        }),
      ),
    );

    expect(card, isNotNull, reason: 'one bad tag must not drop the whole card');
    expect(card!.name, 'Marisol');
    expect(card.description, 'A woman who runs the corner bakery.');
    expect(card.tags, ['romance', 'slice-of-life']);
  });

  test('numeric tags and greetings are coerced, not fatal', () {
    final card = service.parseCardJson(
      jsonEncode(
        cardWith({
          'tags': [1, 'romance'],
          'alternate_greetings': ['Hey.', 42],
        }),
      ),
    );

    expect(card, isNotNull);
    expect(card!.tags, ['1', 'romance']);
    expect(card.alternateGreetings, ['Hey.', '42']);
  });

  test('a bare string where a list belongs becomes a one-entry list', () {
    final card = service.parseCardJson(
      jsonEncode(cardWith({'tags': 'romance'})),
    );

    expect(card, isNotNull);
    expect(card!.tags, ['romance']);
    expect(card.name, 'Marisol');
  });

  test('a numeric name keeps every other field', () {
    final card = service.parseCardJson(
      jsonEncode(cardWith({'name': 123, 'personality': 'Warm, tired.'})),
    );

    expect(card, isNotNull);
    expect(card!.name, '123');
    expect(card.personality, 'Warm, tired.');
    expect(card.firstMessage, 'You again.');
  });

  test('a malformed character_book costs the lorebook, not the card', () {
    final card = service.parseCardJson(
      jsonEncode(cardWith({'character_book': 'not-a-book'})),
    );

    expect(card, isNotNull);
    expect(card!.lorebook, isNull);
    expect(card.description, 'A woman who runs the corner bakery.');
  });

  test('a wrong-typed tts_voice is dropped rather than thrown', () {
    final card = service.parseCardJson(
      jsonEncode(cardWith({'tts_voice': 7})),
    );

    expect(card, isNotNull);
    expect(card!.ttsVoice, isNull);
  });

  test('a well-formed card still parses exactly as before', () {
    final card = service.parseCardJson(
      jsonEncode(
        cardWith({
          'tags': ['romance'],
          'alternate_greetings': ['Hi.'],
          'tts_voice': 'af_heart',
          'world_names': ['Sunset Row'],
        }),
      ),
    );

    expect(card, isNotNull);
    expect(card!.tags, ['romance']);
    expect(card.alternateGreetings, ['Hi.']);
    expect(card.ttsVoice, 'af_heart');
    expect(card.worldNames, ['Sunset Row']);
  });

  test(
    'null greet slot stays aligned so furious stays on Get out',
    () {
      final card = service.parseCardJson(
        jsonEncode(
          cardWith({
            'alternate_greetings': [null, 'Get out.'],
            'extensions': {
              'front_porch': {
                'realism_engine': {
                  'enabled': true,
                  'greeting_seeds': [
                    null,
                    {'character_emotion': 'furious'},
                  ],
                },
              },
            },
          }),
        ),
      );
      expect(card, isNotNull);
      expect(card!.alternateGreetings, ['Get out.']);
      expect(
        card.frontPorchExtensions!.greetingSeeds.single!.characterEmotion,
        'furious',
        reason: 'whereType skip of JSON-null would zip furious off Get out',
      );
    },
  );

  test('input that is not a JSON object stays null (genuinely not a card)', () {
    expect(service.parseCardJson('[]'), isNull);
    expect(service.parseCardJson('"hello"'), isNull);
    expect(service.parseCardJson('not json at all'), isNull);
  });
}
