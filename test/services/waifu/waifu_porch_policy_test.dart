// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

/// The 18+ rule is one block every agent gets, apart from how to code.
void main() {
  final card = CharacterCard(name: 'Mira', personality: 'dry');

  test('Build, Plan and the wrap-up voice all carry the porch policy', () {
    for (final prompt in [
      buildWaifuOpenCodeAgentPrompt(card),
      buildWaifuPlanAgentPrompt(card),
      buildWaifuVoiceAgentPrompt(card),
    ]) {
      expect(prompt, contains('\n\n$kWaifuPorchPolicy'));
    }
  });

  test('the coding rules do not restate the content policy', () {
    for (final rules in [kWaifuOpenCodePreamble, kWaifuPlanPreamble]) {
      expect(rules, isNot(contains('18+')));
      expect(rules, isNot(contains('erotic')));
    }
  });
}
