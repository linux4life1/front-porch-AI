// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// Buttons start file windows without awaiting them. A window that fails (a
// hung Windows dialog, a missing Linux portal) throws past the button and the
// click does nothing (issue #255). GuardedPicker explains the failure, so
// every window opened from lib/ goes through it: no raw PickerPrefs window
// outside the wrapper, and no file_picker call outside PickerPrefs, which also
// owns the remembered folder and the Windows dialog timeout.
//
// file_picker is the only file-dialog package the app depends on. A new one
// needs its own rule here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _pickerPrefs = 'lib/utils/picker_prefs.dart';
const _guardedPicker = 'lib/ui/widgets/guarded_picker.dart';

class _Rule {
  const _Rule(this.name, this.pattern, this.allowedIn);

  final String name;
  final String pattern;
  final Set<String> allowedIn;
}

const _rules = [
  _Rule(
    'raw PickerPrefs window',
    r'PickerPrefs\.(pickFiles|saveFile|saveFromBuilder|getDirectoryPath)\(',
    // The wrapper itself, and PickerPrefs' own saveFromBuilder -> saveFile.
    {_guardedPicker, _pickerPrefs},
  ),
  _Rule(
    'raw file_picker window',
    r'FilePicker\.(pickFile|pickFiles|saveFile|getDirectoryPath|pickFileAndDirectoryPaths)\(',
    {_pickerPrefs},
  ),
  _Rule('raw file_picker platform call', r'FilePicker\.platform\.', {
    _pickerPrefs,
  }),
  _Rule('raw file_picker platform call', r'FilePickerPlatform\.instance\b', {
    _pickerPrefs,
  }),
];

/// Every match of every rule in lib/, as `path:line  code`, keyed by rule.
Map<_Rule, List<String>> _scanLib() {
  final hits = {for (final r in _rules) r: <String>[]};
  final compiled = {for (final r in _rules) r: RegExp(r.pattern)};
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final file in files) {
    final path = p.split(file.path).join('/');
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final code = lines[i].trim();
      if (code.startsWith('//') || code.startsWith('*')) continue;
      for (final rule in _rules) {
        if (compiled[rule]!.hasMatch(code)) {
          hits[rule]!.add('$path:${i + 1}  $code');
        }
      }
    }
  }
  return hits;
}

void main() {
  test('every file window in lib/ opens through GuardedPicker', () {
    final offenders = <String>{};
    _scanLib().forEach((rule, hits) {
      for (final hit in hits) {
        final path = hit.substring(0, hit.indexOf(':'));
        if (!rule.allowedIn.contains(path)) offenders.add('${rule.name}: $hit');
      }
    });
    expect(
      offenders,
      isEmpty,
      reason:
          'Open file windows with GuardedPicker.<method>(context, ...) so a '
          'failure shows a dialog instead of leaving the click doing nothing.',
    );
  });

  test('the patterns match the calls the allowed files really make', () {
    // A pattern that matches nothing would pass the test above forever.
    final hits = _scanLib();
    bool seenIn(String ruleName, String path) => _rules
        .where((r) => r.name == ruleName)
        .any((r) => hits[r]!.any((h) => h.startsWith('$path:')));
    expect(seenIn('raw PickerPrefs window', _guardedPicker), isTrue);
    expect(seenIn('raw file_picker window', _pickerPrefs), isTrue);
  });
}
