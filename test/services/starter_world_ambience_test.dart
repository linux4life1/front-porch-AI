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

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/scene/scene_sound.dart';

/// The shipped starter envelopes must carry scene-ambience defaults, so a
/// fresh install that adds a starter hears its places by default (the
/// Ambient Stage switch in Settings still gates whether anything plays).
void main() {
  final dir = Directory('assets/worlds/starter');

  test('every place loop in a starter is a real bundled preset', () {
    expect(dir.existsSync(), isTrue, reason: 'run from the repo root');
    final files = dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.fpworld'),
    );
    for (final file in files) {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      void check(Map<String, dynamic> env, String label) {
        final a = env['ambience'];
        if (a == null) return;
        expect(
          ScenePlaceLoop.values.map((p) => p.file).toList(),
          contains(a),
          reason: '$label has ambience "$a", not a preset',
        );
        for (final loc in (env['locations'] as List? ?? const [])) {
          check(Map<String, dynamic>.from(loc as Map), '$label/${loc['name']}');
        }
      }

      check(json, file.uri.pathSegments.last);
    }
  });

  test('Canopy Market decodes to the village street loop', () {
    final json =
        jsonDecode(
              File(
                'assets/worlds/starter/verdance-basin.fpworld',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final market = (json['locations'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((l) => l['name'] == 'Canopy Market');
    final world = World.fromJson(market);
    expect(world.ambience, 'village');
  });

  test('the airless moon root carries no place loop (silence outdoors)', () {
    final json =
        jsonDecode(
              File(
                'assets/worlds/starter/kestrel-reach.fpworld',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(json.containsKey('ambience'), isFalse);
  });

  test('seeded places round-trip through the envelope encoder', () {
    // World.fromJson must feed World.toJson, so an import-and-export keeps
    // the seed instead of silently dropping it.
    final world = World.fromJson({
      'id': 'starter-x-market',
      'name': 'Canopy Market',
      'ambience': 'village',
    });
    expect(world.ambience, 'village');
    expect(world.toJson()['ambience'], 'village');
  });
}
