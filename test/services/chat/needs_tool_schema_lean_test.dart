// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// THE NEEDS TOOL SCHEMA STOPS INVITING DEAD FIELDS (2026-08-10).
//
// 'activities' and 'intensity' were stripped from the needs TEXT prompt in
// the Tier-1 sweep (nothing in the app has ever read either from the
// response — the applier consumes the seven deltas + reason), but both
// survived in the TOOLS schema, so every tools-transport needs call still
// invited the model to fill them and it did — visible in the maintainer's
// own log ("activities":["sleeping","washing","emotional_phone_call",
// "crying"],"intensity":6), output tokens paid for fields that go straight
// to the void.
//
// Guard proven to fail: re-adding either field to _needsImpactFields sends
// the dead-fields test red; restored, green.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart'
    show kNeedsImpactEvalTools, kNeedsImpactTool;

void main() {
  group('needs tool schema', () {
    Map<String, dynamic> schemaProps() {
      final tool = kNeedsImpactEvalTools.single;
      final fn = tool['function'] as Map<String, dynamic>? ?? tool;
      final params =
          (fn['parameters'] ?? fn['input_schema']) as Map<String, dynamic>;
      return (params['properties'] as Map).cast<String, dynamic>();
    }

    test('carries exactly the fields something reads: 8 deltas + reason', () {
      final props = schemaProps();
      for (final k in const [
        'hunger_delta',
        'energy_delta',
        'hygiene_delta',
        'fun_delta',
        'social_delta',
        'bladder_delta',
        'bowels_delta',
        'comfort_delta',
        'reason',
      ]) {
        expect(props, contains(k));
      }
    });

    test('the dead fields are gone — activities and intensity', () {
      final props = schemaProps();
      expect(
        props,
        isNot(contains('activities')),
        reason:
            'nothing has ever read activities from the response; its '
            'presence in the schema makes every tools-transport needs call '
            'pay output tokens for it',
      );
      expect(props, isNot(contains('intensity')));
    });

    test('the tool name is unchanged (wire contract)', () {
      final tool = kNeedsImpactEvalTools.single;
      final fn = tool['function'] as Map<String, dynamic>? ?? tool;
      expect(fn['name'], kNeedsImpactTool);
    });
  });
}
