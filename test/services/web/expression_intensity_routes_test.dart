// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'expression_prompt_rules_routes_journey_test.dart' show RulesRouteRig;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real pack routes preview and submit intensity, preserve custom wording, and reject bad levels',
    () async {
      final rig = await RulesRouteRig.open();
      try {
        rig.publish(PackOrigin.phone);
        final s = rig.board.run!.session;
        var response = await rig.post('/rules', {
          'promptRules': s.promptRules.toJson(),
          'intensity': 'subtle',
        });
        expect(response.statusCode, 200);
        expect(s.intensity, ExpressionIntensity.subtle);
        response = await rig.post('/preview', {
          'activePack': true,
          'intensity': 'strong',
          'useIntensityPrompt': true,
        });
        expect(response.statusCode, 200);
        final preview =
            (jsonDecode(response.body)['previews'] as List).first['effective'];
        response = await rig.post('/reroll', {
          'emotion': 'joy',
          'intensity': 'strong',
          'newSeed': false,
          'useIntensityPrompt': true,
        });
        expect(response.statusCode, 200);
        while (s.isRunning) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(rig.generatedPrompts.single, preview);
        expect(s.effectiveIntensityFor(0), ExpressionIntensity.strong);
        await s.reroll(0, promptOverride: 'manual wording');
        response = await rig.post('/preview', {
          'activePack': true,
          'intensity': 'subtle',
        });
        expect(
          (jsonDecode(response.body)['previews'] as List).first['effective'],
          'manual wording',
        );
        for (final invalid in ['unknown', 0, null]) {
          response = await rig.post('/rules', {
            'promptRules': s.promptRules.toJson(),
            'intensity': invalid,
          });
          expect(response.statusCode, 400);
        }
        rig.publish(PackOrigin.desktop);
        response = await rig.post('/rules', {
          'promptRules': s.promptRules.toJson(),
          'intensity': 'subtle',
        });
        expect(response.statusCode, 409);
      } finally {
        await rig.close();
      }
    },
  );
}
