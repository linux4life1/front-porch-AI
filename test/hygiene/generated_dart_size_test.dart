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

// THE GENERATED-CODE RATCHET — the half god_file_ratchet_test.dart cannot see.
//
// That ratchet EXCLUDES *.g.dart, for a good reason: you cannot hand-split
// generated code, so a line count there is not a refactoring instruction. The
// side effect was that generated size had no owner at all, and
// database.g.dart reached 24,343 lines — 7,652 of them Drift table managers
// (`db.managers`, the `$$…FilterComposer` family) that no call site in the app
// has ever used. `generate_manager: false` in build.yaml turned them off.
//
// Generated code still has an owner: the build config that produces it. So
// this file guards the config and its output together.
//
//   1. build.yaml keeps `generate_manager: false`. Drop that line and the next
//      regeneration silently puts 7.7k lines back.
//   2. No generated file carries the manager API. This is the belt to rule 1's
//      braces: it catches a regeneration that happened with managers on, and
//      it keeps working if a future Drift renames the option.
//   3. Every lib/**.g.dart is recorded below and stays under its ceiling. A
//      new generated file must be recorded, so codegen cannot add an
//      unmeasured monster.
//
// The ceilings carry deliberate slack, and that is not sloppiness. A new
// column or provider legitimately grows generated output by a few dozen
// lines, and a gate that goes red on ordinary schema work is a gate people
// learn to edit rather than read. The slack is tiny next to the 7.7k tail
// this exists to stop.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Line ceiling per generated file under lib/. Raise one only with a reason
/// (a real schema or provider addition); lower it when the file shrinks, so
/// freed headroom cannot quietly grow back.
const Map<String, int> kGeneratedCeilings = {
  'lib/database/database.g.dart': 18000,
  'lib/services/chat/weather_providers.g.dart': 400,
  'lib/services/chat/milestone_providers.g.dart': 320,
  'lib/ui/chat_components/overlays/absence_recap_banner.g.dart': 160,
};

/// Drift's unused table-manager API. Any one of these in generated output
/// means managers are being generated again.
const List<String> kManagerMarkers = [
  r'$AppDatabaseManager',
  'TableManager',
  'FilterComposer',
  'OrderingComposer',
  'AnnotationComposer',
];

Map<String, int> _generatedCensus() {
  final counts = <String, int>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.g.dart')) continue;
    final path = entity.path.replaceAll('\\', '/');
    counts[path] = entity.readAsLinesSync().length;
  }
  return counts;
}

void main() {
  test('build.yaml keeps Drift table managers switched off', () {
    final buildConfig = File('build.yaml');
    expect(buildConfig.existsSync(), isTrue);
    expect(
      RegExp(
        r'^\s*generate_manager:\s*false\s*$',
        multiLine: true,
      ).hasMatch(buildConfig.readAsStringSync()),
      isTrue,
      reason:
          'build.yaml must keep `generate_manager: false` under drift_dev. '
          'Without it the next `dart run build_runner build` writes ~7,700 '
          'lines of table-manager API the app never calls.',
    );
  });

  test('no generated file carries the table-manager API', () {
    final offenders = <String>[];
    for (final path in _generatedCensus().keys) {
      final source = File(path).readAsStringSync();
      final found = kManagerMarkers.where(source.contains).toList();
      if (found.isNotEmpty) {
        offenders.add('$path contains ${found.join(', ')}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'generated table managers are back:\n${offenders.join('\n')}\n'
          'Check build.yaml, then regenerate with '
          '`dart run build_runner build`.',
    );
  });

  test('every generated file is recorded and stays under its ceiling', () {
    final counts = _generatedCensus();
    final problems = <String>[];

    counts.forEach((path, lines) {
      final ceiling = kGeneratedCeilings[path];
      if (ceiling == null) {
        problems.add(
          '$path is generated but not recorded ($lines lines). Add it to '
          'kGeneratedCeilings so its size has an owner.',
        );
        return;
      }
      if (lines > ceiling) {
        problems.add(
          '$path is $lines lines, over its $ceiling ceiling. If the growth is '
          'a real schema or provider addition, raise the ceiling in this '
          'change and say why. If it is generated API nothing calls, switch '
          'that generation off instead.',
        );
      }
    });

    for (final path in kGeneratedCeilings.keys) {
      if (!counts.containsKey(path)) {
        problems.add(
          '$path is recorded here but does not exist — drop its entry, or '
          'regenerate if codegen simply has not run.',
        );
      }
    }

    expect(
      problems,
      isEmpty,
      reason: 'generated-size violations:\n\n${problems.join('\n\n')}',
    );
  });
}
