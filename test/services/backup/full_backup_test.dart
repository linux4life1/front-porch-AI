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
import 'package:drift/drift.dart'
    show QueryExecutor, QueryExecutorUser, OpeningDetails;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/backup/backup_db_scrub.dart';
import 'package:front_porch_ai/services/backup/backup_manifest.dart';
import 'package:front_porch_ai/services/backup/full_backup_writer.dart';
import 'package:front_porch_ai/services/backup/pending_restore.dart';
import 'package:front_porch_ai/services/backup/settings_snapshot.dart';

class _Open implements QueryExecutorUser {
  @override
  int get schemaVersion => 1;
  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) =>
      Future.value();
}

/// Runs [sql] on a real SQLite file and returns the rows of the last one.
Future<List<Map<String, Object?>>> _sql(String path, List<String> sql) async {
  await File(path).parent.create(recursive: true);
  final db = NativeDatabase(File(path), enableMigrations: false);
  try {
    await db.ensureOpen(_Open());
    for (final s in sql.take(sql.length - 1)) {
      await db.runCustom(s);
    }
    final last = sql.last;
    if (last.trimLeft().toUpperCase().startsWith('SELECT')) {
      return await db.runSelect(last, const []);
    }
    await db.runCustom(last);
    return const [];
  } finally {
    await db.close();
  }
}

/// A real library database holding [label], with a web login and one
/// signed-in device named after it.
Future<void> _library(String path, String label) => _sql(path, [
  'CREATE TABLE IF NOT EXISTS lib (v TEXT)',
  'DELETE FROM lib',
  "INSERT INTO lib VALUES ('$label')",
  'CREATE TABLE IF NOT EXISTS web_auth_credentials (id TEXT PRIMARY KEY, '
      'username TEXT, password_hash TEXT, totp_secret TEXT)',
  'DELETE FROM web_auth_credentials',
  "INSERT INTO web_auth_credentials VALUES ('1', 'admin', "
      "'hash-$label', 'SEED$label')",
  'CREATE TABLE IF NOT EXISTS web_auth_sessions (id TEXT PRIMARY KEY, '
      'token_hash TEXT)',
  "INSERT OR REPLACE INTO web_auth_sessions VALUES ('$label', 'tok')",
]);

Future<String> _label(String path) async =>
    '${(await _sql(path, ['SELECT v FROM lib'])).single['v']}';

Future<String> _login(String path) async =>
    '${(await _sql(path, ['SELECT password_hash FROM web_auth_credentials'])).single['password_hash']}';

