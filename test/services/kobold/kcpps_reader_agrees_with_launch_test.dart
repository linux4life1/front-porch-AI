// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The editor shows a preset through `readKcpps`; a launch runs the same file
// through `kcppsPresetLaunchMap` and the helpers beside it. For any value a
// file holds (a hand-edited preset can hold a text or a null where
// KoboldCpp's launcher writes true and false) what the editor shows must be
// what the launch runs.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

KcppsOk _read(Map<String, dynamic> map) =>
    readKcpps(jsonEncode(map)) as KcppsOk;

void main() {
  test('sliding window is shown when the launch leaves it on with fast '
      'forward off, and only then', () {
    for (var map in <Map<String, dynamic>>[
      {'noswa': false, 'nofastforward': true},
      {'noswa': true, 'nofastforward': true},
      {'noswa': 'yes', 'nofastforward': true},
      {'noswa': null, 'nofastforward': true},
      {'noswa': 0, 'nofastforward': true},
      {'useswa': true, 'nofastforward': true},
      {'useswa': 'yes', 'nofastforward': true},
      {'useswa': false, 'nofastforward': true},
      {'nofastforward': true},
      {'noswa': false},
      {'noswa': false, 'nofastforward': 'yes'},
      <String, dynamic>{},
    ]) {
      // A file that has only an old name is refused until the editor has
      // saved it (kcpps_old_names_test); what the editor shows for the
      // saved file is what the launch runs.
      if (kcppsOldNames(map).isNotEmpty) {
        expect(
          () => kcppsPresetLaunchMap(map, modelPath: '', mmprojPath: ''),
          throwsA(isA<KoboldPresetProblem>()),
          reason: '$map',
        );
        map = kcppsWithCurrentNames(map);
      }
      final shown =
          _read(map).config.contextMode ==
          ContextManagementMode.slidingWindowAttention;
      final launch = kcppsPresetLaunchMap(map, modelPath: '', mmprojPath: '');
      final runs = kcppsHasSwaOn(launch) && launch['nofastforward'] == true;
      expect(shown, runs, reason: '$map');
    }
  });
}
