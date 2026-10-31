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

// Pins complete backups: every setting round-trips with its type and
// channel, secrets only travel when asked, a full backup carries the user's
// files but not models, and a staged restore puts library, files and
// settings back at the next launch without ever writing outside the root.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/backup/backup_manifest.dart';
import 'package:front_porch_ai/services/backup/full_backup_writer.dart';
import 'package:front_porch_ai/services/backup/pending_restore.dart';
import 'package:front_porch_ai/services/backup/settings_snapshot.dart';

const _sqliteHeader = 'SQLite format 3\u0000';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('full_backup_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<File> put(String path, String text) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    return f.writeAsString(text);
  }

  group('SettingsSnapshot', () {
    test(
      'every setting comes back with its type, secrets only when asked',
      () async {
        SharedPreferences.setMockInitialValues({
          'saved_prompts': '[{"name":"Novel","content":"Write long."}]',
          'temperature': 1.0,
          'max_tokens': 512,
          'realism_default': true,
          'custom_backgrounds': ['/old/root/custom_backgrounds/a.png'],
          'remote_api_key': 'sk-secret',
          'root_path': '/old/root',
          'window_width': 900.0,
          'beta_saved_prompts': 'nightly only',
        });
        final prefs = await SharedPreferences.getInstance();

        final withKeys = SettingsSnapshot.capture(
          prefs,
          isNightly: false,
          includeSecrets: true,
          root: '/old/root',
        );
        final noKeys = SettingsSnapshot.capture(
          prefs,
          isNightly: false,
          includeSecrets: false,
          root: '/old/root',
        );
        expect(withKeys.values['remote_api_key'], 'sk-secret');
        expect(noKeys.values.containsKey('remote_api_key'), isFalse);
        expect(withKeys.values.containsKey('root_path'), isFalse);
        expect(withKeys.values.containsKey('window_width'), isFalse);
        expect(withKeys.values.containsKey('beta_saved_prompts'), isFalse);

        // Wipe and change everything, then restore the keyless snapshot.
        await prefs.setString('saved_prompts', '[]');
        await prefs.setDouble('temperature', 0.2);
        await prefs.setString('remote_api_key', 'sk-newer');
        await prefs.setString('root_path', '/new/root');
        await prefs.setString('added_later', 'gone after restore');

        final decoded = SettingsSnapshot.decode(noKeys.encode());
        await decoded.restoreInto(
          prefs,
          isNightly: false,
          newRoot: '/new/root',
        );

        expect(prefs.getString('saved_prompts'), contains('Novel'));
        expect(prefs.get('temperature'), isA<double>());
        expect(prefs.getDouble('temperature'), 1.0);
        expect(prefs.getInt('max_tokens'), 512);
        expect(prefs.getBool('realism_default'), isTrue);
        expect(prefs.getStringList('custom_backgrounds'), [
          '/new/root/custom_backgrounds/a.png',
        ]);
        expect(
          prefs.getString('remote_api_key'),
          'sk-newer',
          reason: 'a backup without keys leaves this machine\'s keys alone',
        );
        expect(prefs.getString('root_path'), '/new/root');
        expect(prefs.containsKey('added_later'), isFalse);
        expect(prefs.getString('beta_saved_prompts'), 'nightly only');
      },
    );

    test('a stable backup restores onto a nightly\'s own keys', () async {
      SharedPreferences.setMockInitialValues({'saved_prompts': 'stable'});
      final prefs = await SharedPreferences.getInstance();
      final snap = SettingsSnapshot.capture(
        prefs,
        isNightly: false,
        includeSecrets: false,
      );

      await SettingsSnapshot.decode(
        snap.encode(),
      ).restoreInto(prefs, isNightly: true);

      expect(prefs.getString('beta_saved_prompts'), 'stable');
      expect(prefs.getString('saved_prompts'), 'stable');
    });

    test('a settings file from a newer format is refused', () {
      expect(
        () => SettingsSnapshot.decode(jsonEncode({'format': 99, 'values': {}})),
        throwsFormatException,
      );
    });
  });

  group('full backup', () {
    late String root;
    late String dbFile;

    setUp(() async {
      root = p.join(tmp.path, 'FrontPorchAI');
      dbFile = p.join(root, 'KoboldManager', 'front_porch.db');
      await put(dbFile, '${_sqliteHeader}live library');
      await put(
        p.join(root, 'KoboldManager', 'Characters', 'Ada', 'avatars', 'a.png'),
        'portrait',
      );
      await put(p.join(root, 'groups', 'g.png'), 'group picture');
      await put(p.join(root, 'system', 'piper_voices', 'mine.onnx'), 'voice');
      await put(p.join(root, 'models', 'big.gguf'), 'model weights');
      await put(p.join(root, 'system', 'whisper_models', 'w.bin'), 'stt');
      await put(p.join(root, 'cache', 'web_thumbs', 't.jpg'), 'thumb');
      await put(p.join(root, 'KoboldManager', 'backups', 'old.db'), 'snap');
    });

    Future<(File, BackupManifest)> writeBackup({bool secrets = false}) async {
      SharedPreferences.setMockInitialValues({
        'saved_prompts': 'my prompts',
        'remote_api_key': 'sk-secret',
      });
      final writer = FullBackupWriter(
        root: root,
        prefs: await SharedPreferences.getInstance(),
        nightly: false,
        appVersion: '1.6.2',
        schemaVersion: 63,
        snapshotDatabase: (target) async {
          await File(target).writeAsString('${_sqliteHeader}snapshot library');
          return true;
        },
      );
      final out = File(
        p.join(tmp.path, 'out', 'b${BackupManifest.fileExtension}'),
      );
      await out.parent.create();
      final manifest = await writer.write(out, includeSecrets: secrets);
      return (out, manifest);
    }

    test(
      'carries the user\'s files and settings, never models or caches',
      () async {
        final (out, manifest) = await writeBackup();
        final zip = ZipDecoder().decodeBytes(await out.readAsBytes());
        final names = zip.files.map((f) => f.name).toSet();

        expect(names, contains(BackupManifest.entryName));
        expect(names, contains(BackupManifest.databaseEntry));
        expect(names, contains(BackupManifest.settingsEntry));
        expect(
          names,
          containsAll([
            'files/KoboldManager/Characters/Ada/avatars/a.png',
            'files/groups/g.png',
            'files/system/piper_voices/mine.onnx',
          ]),
        );
        for (final skipped in [
          'files/models/big.gguf',
          'files/system/whisper_models/w.bin',
          'files/cache/web_thumbs/t.jpg',
          'files/KoboldManager/backups/old.db',
          'files/KoboldManager/front_porch.db',
        ]) {
          expect(names, isNot(contains(skipped)));
        }
        final settings = utf8.decode(
          zip.findFile(BackupManifest.settingsEntry)!.readBytes()!,
        );
        expect(settings, contains('my prompts'));
        expect(settings, isNot(contains('sk-secret')));
        expect(manifest.hasSecrets, isFalse);
        expect(await File('${out.path}.part').exists(), isFalse);
      },
    );

    test('a staged restore puts library, files and settings back at the '
        'next launch', () async {
      final (out, _) = await writeBackup(secrets: true);
      // Life goes on after the backup.
      await put(dbFile, '${_sqliteHeader}changed library');
      await put(
        p.join(root, 'KoboldManager', 'Characters', 'Ada', 'avatars', 'a.png'),
        'changed portrait',
      );
      await File(p.join(root, 'groups', 'g.png')).delete();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_prompts', 'lost in a crash');

      await PendingRestore.stageFull(root, out, currentSchema: 63);
      expect(await PendingRestore.read(root), isNotNull);
      expect(
        await File(dbFile).readAsString(),
        contains('changed library'),
        reason: 'staging touches nothing until the next launch',
      );

      await PendingRestore.applyAtStartup(
        root: root,
        dbFile: dbFile,
        prefs: prefs,
        nightly: false,
        currentSchema: 63,
      );

      expect(PendingRestore.lastOutcome?.error, isNull);
      expect(await File(dbFile).readAsString(), contains('snapshot library'));
      expect(
        await File(
          p.join(
            root,
            'KoboldManager',
            'Characters',
            'Ada',
            'avatars',
            'a.png',
          ),
        ).readAsString(),
        'portrait',
      );
      expect(await File(p.join(root, 'groups', 'g.png')).exists(), isTrue);
      expect(prefs.getString('saved_prompts'), 'my prompts');
      expect(prefs.getString('remote_api_key'), 'sk-secret');
      expect(await PendingRestore.read(root), isNull);
    });

    test(
      'a backup from a newer app is refused before anything is staged',
      () async {
        final (out, _) = await writeBackup();
        await expectLater(
          PendingRestore.stageFull(root, out, currentSchema: 62),
          throwsFormatException,
        );
        expect(await PendingRestore.read(root), isNull);
      },
    );

    test('a file that is not a backup is refused', () async {
      final junk = await put(p.join(tmp.path, 'x.fpbackup'), 'not a zip');
      await expectLater(PendingRestore.inspect(junk), throwsFormatException);
    });
  });

  test('restore never writes outside the storage root', () {
    final root = p.join(tmp.path, 'root');
    expect(PendingRestore.safeTarget(root, '../evil.txt'), isNull);
    expect(PendingRestore.safeTarget(root, 'groups/../../evil.txt'), isNull);
    expect(PendingRestore.safeTarget(root, '/etc/passwd'), isNull);
    expect(PendingRestore.safeTarget(root, 'C:/Windows/x.dll'), isNull);
    expect(PendingRestore.safeTarget(root, 'models/big.gguf'), isNull);
    expect(
      PendingRestore.safeTarget(root, 'groups/g.png'),
      p.join(root, 'groups', 'g.png'),
    );
  });
}
