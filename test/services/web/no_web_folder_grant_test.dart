// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Use this folder" saves a folder ComfyUI's config named as a models folder.
// That is a decision for the person at this computer: no route the phone or
// the web can call may save a models folder, and none may name the path of a
// refused folder. The code that saves them is reachable from the desktop
// sheet only.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _grants = [
  'addTrustedModelFolder',
  'rememberStudioModelRoot',
  'kStudioExtraModelRootsKey',
  'kStudioModelRootsKey',
  'kStudioModelRootsResolvedKey',
];

void main() {
  test('nothing under lib/services/web can save a models folder', () {
    final offenders = <String>[];
    for (final entity in Directory(
      'lib/services/web',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      for (final name in _grants) {
        if (text.contains(name)) {
          offenders.add('${p.basename(entity.path)}: $name');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('the code that saves them is used by the desktop sheet', () {
    // The guard above only means something if the grant is used somewhere.
    final sheet = File(
      'lib/ui/image_studio/studio_civitai_get.dart',
    ).readAsStringSync();
    expect(sheet, contains('addTrustedModelFolder'));
  });

  test('a refusal that carries a folder is never put in a response', () {
    final offenders = <String>[];
    for (final entity in Directory(
      'lib/services/web',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (RegExp(
        r'\be\.folder\b|\.folder\b',
      ).hasMatch(entity.readAsStringSync())) {
        offenders.add(p.basename(entity.path));
      }
    }
    expect(offenders, isEmpty);
  });
}
