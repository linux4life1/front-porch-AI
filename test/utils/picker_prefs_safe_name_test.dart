// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// windows_file_picker checks the suggested save name inside its dialog
// isolate. A name with a character Windows refuses (<>:"/\|?*) throws there,
// nothing is sent back, and the save window never opens: exporting a
// character named "Dr. Who: Reborn" hung until the 10-minute timeout.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/utils/picker_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? suggested;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    suggested = null;
    PickerPrefs.testSaveFileOverride =
        ({
          required String category,
          required Uint8List bytes,
          String? dialogTitle,
          String? fileName,
          FileType? type,
          List<String>? allowedExtensions,
        }) async {
          suggested = fileName;
          return null;
        };
  });

  tearDown(() {
    PickerPrefs.testSaveFileOverride = null;
  });

  test('saveFile suggests a name Windows accepts', () async {
    await PickerPrefs.saveFile(
      category: PickerPrefs.catExport,
      bytes: Uint8List.fromList(const [1]),
      fileName: 'Dr. Who: "Reborn"?.png',
    );
    expect(suggested, 'Dr. Who_ _Reborn__.png');
  });

  test('saveFromBuilder builds and suggests the same safe name', () async {
    String? built;
    await PickerPrefs.saveFromBuilder(
      category: PickerPrefs.catExport,
      fileName: r'AC/DC <live>|*\.fpworld',
      writeTemp: (path) async {
        built = p.basename(path);
        await File(path).writeAsBytes(const [1]);
      },
    );
    expect(built, 'AC_DC _live____.fpworld');
    expect(suggested, built);
  });

  test('an ordinary name is left alone', () async {
    await PickerPrefs.saveFile(
      category: PickerPrefs.catExport,
      bytes: Uint8List.fromList(const [1]),
      fileName: "Sera's café (v2).png",
    );
    expect(suggested, "Sera's café (v2).png");
  });
}
