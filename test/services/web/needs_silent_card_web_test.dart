// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's character editor round-trips the card's Realism block through
// realism_extensions_json. A card that says nothing about Needs follows the
// Porch Life Needs switch (ruling 2026-10-10), so the phone shows that
// switch for it, and a save that leaves Needs out keeps the card silent
// instead of stamping a false the card never had.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/web/util/realism_extensions_json.dart';

void main() {
  test('a partial save keeps a silent card silent', () {
    final silent = FrontPorchExtensions(realismEnabled: true);
    final saved = frontPorchFromFields({'realismEnabled': true}, base: silent);
    expect(
      saved.needsSimChoice,
      isNull,
      reason: 'a phone save that never touched Needs stamped a choice',
    );
    expect(
      (saved.toJson()['realism_engine'] as Map).containsKey(
        'needs_sim_enabled',
      ),
      isFalse,
    );
  });

  test('a save that sends Needs writes it', () {
    final silent = FrontPorchExtensions(realismEnabled: true);
    expect(
      frontPorchFromFields({
        'needsSimEnabled': true,
      }, base: silent).needsSimChoice,
      isTrue,
    );
    expect(
      frontPorchFromFields({
        'needsSimEnabled': false,
      }, base: silent).needsSimChoice,
      isFalse,
    );
  });

  test('the phone shows the Porch Life switch for a silent card', () {
    final silent = FrontPorchExtensions(realismEnabled: true);
    expect(
      frontPorchToJson(silent, needsSimWhenSilent: true)['needsSimEnabled'],
      isTrue,
    );
    expect(
      frontPorchToJson(silent, needsSimWhenSilent: false)['needsSimEnabled'],
      isFalse,
    );
    final chose = FrontPorchExtensions(needsSimEnabled: false);
    expect(
      frontPorchToJson(chose, needsSimWhenSilent: true)['needsSimEnabled'],
      isFalse,
      reason: 'a card that chose off shows off',
    );
  });
}
