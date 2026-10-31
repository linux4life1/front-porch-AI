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

import 'dart:convert';
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

    test(
      'an empty store after a torn write is blank and heals from .good',
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
      },
    );

    test(
      'a NUL-filled store is not blank, so the corrupt path handles it',
      () async {
        final file = File(p.join(tmp.path, 'shared_preferences.json'));
        await file.writeAsBytes(List.filled(32, 0));
        expect(await PrefsRecovery.isBlankStore(file), isFalse);
      },
    );
  });

  group('PrefsRecovery old Windows folder', () {
    Future<File> put(String path, String text) async {
      final f = File(path);
      await f.parent.create(recursive: true);
      return f.writeAsString(text);
    }

    test('stored key files are copied, never over an existing one', () async {
      final legacy = p.join(tmp.path, 'com.antigravity', 'FPAI');
      await put(p.join(legacy, 'a.secure'), 'old a');
      await put(p.join(legacy, 'b.secure'), 'old b');
      await put(p.join(legacy, 'shared_preferences.json'), '{}');
      final current = p.join(tmp.path, 'FPAI');
      await put(p.join(current, 'b.secure'), 'new b');

      final copied = await PrefsRecovery.copyLegacyFiles(
        Directory(legacy),
        Directory(current),
      );

      expect(copied, 1);
      expect(await File(p.join(current, 'a.secure')).readAsString(), 'old a');
      expect(await File(p.join(current, 'b.secure')).readAsString(), 'new b');
      expect(
        await File(p.join(current, 'shared_preferences.json')).exists(),
        isFalse,
        reason: 'the settings file is merged per channel, not copied',
      );
    });

    test('each channel brings its own settings across, whichever launches '
        'first', () async {
      final legacy = await put(
        p.join(tmp.path, 'old', 'shared_preferences.json'),
        jsonEncode({
          'flutter.saved_prompts': 'stable prompts',
          'flutter.beta_saved_prompts': 'nightly prompts',
        }),
      );
      final current = File(p.join(tmp.path, 'new', 'shared_preferences.json'));

      // Nightly launches first and later writes a stray unprefixed key.
      expect(
        await PrefsRecovery.mergeLegacySettingsFile(
          legacy,
          current,
          nightly: true,
        ),
        isTrue,
      );
      final afterNightly =
          jsonDecode(await current.readAsString()) as Map<String, dynamic>;
      expect(afterNightly['flutter.beta_saved_prompts'], 'nightly prompts');
      expect(afterNightly.containsKey('flutter.saved_prompts'), isFalse);
      afterNightly['flutter.saved_prompts'] = 'stray';
      await current.writeAsString(jsonEncode(afterNightly));

      // Stable's first launch still brings its own settings over.
      expect(
        await PrefsRecovery.mergeLegacySettingsFile(
          legacy,
          current,
          nightly: false,
        ),
        isTrue,
      );
      final both =
          jsonDecode(await current.readAsString()) as Map<String, dynamic>;
      expect(both['flutter.saved_prompts'], 'stable prompts');
      expect(both['flutter.beta_saved_prompts'], 'nightly prompts');

      // Once per channel: later launches leave the new file alone.
      both['flutter.saved_prompts'] = 'edited since';
      await current.writeAsString(jsonEncode(both));
      expect(
        await PrefsRecovery.mergeLegacySettingsFile(
          legacy,
          current,
          nightly: false,
        ),
        isFalse,
      );
      final later =
          jsonDecode(await current.readAsString()) as Map<String, dynamic>;
      expect(later['flutter.saved_prompts'], 'edited since');
    });

    test('a torn store after the move comes back from .good, not the old '
        'folder', () async {
      final legacy = File(p.join(tmp.path, 'old', 'shared_preferences.json'));
      final current = File(p.join(tmp.path, 'new', 'shared_preferences.json'));
      await legacy.parent.create(recursive: true);
      await current.parent.create(recursive: true);
      await legacy.writeAsString(
        jsonEncode({'flutter.beta_saved_prompts': 'old folder prompts'}),
      );
      await File('${current.path}.good').writeAsString(
        jsonEncode({
          'flutter.beta_saved_prompts': 'edited since the move',
          'flutter.beta_moved_from_legacy_windows_folder': true,
        }),
      );
      await current.writeAsString('');

      expect(
        await PrefsRecovery.mergeLegacySettingsFile(
          legacy,
          current,
          nightly: true,
        ),
        isFalse,
      );
      expect(await PrefsRecovery.isBlankStore(current), isTrue);
      expect(await PrefsRecovery.restoreGoodCopy(current), isNotNull);
      final healed =
          jsonDecode(await current.readAsString()) as Map<String, dynamic>;
      expect(healed['flutter.beta_saved_prompts'], 'edited since the move');
    });

    test('the old folder is copied once: a key deleted after the move stays '
        'deleted', () async {
      final legacy = p.join(tmp.path, 'com.antigravity', 'FPAI');
      await put(p.join(legacy, 'a.secure'), 'old a');
      await put(p.join(legacy, 'cache', 'img.png'), 'png');
      final current = Directory(p.join(tmp.path, 'FPAI'));

      expect(
        await PrefsRecovery.copyLegacyFiles(Directory(legacy), current),
        2,
      );
      // The user signs out or clears the cache in the new folder.
      await File(p.join(current.path, 'a.secure')).delete();
      await File(p.join(current.path, 'cache', 'img.png')).delete();

      expect(
        await PrefsRecovery.copyLegacyFiles(Directory(legacy), current),
        0,
      );
      expect(File(p.join(current.path, 'a.secure')).existsSync(), isFalse);
      expect(
        File(p.join(current.path, 'cache', 'img.png')).existsSync(),
        isFalse,
      );
      expect(File(p.join(legacy, 'a.secure')).existsSync(), isTrue);
    });
  });
}
