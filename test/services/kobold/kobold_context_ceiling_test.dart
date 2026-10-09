// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// How much context is offered for a model (maintainer, 2026-10-05): up to
// the length the model was made for, everywhere, with one rule
// (koboldContextMost). Before, the Local model card applied the model's own
// length only from 16,384 up and never went past 131,072, while the preset
// editor's slider stopped at 16,384 at the bottom and 262,144 at the top: an
// 8k model was offered 32k to 131k on the card as if they were fine, and a
// 262k model was cut short. The size in use is always offered, and a model
// made for less than 16,384 tokens gets a plain warning. Since 2026-10-09
// the usual sizes start at 16,384: the app never suggests less (maintainer
// ruling); only the size in use, or a short model's own length, can be.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

void main() {
  test(
    'the choices go up to what the model was made for, past 131,072 too',
    () {
      expect(koboldContextChoices(current: 16384, modelMax: 262144), [
        16384,
        32768,
        65536,
        131072,
        262144,
      ]);
      expect(
        koboldContextChoices(current: 16384, modelMax: 1024000).last,
        1024000,
      );
      expect(koboldContextChoices(current: 16384, modelMax: 40960), [
        16384,
        32768,
        40960,
      ]);
    },
  );

  test('a model made for less than 16,384 tokens is offered no more than '
      'that, and the size in use', () {
    expect(koboldContextChoices(current: 8192, modelMax: 8192), [8192]);
    expect(koboldContextChoices(current: 16384, modelMax: 8192), [8192, 16384]);
    expect(koboldContextChoices(current: 16384, modelMax: 4096), [4096, 16384]);
  });

  test('a model that does not say keeps the usual sizes', () {
    expect(koboldContextChoices(current: 16384, modelMax: null), [
      16384,
      32768,
      65536,
      131072,
    ]);
    expect(koboldContextMost(null), 131072);
    expect(koboldContextMost(0), 131072);
  });

  test('a model made for too little chat is warned about in plain words', () {
    expect(
      koboldShortModelWarning(8192),
      'This model was made for 8,192 tokens of chat. Front Porch needs at '
      'least 16,384, so it may not work well here. A model made for longer '
      'chats is recommended.',
    );
    expect(koboldShortModelWarning(4096), contains('made for 4,096 tokens'));
    for (final enough in [16384, 32768, 262144, null, 0]) {
      expect(koboldShortModelWarning(enough), isNull, reason: '$enough');
    }
  });
}
