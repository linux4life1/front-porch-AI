// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/utils/picker_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    PickerPrefs.testNativePicker = null;
    PickerPrefs.testForceWindowsPickerGuard = false;
    PickerPrefs.testWindowsPickerTimeout = const Duration(minutes: 10);
  });

  const cases = <_PickerCase>[
    _PickerCase('saveFile', 'saveFile', PickerPrefs.catExport),
    _PickerCase('pickFile', 'pickFile', PickerPrefs.catImport),
    _PickerCase('pickFiles', 'pickFiles', PickerPrefs.catImport),
    _PickerCase(
      'getDirectoryPath',
      'getDirectoryPath',
      PickerPrefs.catDirectory,
    ),
  ];

  for (final c in cases) {
    test('${c.name} does not pass a missing remembered folder', () async {
      await _expectInitial(c, exists: false);
    });

    test('${c.name} still passes an existing remembered folder', () async {
      await _expectInitial(c, exists: true);
    });

    test(
      '${c.name} times out a stuck Windows dialog and clears the folder',
      () async {
        final live = await Directory.systemTemp.createTemp('fpai_picker_hang_');
        addTearDown(() async {
          if (live.existsSync()) await live.delete(recursive: true);
        });
        final key = PickerPrefs.testPrefsKey(c.category);
        SharedPreferences.setMockInitialValues({key: live.path});
        PickerPrefs.testForceWindowsPickerGuard = true;
        PickerPrefs.testWindowsPickerTimeout = const Duration(milliseconds: 40);
        String? seen;
        PickerPrefs.testNativePicker =
            ({required String op, required String? initialDirectory}) {
              expect(op, c.op);
              seen = initialDirectory;
              return Completer<Object?>().future;
            };

        await expectLater(
          c.invoke(),
          throwsA(
            isA<PickerDialogTimeout>().having(
              (e) => e.toString(),
              'toString',
              'The file dialog did not open. The remembered folder was cleared; try again.',
            ),
          ),
        );
        expect(seen, live.path);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(key), isNull);
      },
      timeout: const Timeout(Duration(seconds: 2)),
    );
  }

  test(
    'a slow dialog is not timed out off Windows',
    () async {
      final live = await Directory.systemTemp.createTemp('fpai_picker_slow_');
      addTearDown(() async {
        if (live.existsSync()) await live.delete(recursive: true);
      });
      final key = PickerPrefs.testPrefsKey(PickerPrefs.catExport);
      SharedPreferences.setMockInitialValues({key: live.path});
      PickerPrefs.testForceWindowsPickerGuard = false;
      PickerPrefs.testWindowsPickerTimeout = const Duration(milliseconds: 20);
      PickerPrefs.testNativePicker =
          ({required String op, required String? initialDirectory}) async {
            expect(op, 'saveFile');
            expect(initialDirectory, live.path);
            await Future<void>.delayed(const Duration(milliseconds: 80));
            return null;
          };

      await PickerPrefs.saveFile(
        category: PickerPrefs.catExport,
        bytes: Uint8List.fromList(const [1]),
        fileName: 'lore.json',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), live.path);
    },
    // On Windows the guard is always on, so this off-Windows case can't run.
    skip: Platform.isWindows ? 'guard is always on on Windows' : false,
  );
}

class _PickerCase {
  const _PickerCase(this.name, this.op, this.category);

  final String name;
  final String op;
  final String category;

  Future<void> invoke() {
    switch (name) {
      case 'saveFile':
        return PickerPrefs.saveFile(
          category: category,
          bytes: Uint8List.fromList(const [1]),
          fileName: 'lore.json',
        );
      case 'pickFile':
        return PickerPrefs.pickFiles(category: category);
      case 'pickFiles':
        return PickerPrefs.pickFiles(category: category, allowMultiple: true);
      case 'getDirectoryPath':
        return PickerPrefs.getDirectoryPath(category: category);
      default:
        throw StateError(name);
    }
  }
}

var _missingSeq = 0;

Future<void> _expectInitial(_PickerCase c, {required bool exists}) async {
  final Directory? live = exists
      ? await Directory.systemTemp.createTemp('fpai_picker_live_')
      : null;
  if (live != null) {
    addTearDown(() async {
      if (live.existsSync()) await live.delete(recursive: true);
    });
  }
  final folder = exists
      ? live!.path
      : '${Directory.systemTemp.path}${Platform.pathSeparator}fpai_picker_missing_${_missingSeq++}';
  if (!exists) {
    expect(Directory(folder).existsSync(), isFalse);
  }

  final key = PickerPrefs.testPrefsKey(c.category);
  SharedPreferences.setMockInitialValues({key: folder});
  String? seen;
  var called = false;
  PickerPrefs.testNativePicker =
      ({required String op, required String? initialDirectory}) async {
        expect(op, c.op);
        called = true;
        seen = initialDirectory;
        return null;
      };

  await c.invoke();
  expect(called, isTrue);
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getString(key);
  if (exists) {
    expect(seen, folder);
    expect(stored, folder);
  } else {
    expect(seen, isNull);
    expect(stored, isNull);
  }
}
