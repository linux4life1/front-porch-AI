// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';

void main() {
  test('an older card opens and its saved rates do not move a bar', () {
    final ext = FrontPorchExtensions.fromJson({
      'realism_engine': {
        'enabled': true,
        'needs_sim_enabled': true,
        'needs_decay_hunger': 20,
        'needs_decay_energy': 9,
        'needs_sim_strength': 5,
        'needs_baseline_hunger': 70,
      },
    });

    expect(ext.needsBaselineHunger, 70);
    expect(ext.needsPace, 'normal');

    final saved = ext.toJson()['realism_engine'] as Map;
    expect(saved.containsKey('needs_decay_hunger'), isFalse);
    expect(saved.containsKey('needs_decay_energy'), isFalse);
    expect(saved.containsKey('needs_sim_strength'), isFalse);
    expect(BodyPace.parse(ext.needsPace), BodyPace.normal);
  });
}
