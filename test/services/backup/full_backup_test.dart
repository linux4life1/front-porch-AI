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
import 'package:front_porch_ai/services/backup/restore_applier.dart';
import 'package:front_porch_ai/services/backup/settings_snapshot.dart';
import 'package:front_porch_ai/services/backup/snapshot_files.dart';
import 'package:front_porch_ai/services/backup_service.dart';

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
      'front_porch_2026-10-31T12-00-00-000_before_restore.db',
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

    test('a restore without keys keeps this machine\'s KoboldCpp preset '
        'keys', () async {
      final preset = p.join(root, 'presets', 'mine.kcpps');
      await put(
        preset,
        jsonEncode({'model': 'x.gguf', 'hordekey': 'HK-1', 'password': 'pw'}),
      );
      final (out, _) = await writeBackup();
      await put(
        preset,
        jsonEncode({'model': 'y.gguf', 'hordekey': 'HK-mine', 'password': ''}),
      );
      final prefs = await SharedPreferences.getInstance();
      await PendingRestore.stageFull(root, out, currentSchema: 63);

      await applyNow(prefs);

      expect(PendingRestore.lastOutcome?.error, isNull);
      final back = jsonDecode(await File(preset).readAsString());
      expect(back['model'], 'x.gguf', reason: 'the preset itself comes back');
      expect(back['hordekey'], 'HK-mine');
      expect(back['password'], '');
    });

    test('the safety copy keeps changes still in a journal a crash left '
        'beside the library', () async {
      SharedPreferences.setMockInitialValues({});
      await _library(dbFile, 'changed library');
      // A write that is still only in the -wal file, as after a crash.
      final crashed = p.join(tmp.path, 'crashed', 'front_porch.db');
      final open = NativeDatabase(
        File(dbFile),
        enableMigrations: false,
        setup: (db) => db.execute('PRAGMA journal_mode = WAL'),
      );
      await open.ensureOpen(_Open());
      await open.runCustom("UPDATE lib SET v = 'unsaved library'");
      await Directory(p.dirname(crashed)).create();
      await File(dbFile).copy(crashed);
      await File('$dbFile-wal').copy('$crashed-wal');
      await open.close();
      await File(crashed).copy(dbFile);
      await File('$crashed-wal').copy('$dbFile-wal');
      final snap = p.join(tmp.path, 'snap.db');
      await File(crashed).copy(snap);
      await _library(snap, 'old library');
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
      expect(await _label(safetyDb()), 'unsaved library');
      expect(await File('${safetyDb()}-wal').exists(), isFalse);
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

  test('restore safety copies are kept apart from snapshot retention', () {
    final now = DateTime(2026, 10, 31, 12);
    String snap(int i) => 'front_porch_$i.db';
    String safety(int i) => 'front_porch_$i${RestoreApplier.safetySuffix}.db';
    // Newest first: an auto snapshot every half hour, with a restore's
    // safety copy among the oldest.
    final entries = [
      for (var i = 0; i < 20; i++)
        (path: snap(i), modified: now.subtract(Duration(minutes: 30 * i))),
      for (var i = 0; i < 5; i++)
        (
          path: safety(i),
          modified: now.subtract(Duration(hours: 11, minutes: i)),
        ),
    ];
    final drop = BackupService.backupsToDrop(entries, now);
    final snapshots = entries.where((e) => !e.path.contains('before'));
    final keep = BackupService.backupsToKeep(snapshots.toList(), now);

    expect(drop.intersection(keep), isEmpty);
    expect(
      drop,
      containsAll(snapshots.map((e) => e.path).where((p) => !keep.contains(p))),
    );
    expect(drop.contains(safety(0)), isFalse);
    expect(drop.contains(safety(2)), isFalse);
    expect(drop, containsAll([safety(3), safety(4)]));
  });

  group('round trip', () {
    late String root;
    late String dbFile;
    final binary = List<int>.generate(4096, (i) => (i * 37) % 256);

    String at(String rel) => p.joinAll([root, ...p.posix.split(rel)]);

    // A whole app state: the library, every kind of user file and settings
    // of every type.
    setUp(() async {
      root = p.join(tmp.path, 'FrontPorchAI');
      dbFile = p.join(root, 'KoboldManager', 'front_porch.db');
      await _library(dbFile, 'snapshot library');
      final portrait = File(at('KoboldManager/Characters/Ada.png'));
      await portrait.parent.create(recursive: true);
      await portrait.writeAsBytes(binary);
      await put(at('KoboldManager/Characters/Ada/avatars/smile.png'), 'smile');
      await put(at('groups/porch crew.png'), 'group picture');
      await put(at('worlds/Greenhollow/lore.json'), '{"lore":"old"}');
      await put(at('system/piper_voices/mine.onnx'), 'voice');
      await put(at('stories/Café night.md'), 'a story');
      await put(
        at('KoboldManager/presets/mine.kcpps'),
        '{"model":"m.gguf","hordekey":"HORDE-SECRET"}',
      );
      await put(at('models/big.gguf'), 'model weights');
      SharedPreferences.setMockInitialValues({
        'saved_prompts': 'my prompts',
        'group_system_prompt': 'group prompt',
        'font_scale': 1.25,
        'max_tokens': 512,
        'realism_default': true,
        'pinned': ['a', 'b'],
        'remote_api_key': 'sk-secret',
      });
    });

    Future<Map<String, String>> tree() async => {
      for (final rel in SnapshotFiles.userFiles(root))
        if (!rel.startsWith('KoboldManager/backups/'))
          rel: SnapshotFiles.hashOf(File(at(rel))),
    };

    Map<String, Object?> settingsOf(SharedPreferences prefs) => {
      for (final k in prefs.getKeys()) k: prefs.get(k),
    };

    /// Takes an automatic snapshot the way BackupService does: database,
    /// settings without keys, and the user's files.
    Future<String> snapshot(SharedPreferences prefs) async {
      final snap = p.join(
        root,
        'KoboldManager',
        'backups',
        'front_porch_2026-10-30T12-00-00-000.db',
      );
      await File(snap).parent.create(recursive: true);
      await File(dbFile).copy(snap);
      await put(
        BackupService.settingsPathFor(snap),
        SettingsSnapshot.capture(
          prefs,
          isNightly: false,
          includeSecrets: false,
          root: root,
        ).encode(),
      );
      await SnapshotFiles(root).capture(snap);
      return snap;
    }

    /// Everything a bad day can do: portraits deleted with their
    /// character, files changed, settings lost, the library rolled on.
    Future<void> wreck(SharedPreferences prefs) async {
      await _library(dbFile, 'wrecked library');
      await File(at('KoboldManager/Characters/Ada.png')).delete();
      await Directory(
        at('KoboldManager/Characters/Ada'),
      ).delete(recursive: true);
      await put(at('worlds/Greenhollow/lore.json'), '{"lore":"overwritten"}');
      await File(at('stories/Café night.md')).delete();
      await put(at('groups/new since.png'), 'made after the backup');
      await prefs.setString('saved_prompts', 'lost in a crash');
      await prefs.remove('group_system_prompt');
      await prefs.setDouble('font_scale', 3);
      await prefs.setStringList('pinned', []);
    }

    Future<void> launch(SharedPreferences prefs) =>
        PendingRestore.applyAtStartup(
          root: root,
          dbFile: dbFile,
          prefs: prefs,
          nightly: false,
          currentSchema: 63,
          now: () => DateTime(2026, 10, 31, 12),
        );

    test('a snapshot puts the whole app state back: every file byte for '
        'byte, every setting and the library', () async {
      final prefs = await SharedPreferences.getInstance();
      final before = await tree();
      final settingsBefore = settingsOf(prefs);
      final snap = await snapshot(prefs);
      final entry = BackupEntry(
        File(snap),
        1,
        DateTime(2026, 10, 30, 12),
        true,
        hasFiles: true,
      );
      expect(await File(SnapshotFiles.listPathFor(snap)).exists(), isTrue);

      await wreck(prefs);
      expect(await tree(), isNot(before));

      await PendingRestore.stageSnapshot(
        root,
        entry.file,
        File(BackupService.settingsPathFor(snap)),
        entry.modified,
        files: File(SnapshotFiles.listPathFor(snap)),
      );
      expect((await PendingRestore.read(root))?.withFiles, isTrue);
      await launch(prefs);

      expect(PendingRestore.lastOutcome?.error, isNull);
      expect(PendingRestore.lastOutcome?.withFiles, isTrue);
      expect(await _label(dbFile), 'snapshot library');
      final after = await tree();
      for (final rel in before.keys) {
        expect(
          after[rel],
          before[rel],
          reason: '$rel must come back as it was',
        );
      }
      expect(
        await File(at('KoboldManager/Characters/Ada.png')).readAsBytes(),
        binary,
      );
      expect(
        await File(at('groups/new since.png')).exists(),
        isTrue,
        reason: 'a file made after the snapshot is left alone',
      );
      expect(settingsOf(prefs), settingsBefore);
      expect(
        await File(
          at(
            'KoboldManager/backups/'
            'front_porch_2026-10-31T12-00-00-000_before_restore.files/'
            'worlds/Greenhollow/lore.json',
          ),
        ).readAsString(),
        '{"lore":"overwritten"}',
        reason: 'what the restore replaced is kept beside its safety copy',
      );
      expect(await PendingRestore.read(root), isNull);
    });

    test('a full backup puts the whole app state back: every file byte for '
        'byte, every setting and the library', () async {
      final prefs = await SharedPreferences.getInstance();
      final before = await tree();
      final settingsBefore = settingsOf(prefs);
      final writer = FullBackupWriter(
        root: root,
        prefs: prefs,
        nightly: false,
        appVersion: '1.6.2',
        schemaVersion: 63,
        snapshotDatabase: (target) async {
          await File(dbFile).copy(target);
          return true;
        },
      );
      final out = File(p.join(tmp.path, 'b${BackupManifest.fileExtension}'));
      await writer.write(out, includeSecrets: true);

      await wreck(prefs);
      await prefs.remove('remote_api_key');
      await PendingRestore.stageFull(root, out, currentSchema: 63);
      await launch(prefs);

      expect(PendingRestore.lastOutcome?.error, isNull);
      expect(await _label(dbFile), 'snapshot library');
      final after = await tree();
      for (final rel in before.keys) {
        expect(
          after[rel],
          before[rel],
          reason: '$rel must come back as it was',
        );
      }
      expect(settingsOf(prefs), settingsBefore);
    });

    test('snapshots store each file once, and a stored file goes once no '
        'snapshot lists it', () async {
      final prefs = await SharedPreferences.getInstance();
      // The stored files' times are real: snapshot() writes them now.
      final clock = DateTime.now();
      final store = SnapshotFiles(root, now: () => clock);
      final first = await snapshot(prefs);
      int stored() => Directory(store.storeDir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => !f.path.endsWith('index.json'))
          .length;
      final afterFirst = stored();
      expect(afterFirst, (await tree()).length);

      final second = p.join(p.dirname(first), 'front_porch_second.db');
      await File(first).copy(second);
      await store.capture(second);
      expect(stored(), afterFirst, reason: 'nothing changed, nothing copied');

      await put(at('worlds/Greenhollow/lore.json'), '{"lore":"new"}');
      final third = p.join(p.dirname(first), 'front_porch_third.db');
      await File(first).copy(third);
      await store.capture(third);
      expect(stored(), afterFirst + 1, reason: 'only the changed file');

      await BackupService.deleteBackup(File(first), cleanUp: false);
      await BackupService.deleteBackup(File(second), cleanUp: false);
      final keptByThird = (await SnapshotFiles.readList(
        SnapshotFiles.listPathFor(third),
      )).map((f) => f.sha256).toSet();

      await SnapshotFiles(root, now: () => clock).cleanUp();
      expect(stored(), afterFirst + 1, reason: 'too new to remove yet');

      await SnapshotFiles(
        root,
        now: () => clock.add(const Duration(days: 1)),
      ).cleanUp();
      expect(stored(), afterFirst);
      for (final sha in keptByThird) {
        expect(await File(store.blobPath(sha)).exists(), isTrue);
      }
    });

    test(
      'a waiting restore keeps the files it needs through a cleanup',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final snap = await snapshot(prefs);
        await PendingRestore.stageSettings(
          root,
          null,
          DateTime(2026, 10, 30, 12),
          files: File(SnapshotFiles.listPathFor(snap)),
        );
        await BackupService.deleteBackup(File(snap), cleanUp: false);
        final store = SnapshotFiles(
          root,
          now: () => DateTime.now().add(const Duration(days: 1)),
        );
        await store.cleanUp(alsoKeep: [PendingRestore.filesListIn(root)]);
        await File(at('KoboldManager/Characters/Ada.png')).delete();

        await launch(prefs);

        expect(PendingRestore.lastOutcome?.error, isNull);
        expect(
          await File(at('KoboldManager/Characters/Ada.png')).readAsBytes(),
          binary,
        );
      },
    );

    test('a snapshot keeps KoboldCpp presets without their keys, and a '
        'restore keeps this machine\'s', () async {
      final prefs = await SharedPreferences.getInstance();
      final snap = await snapshot(prefs);
      final list = await SnapshotFiles.readList(
        SnapshotFiles.listPathFor(snap),
      );
      final preset = list.singleWhere((f) => f.path.endsWith('.kcpps'));
      final stored = await File(
        SnapshotFiles(root).blobPath(preset.sha256),
      ).readAsString();
      expect(stored, isNot(contains('HORDE-SECRET')));
      expect(stored, contains('m.gguf'));

      await put(
        at('KoboldManager/presets/mine.kcpps'),
        '{"model":"other.gguf","hordekey":"HORDE-SECRET"}',
      );
      await PendingRestore.stageSnapshot(
        root,
        File(snap),
        null,
        DateTime(2026, 10, 30, 12),
        files: File(SnapshotFiles.listPathFor(snap)),
      );
      await launch(prefs);

      final back = jsonDecode(
        await File(at('KoboldManager/presets/mine.kcpps')).readAsString(),
      );
      expect(back['model'], 'm.gguf');
      expect(back['hordekey'], 'HORDE-SECRET');
    });

    test('a snapshot with a damaged stored file restores nothing', () async {
      final prefs = await SharedPreferences.getInstance();
      final snap = await snapshot(prefs);
      final list = await SnapshotFiles.readList(
        SnapshotFiles.listPathFor(snap),
      );
      final lore = list.singleWhere((f) => f.path.endsWith('lore.json'));
      await File(
        SnapshotFiles(root).blobPath(lore.sha256),
      ).writeAsString('rot');
      await wreck(prefs);
      final wrecked = await tree();

      await PendingRestore.stageSnapshot(
        root,
        File(snap),
        null,
        DateTime(2026, 10, 30, 12),
        files: File(SnapshotFiles.listPathFor(snap)),
      );
      await launch(prefs);

      expect(PendingRestore.lastOutcome?.error, contains('lore.json'));
      expect(await _label(dbFile), 'wrecked library');
      expect(await tree(), wrecked);
    });
  });
}
