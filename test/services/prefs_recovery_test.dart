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

// Pins the file-surgery half of the corrupt-settings self-heal: the broken
// shared_preferences.json must be MOVED aside (kept for diagnosis), never
// deleted, and a missing or immovable file must return false rather than
// throw — startup calls this before any error UI exists.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/prefs_recovery.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('prefs_recovery_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('PrefsRecovery.moveCorruptFileAside', () {
    test('moves a NUL-filled file to .corrupt and reports true', () async {
      final file = File(p.join(tmp.path, 'shared_preferences.json'));
      // The field-reported corruption shape: all NUL bytes after power loss.
      await file.writeAsBytes(List.filled(256, 0));

      final moved = await PrefsRecovery.moveCorruptFileAside(file);

      expect(moved, isTrue);
      expect(await file.exists(), isFalse, reason: 'original must be gone');
      final backup = File('${file.path}.corrupt');
      expect(await backup.exists(), isTrue, reason: 'content kept aside');
      expect((await backup.readAsBytes()).length, 256);
    });

    test('replaces a stale .corrupt backup from an earlier incident', () async {
      final file = File(p.join(tmp.path, 'shared_preferences.json'));
      await file.writeAsString('new garbage');
      final backup = File('${file.path}.corrupt');
      await backup.writeAsString('old garbage');

      final moved = await PrefsRecovery.moveCorruptFileAside(file);

      expect(moved, isTrue);
      expect(await backup.readAsString(), 'new garbage');
    });

    test('returns false for a missing file instead of throwing', () async {
      final file = File(p.join(tmp.path, 'does_not_exist.json'));
      expect(await PrefsRecovery.moveCorruptFileAside(file), isFalse);
    });
  });

  group('PrefsRecovery good copy', () {
    test(
      'a clean store is copied to .good and a torn one never replaces it',
      () async {
        final file = File(p.join(tmp.path, 'shared_preferences.json'));
        await file.writeAsString('{"flutter.saved_prompts":"[]"}');
        expect(await PrefsRecovery.writeGoodCopy(file), isTrue);
        final good = File('${file.path}.good');
        expect(await good.readAsString(), '{"flutter.saved_prompts":"[]"}');

        await file.writeAsBytes(List.filled(64, 0));
        expect(await PrefsRecovery.writeGoodCopy(file), isFalse);
        expect(
          await good.readAsString(),
          '{"flutter.saved_prompts":"[]"}',
          reason: 'a torn store must not overwrite the last good copy',
        );
      },
    );

    test('a corrupt store comes back from .good instead of defaults', () async {
      final file = File(p.join(tmp.path, 'shared_preferences.json'));
      await file.writeAsString('{"flutter.saved_prompts":"[1]"}');
      await PrefsRecovery.writeGoodCopy(file);
      await file.writeAsBytes(List.filled(64, 0));

      expect(await PrefsRecovery.moveCorruptFileAside(file), isTrue);
      final when = await PrefsRecovery.restoreGoodCopy(file);

      expect(when, isNotNull);
      expect(await file.readAsString(), '{"flutter.saved_prompts":"[1]"}');
      expect(await File('${file.path}.corrupt').exists(), isTrue);
    });

    test('no usable .good copy leaves the store empty for defaults', () async {
      final file = File(p.join(tmp.path, 'shared_preferences.json'));
      expect(await PrefsRecovery.restoreGoodCopy(file), isNull);
      await File('${file.path}.good').writeAsString('not json');
      expect(await PrefsRecovery.restoreGoodCopy(file), isNull);
      expect(await file.exists(), isFalse);
    });

    test('an empty store after a torn write is blank and heals from .good',
        () async {
      final file = File(p.join(tmp.path, 'shared_preferences.json'));
      await file.writeAsString('{"flutter.theme":"plum"}');
      await PrefsRecovery.writeGoodCopy(file);
      // The plugin truncates before it writes; a crash in between leaves
      // zero bytes, which it reads as "no settings" without an error.
      await file.writeAsString('');

      expect(await PrefsRecovery.isBlankStore(file), isTrue);
      expect(await PrefsRecovery.restoreGoodCopy(file), isNotNull);
      expect(await file.readAsString(), '{"flutter.theme":"plum"}');
      expect(await PrefsRecovery.isBlankStore(file), isFalse);
    });

    test('a NUL-filled store is not blank, so the corrupt path handles it',
        () async {
      final file = File(p.join(tmp.path, 'shared_preferences.json'));
      await file.writeAsBytes(List.filled(32, 0));
      expect(await PrefsRecovery.isBlankStore(file), isFalse);
    });
  });

  group('PrefsRecovery.copyLegacyFolder', () {
    Future<void> put(String path, String text) async {
      final f = File(path);
      await f.parent.create(recursive: true);
      await f.writeAsString(text);
    }

    test('copies the old Windows folder into a new one without settings',
        () async {
      final legacy = p.join(tmp.path, 'com.antigravity', 'FPAI');
      await put(p.join(legacy, 'shared_preferences.json'), '{"flutter.a":1}');
      await put(p.join(legacy, 'k.secure'), 'sealed');
      final current = p.join(tmp.path, 'FPAI');

      expect(
        await PrefsRecovery.copyLegacyFolder(
          Directory(legacy),
          Directory(current),
        ),
        2,
      );
      expect(
        await File(p.join(current, 'shared_preferences.json')).readAsString(),
        '{"flutter.a":1}',
      );
      expect(await File(p.join(current, 'k.secure')).exists(), isTrue);
      expect(
        await File(p.join(legacy, 'shared_preferences.json')).exists(),
        isTrue,
        reason: 'the old folder stays as a fallback',
      );
    });

    test('never copies over settings the new folder already has', () async {
      final legacy = p.join(tmp.path, 'old');
      await put(p.join(legacy, 'shared_preferences.json'), '{"flutter.a":1}');
      final current = p.join(tmp.path, 'new');
      await put(p.join(current, 'shared_preferences.json'), '{"flutter.a":2}');

      expect(
        await PrefsRecovery.copyLegacyFolder(
          Directory(legacy),
          Directory(current),
        ),
        0,
      );
      expect(
        await File(p.join(current, 'shared_preferences.json')).readAsString(),
        '{"flutter.a":2}',
      );
    });
  });
}