Future<int> _rows(String path, String table) async =>
    (await _sql(path, ['SELECT * FROM $table'])).length;

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
      'paths move only under the old storage folder, by whole segment',
      () async {
        SharedPreferences.setMockInitialValues({
          'last_export_dir': '/x/FrontPorchAI/exports',
          'beta_root_note': 'unused',
          'other_folder': '/x/FrontPorchAI-Beta/exports',
        });
        final prefs = await SharedPreferences.getInstance();
        final snap = SettingsSnapshot.decode(
          SettingsSnapshot.capture(
            prefs,
            isNightly: false,
            includeSecrets: false,
            root: '/x/FrontPorchAI',
          ).encode(),
        );
        await snap.restoreInto(prefs, isNightly: false, newRoot: '/y/FP');
        expect(prefs.getString('last_export_dir'), '/y/FP/exports');
        expect(prefs.getString('other_folder'), '/x/FrontPorchAI-Beta/exports');
      },
    );

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
      await _library(dbFile, 'live library');
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
          await File(dbFile).copy(target);
          await _library(target, 'snapshot library');
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
      await _library(dbFile, 'changed library');
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
        await _label(dbFile),
        'changed library',
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
      expect(await _label(dbFile), 'snapshot library');
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

    Future<void> applyNow(SharedPreferences prefs) =>
        PendingRestore.applyAtStartup(
          root: root,
          dbFile: dbFile,
          prefs: prefs,
          nightly: false,
          currentSchema: 63,
          now: () => DateTime(2026, 10, 31, 12),
        );

    String safetyDb() => p.join(
      root,
      'KoboldManager',
      'backups',
      'front_porch_2026-10-31T12-00-00-000.db',
    );

    String portrait() =>
        p.join(root, 'KoboldManager', 'Characters', 'Ada', 'avatars', 'a.png');

    test('a KoboldCpp preset travels without its Horde key or API password '
        'unless keys go in', () async {
      await put(
        p.join(root, 'presets', 'mine.kcpps'),
        jsonEncode({'model': 'x.gguf', 'hordekey': 'HK-1', 'password': 'pw'}),
      );
      for (final secrets in [false, true]) {
        final (out, _) = await writeBackup(secrets: secrets);
        final zip = ZipDecoder().decodeBytes(await out.readAsBytes());
        final preset = jsonDecode(
          utf8.decode(zip.findFile('files/presets/mine.kcpps')!.readBytes()!),
        );
        expect(preset['model'], 'x.gguf');
        expect(preset['hordekey'], secrets ? 'HK-1' : '');
        expect(preset['password'], secrets ? 'pw' : '');
      }
    });

    test('a backup without keys carries no web login and no signed-in '
        'devices; with keys, the login but still no devices', () async {
      for (final secrets in [false, true]) {
        final (out, _) = await writeBackup(secrets: secrets);
        final zip = ZipDecoder().decodeBytes(await out.readAsBytes());
        final db = File(p.join(tmp.path, 'inside_$secrets.db'));
        await db.writeAsBytes(
          zip.findFile(BackupManifest.databaseEntry)!.readBytes()!,
        );
        expect(await _label(db.path), 'snapshot library');
        expect(await _rows(db.path, 'web_auth_sessions'), 0);
        expect(
          await _rows(db.path, 'web_auth_credentials'),
          secrets ? 1 : 0,
          reason: 'the TOTP seed travels only with keys',
        );
        final raw = await db.readAsString(encoding: latin1);
        if (!secrets) expect(raw, isNot(contains('SEEDsnapshot')));
      }
    });

    test(
      'a restore keeps this machine\'s web login, signs every device '
      'out, and first copies what it replaces beside a safety snapshot',
      () async {
        final (out, _) = await writeBackup(secrets: true);
        await _library(dbFile, 'changed library');
        await put(portrait(), 'changed portrait');
        final prefs = await SharedPreferences.getInstance();
        await PendingRestore.stageFull(root, out, currentSchema: 63);

        await applyNow(prefs);

        expect(PendingRestore.lastOutcome?.error, isNull);
        expect(await _label(dbFile), 'snapshot library');
        expect(await _login(dbFile), 'hash-changed library');
        expect(await _rows(dbFile, 'web_auth_sessions'), 0);
        // The safety copy is the library as it was at this launch.
        expect(await _label(safetyDb()), 'changed library');
        final sidecar = File('${p.withoutExtension(safetyDb())}.settings.json');
        expect(await sidecar.readAsString(), isNot(contains('sk-secret')));
        expect(
          await File(
            p.join(
              '${p.withoutExtension(safetyDb())}.files',
              'KoboldManager',
              'Characters',
              'Ada',
              'avatars',
              'a.png',
            ),
          ).readAsString(),
          'changed portrait',
        );
      },
    );

    test('a snapshot restore takes its safety copy at launch and keeps this '
        'machine\'s login too', () async {
      final snap = p.join(tmp.path, 'snap.db');
      await File(dbFile).copy(snap);
      await _library(snap, 'old library');
      await _library(dbFile, 'changed library');
      final prefs = await SharedPreferences.getInstance();
      await PendingRestore.stageSnapshot(
        root,
        File(snap),
        null,
        DateTime(2026, 10, 30),
      );

      await applyNow(prefs);

      expect(PendingRestore.lastOutcome?.error, isNull);
      expect(await _label(dbFile), 'old library');
      expect(await _login(dbFile), 'hash-changed library');
      expect(await _rows(dbFile, 'web_auth_sessions'), 0);
      expect(await _label(safetyDb()), 'changed library');
    });

    test('a restore that fails part-way puts back what it already moved and '
        'leaves the library alone', () async {
      final (out, _) = await writeBackup();
      await _library(dbFile, 'changed library');
      await put(portrait(), 'changed portrait');
      // A folder where the group picture goes: that move cannot happen.
      final group = p.join(root, 'groups', 'g.png');
      await File(group).delete();
      await put(p.join(group, 'blocker'), 'x');
      final prefs = await SharedPreferences.getInstance();
      await PendingRestore.stageFull(root, out, currentSchema: 63);

      await applyNow(prefs);

      expect(PendingRestore.lastOutcome?.error, isNotNull);
      expect(await File(portrait()).readAsString(), 'changed portrait');
      expect(await _label(dbFile), 'changed library');
      expect(prefs.getString('saved_prompts'), 'my prompts');
      expect(
        await Directory(
          p.join(PendingRestore.dirFor(root).path, 'staging'),
        ).exists(),
        isFalse,
      );
    });

    test('nothing is restored when the safety copy cannot be made', () async {
      final (out, _) = await writeBackup();
      await _library(dbFile, 'changed library');
      final backups = Directory(p.join(root, 'KoboldManager', 'backups'));
      await backups.delete(recursive: true);
      await put(backups.path, 'a file where the backups folder goes');
      final prefs = await SharedPreferences.getInstance();
      await PendingRestore.stageFull(root, out, currentSchema: 63);

      await applyNow(prefs);

      expect(PendingRestore.lastOutcome?.error, isNotNull);
      expect(await _label(dbFile), 'changed library');
    });

    test('a hostile archive writes nothing outside the root and never over '
        'the live database, restore folder or models', () async {
      final (good, manifest) = await writeBackup();
      final zip = ZipDecoder().decodeBytes(await good.readAsBytes());
      final evil = Archive();
      for (final name in [
        BackupManifest.entryName,
        BackupManifest.databaseEntry,
        BackupManifest.settingsEntry,
      ]) {
        evil.addFile(ArchiveFile.bytes(name, zip.findFile(name)!.readBytes()!));
      }
      for (final name in [
        'files/../evil.txt',
        'files/groups/../../evil2.txt',
        'files/KoboldManager/front_porch.db',
        'files/KoboldManager/restore/pending.json',
        'files/models/x.gguf',
        'files/groups/ok.png',
      ]) {
        evil.addFile(ArchiveFile.string(name, 'payload'));
      }
      final out = File(p.join(tmp.path, 'evil${BackupManifest.fileExtension}'));
      await out.writeAsBytes(ZipEncoder().encode(evil));
      expect(manifest.fileCount, greaterThan(0));
      final prefs = await SharedPreferences.getInstance();
      await PendingRestore.stageFull(root, out, currentSchema: 63);

      await applyNow(prefs);

      expect(PendingRestore.lastOutcome?.error, isNull);
      expect(await File(p.join(tmp.path, 'evil.txt')).exists(), isFalse);
      expect(await File(p.join(tmp.path, 'evil2.txt')).exists(), isFalse);
      expect(await File(p.join(root, 'evil.txt')).exists(), isFalse);
      expect(await _label(dbFile), 'snapshot library');
      expect(await File(p.join(root, 'models', 'x.gguf')).exists(), isFalse);
      expect(
        await File(p.join(root, 'groups', 'ok.png')).readAsString(),
        'payload',
      );
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

  test('a restore from the Backups list keeps this machine\'s login and '
      'signs devices out', () async {
    final live = p.join(tmp.path, 'front_porch.db');
    final backup = p.join(tmp.path, 'backups', 'front_porch_old.db');
    await Directory(p.dirname(backup)).create(recursive: true);
    await _library(live, 'changed library');
    await _library(backup, 'old library');
    final staged = '$live.restore.tmp';

    await BackupDbScrub.stageCopy(backup, staged, live);

    expect(await _label(staged), 'old library');
    expect(await _login(staged), 'hash-changed library');
    expect(await _rows(staged, 'web_auth_sessions'), 0);
    expect(await _login(backup), 'hash-old library', reason: 'source kept');
  });
}
