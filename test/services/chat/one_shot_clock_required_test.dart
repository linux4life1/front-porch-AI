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

// THE FUSED ONE-SHOT CALL IS NOT THE CLOCK DRIVER.
//
// Clock decide is post-generation (time-only eval after the reply). One-shot
// must not demand minutes_elapsed or it would double-count. The standalone
// scene-time twin still requires it — that call is the clock.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';

List<String> _required(List<Map<String, dynamic>> tools) {
  final params = tools.single['function']['parameters'] as Map<String, dynamic>;
  return (params['required'] as List).cast<String>();
}

Map<String, dynamic> _properties(List<Map<String, dynamic>> tools) {
  final params = tools.single['function']['parameters'] as Map<String, dynamic>;
  return params['properties'] as Map<String, dynamic>;
}

void main() {
  group('one-shot tool schema', () {
    test('one-shot does not demand minutes_elapsed; scene-time-only does', () {
      expect(_required(kOneShotEvalTools), isNot(contains('minutes_elapsed')));
      expect(_required(kSceneTimeOnlyEvalTools), contains('minutes_elapsed'));
    });

    test('still demands the judge fields it always did', () {
      expect(
        _required(kOneShotEvalTools),
        containsAll(<String>[
          'relationship_delta',
          'trust_delta',
          'emotion',
          'emotion_intensity',
        ]),
      );
    });

    test('new_day lives only on the scene-time lane', () {
      expect(_properties(kOneShotEvalTools), isNot(contains('new_day')));
      expect(_required(kSceneTimeOnlyEvalTools), isNot(contains('new_day')));
      expect(_properties(kSceneTimeOnlyEvalTools), contains('new_day'));
    });

    test('continuous_instant is optional on the scene-time lane', () {
      expect(
        _required(kSceneTimeOnlyEvalTools),
        isNot(contains('continuous_instant')),
      );
      expect(
        _properties(kSceneTimeOnlyEvalTools),
        contains('continuous_instant'),
      );
    });

    test('every required field is actually declared in the schema', () {
      final props = _properties(kOneShotEvalTools);
      for (final key in _required(kOneShotEvalTools)) {
        expect(props, contains(key), reason: '$key is demanded but undeclared');
      }
    });

    test('planner-on scene-time demands today_sentence; one-shot does not', () {
      expect(
        _required(kOneShotEvalToolsWithToday),
        isNot(contains('today_sentence')),
      );
      expect(
        _required(kSceneTimeOnlyEvalToolsWithToday),
        contains('today_sentence'),
      );
      expect(_required(kOneShotEvalTools), isNot(contains('today_sentence')));
      expect(
        _required(kSceneTimeOnlyEvalTools),
        isNot(contains('today_sentence')),
      );
    });
  });
}
