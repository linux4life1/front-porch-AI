// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// Buttons start file windows without awaiting them. A raw PickerPrefs call
// that fails (a hung Windows dialog, a missing Linux portal) throws past the
// button and the click does nothing (issue #255). GuardedPicker explains the
// failure instead, so every window opened from lib/ goes through it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('every file window in lib/ opens through GuardedPicker', () {
    final raw = RegExp(
      r'PickerPrefs\.(pickFiles|saveFile|saveFromBuilder|getDirectoryPath)\(',
    );
    // The wrapper itself, and PickerPrefs' own saveFromBuilder -> saveFile.
    const allowed = {'guarded_picker.dart', 'picker_prefs.dart'};
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      if (allowed.contains(p.basename(file.path))) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (raw.hasMatch(lines[i])) offenders.add('${file.path}:${i + 1}');
      }
    }
    expect(files, isNotEmpty);
    expect(
      offenders,
      isEmpty,
      reason:
          'Open file windows with GuardedPicker.<same method>(context, ...) so '
          'a failure shows a dialog instead of leaving the click doing nothing.',
    );
  });
}
