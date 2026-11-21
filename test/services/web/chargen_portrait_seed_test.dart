// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Review step's portrait prompt seed, read from a saved card (the web
// reloads between steps, so the creator's live state is gone). The stamp the
// web's create writes carries the LLM image prompt, art style, age and sex;
// a card from before those keys falls back to the card's own words, as the
// desktop's fallback does.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_gen/creator_inputs_stamp.dart';
import 'package:front_porch_ai/services/web/facade/chargen/chargen_portrait_seed.dart';

void main() {
  CharacterCard stamped(
    Map<String, dynamic> portrait, {
    String name = 'Porchie',
  }) {
    final card = CharacterCard(
      name: name,
      description: 'A sharp-tongued vampire lecturer in a wool coat.',
    );
    card.rawExtensions = {
      kCreatorInputsExtensionKey: {
        'concept': 'vampire lecturer',
        'loreCategories': <String>[],
        'loreDepth': 'Standard',
        ...portrait,
      },
    };
    return card;
  }

  test('the LLM prompt wins, with the character name stripped', () {
    final card = stamped({
      'imagePrompt':
          'Porchie, a vampire lecturer in a rain-soaked cathedral, gothic',
      'artStyle': 'Gothic',
      'age': '30',
      'sex': 'female',
    });
    expect(
      buildPortraitPromptSeed(card),
      'a vampire lecturer in a rain-soaked cathedral, gothic, Gothic style',
    );
  });

  test('the name is stripped from every word and adjacent commas collapse', () {
    final card = stamped({
      'imagePrompt': 'Wren Vale, tall, , pale, Wren in a long coat',
      'artStyle': 'Anime',
    }, name: 'Wren Vale');
    expect(
      buildPortraitPromptSeed(card),
      'tall, pale, in a long coat, Anime style',
    );
  });

  test('no LLM prompt: visual tags from the stamp, then the description', () {
    final card = stamped({'artStyle': 'Anime', 'age': '30', 'sex': 'female'});
    expect(
      buildPortraitPromptSeed(card),
      'character portrait, Anime style, female, 30 years old, '
      'A sharp-tongued vampire lecturer in a wool coat.',
    );
  });

  test('a card with no stamp reads its description and the default style', () {
    final card = CharacterCard(
      name: 'Wren',
      description: 'A tall woman in a wool coat.',
    );
    expect(
      buildPortraitPromptSeed(card),
      'character portrait, Anime style, A tall woman in a wool coat.',
    );
  });

  test('the stamp reader is empty for a card that carries none', () {
    final card = CharacterCard(name: 'Wren');
    expect(readCreatorPortraitInputs(card), (
      imagePrompt: '',
      artStyle: '',
      age: '',
      sex: '',
    ));
  });
}
