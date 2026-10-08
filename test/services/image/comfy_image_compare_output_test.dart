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

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/image.dart';

void main() {
  test('UI graph omits an incomplete terminal comparison output', () {
    final api = ensureComfyApiGraph({
      'nodes': [
        {
          'id': 1,
          'type': 'LoadImage',
          'inputs': <Object>[],
          'widgets_values': ['reference.png'],
        },
        {
          'id': 2,
          'type': 'SaveImage',
          'inputs': [
            {'name': 'images', 'link': 11},
          ],
          'widgets_values': ['result'],
        },
        {
          'id': 3,
          'type': 'ImageCompare',
          'inputs': [
            {'name': 'image_a', 'link': 12},
            {'name': 'image_b', 'link': 13},
            {'name': 'compare_view', 'link': null},
          ],
          'widgets_values': <Object>[],
        },
      ],
      'links': [
        [11, 1, 0, 2, 0, 'IMAGE'],
        [12, 1, 0, 3, 0, 'IMAGE'],
        [13, 1, 0, 3, 1, 'IMAGE'],
      ],
    });

    expect(api, isNotNull);
    expect(api, containsPair('2', isA<Map>()));
    expect(api, isNot(contains('3')));
  });

  test('API graph omits the same incomplete terminal output', () {
    final api = ensureComfyApiGraph({
      'save': {
        'class_type': 'SaveImage',
        'inputs': {
          'images': ['source', 0],
        },
      },
      'compare': {
        'class_type': 'ImageCompare',
        'inputs': {
          'image_a': ['source', 0],
          'image_b': ['source', 0],
        },
      },
    });

    expect(api, contains('save'));
    expect(api, isNot(contains('compare')));
  });

  test('linked or complete comparison nodes are retained', () {
    final api = ensureComfyApiGraph({
      'linked': {'class_type': 'ImageCompare', 'inputs': <String, Object>{}},
      'consumer': {
        'class_type': 'PreviewAny',
        'inputs': {
          'source': ['linked', 0],
        },
      },
      'complete': {
        'class_type': 'ImageCompare',
        'inputs': {
          'compare_view': ['view', 0],
        },
      },
    });

    expect(api, contains('linked'));
    expect(api, contains('complete'));
  });
}
