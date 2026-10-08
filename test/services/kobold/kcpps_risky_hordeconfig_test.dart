// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// `hordeconfig` is the name KoboldCpp's launcher used for its AI Horde
// settings before `hordemodelname`, `hordekey` and the rest. KoboldCpp turns
// it into them on every load (`convert_invalid_args`), over whatever the file
// says under the current names, and takes the Horde key from its fourth entry
// when it has more than four. A preset with a key in it lends the graphics
// card to strangers exactly as one with `hordekey` does, so it is refused the
// same way (kcpps_risky_preset_test), naming the old setting, even beside the
// current name of the model, which would otherwise let it through as an
// up-to-date preset (kcpps_old_names_test). Without a key it is only the old
// form of a display name. KoboldCpp's own export carries `hordeconfig` as
// null and passes.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:path/path.dart' as p;

Map<String, dynamic> _launch(Map<String, dynamic> preset) =>
    kcppsPresetLaunchMap(preset, modelPath: '', mmprojPath: '');

final Matcher _risky = allOf(
  contains('hordeconfig'),
  contains('run a program or open itself to the internet'),
  contains('pick another preset'),
);

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('fpai_horde_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(Map<String, dynamic> preset) => (File(
    p.join(dir.path, 'Theirs.kcpps'),
  )..writeAsStringSync(jsonEncode(preset))).path;

  test('the old Horde settings with a key are refused, naming them, '
      'wherever a preset reaches the engine', () async {
    for (final preset in <Map<String, dynamic>>[
      {
        'contextsize': 8192,
        'hordeconfig': ['My model', 80, 1024, 'abc123', 'my-worker'],
      },
      // The current name of the model beside it changes nothing: KoboldCpp
      // still takes the key from the old setting.
      {
        'hordemodelname': 'My model',
        'hordekey': '',
        'hordeconfig': ['My model', 80, 1024, 'abc123', 'my-worker'],
      },
    ]) {
      expect(await koboldPresetProblem(write(preset)), _risky);
      expect(
        () => _launch(preset),
        throwsA(
          isA<KoboldPresetProblem>().having(
            (e) => e.message,
            'message',
            _risky,
          ),
        ),
      );
    }
  });

  test('KoboldCpp reads a text there by its letters, so one of more than '
      'four letters gives it a key', () {
    expect(kcppsRiskyPresetProblem({'hordeconfig': 'a1234'}), _risky);
    expect(kcppsRiskyPresetProblem({'hordeconfig': 'a123'}), isNull);
  });

  test('every way of giving no Horde key is not risky', () {
    for (final nothing in <Object?>[
      null,
      false,
      0,
      '',
      <Object>[],
      // No model name: KoboldCpp reads none of it.
      ['', 0, 0, 'abc123', 'my-worker'],
      // A display name, and lengths, but no key.
      ['My model'],
      ['My model', 80, 1024, '', 'my-worker'],
      ['My model', 80, 1024, 'abc123'],
    ]) {
      expect(
        kcppsRiskyPresetProblem({'hordeconfig': nothing}),
        isNull,
        reason: '$nothing',
      );
    }
  });

  test('without a key, the old form is refused as an old preset, not as a '
      'risky one', () async {
    final problem = await koboldPresetProblem(
      write({
        'hordeconfig': ['My model', 80, 1024],
      }),
    );

    expect(problem, contains('saved by an older KoboldCpp'));
    expect(problem, isNot(contains('open itself to the internet')));
  });

  test('a config saved by KoboldCpp 1.117.1 itself passes', () async {
    final text = File(
      'test/fixtures/kcpps/koboldcpp_1_117_1_export.kcpps',
    ).readAsStringSync();
    final raw = (readKcpps(text) as KcppsOk).raw;
    expect(raw.containsKey('hordeconfig'), isTrue);

    expect(await koboldPresetProblem(write(raw)), isNull);
  });
}
