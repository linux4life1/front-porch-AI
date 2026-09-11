// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Waifu Coder source has one product name at every layer', () {
    final retired = '${'de'}${'sk'}';
    final forbidden = RegExp(retired, caseSensitive: false);
    final unrelatedDesktop = RegExp('${retired}top', caseSensitive: false);
    final legacyLiteral = RegExp(
      "(['\"])\\.${RegExp.escape(retired)}\\1",
      caseSensitive: false,
    );
    final files = <File>[];
    for (final root in [
      'lib/services/waifu',
      'lib/ui/waifu',
      'test/services/waifu',
      'test/ui/waifu',
    ]) {
      files.addAll(
        Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            // Belt A owns this file byte-identical. B does not rename it.
            .where((file) => !file.path.endsWith('waifu_verify_theater.dart')),
      );
    }
    files.addAll([
      File('docs/Rawhide.md'),
      File('lib/ui/chat_components/stage/chat_message_list.dart'),
      File('docs/superpowers/plans/2026-09-05-waifu-coder.md'),
      File('docs/superpowers/specs/2026-09-05-waifu-coding-design.md'),
      File('.claude/changelog.md'),
    ]);

    for (final file in files) {
      expect(
        forbidden.hasMatch(file.path),
        isFalse,
        reason: 'retired name remains in path: ${file.path}',
      );
      final checked = file
          .readAsStringSync()
          .replaceAll(unrelatedDesktop, '')
          .replaceAll(legacyLiteral, '');
      expect(
        forbidden.hasMatch(checked),
        isFalse,
        reason: 'retired name remains in ${file.path}',
      );
    }
  });
}
