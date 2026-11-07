// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web Backups routes that restore, delete a snapshot or make a full
// backup each need the password step-up, checked by the real AuthService
// against a real database. Without the password they refuse and change
// nothing; with it they go through.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/backup/pending_restore.dart';
import 'package:front_porch_ai/services/backup_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/routes/backup_routes.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const password = 'password123';
  late Directory tmp;
  late String root;
  late AppDatabase db;
  late Router router;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('fpai_backup_routes_');
    root = p.join(tmp.path, 'root');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => tmp.path);
    SharedPreferences.setMockInitialValues({
      'root_path': root,
      'root_path_beta': root,
    });
    db = await AppDatabase.instance();
    final auth = AuthService(db);
    final storage = StorageService();
    await storage.initialized;
    router = Router();
    WebBackupRoutes(
      WebServerDeps(storage: storage, db: db, auth: auth),
      router,
    );
    expect(
      await auth.setupAccount('admin', password, isDirectLoopbackClient: true),
      SetupStatus.success,
    );
  });

  tearDown(() async {
    await AppDatabase.closeAndReset();
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException catch (e) {
      debugPrint('temp cleanup: $e');
    }
  });

  Future<shelf.Response> call(
    String method,
    String path, {
    Object? json,
    List<int>? bytes,
    Map<String, String> headers = const {},
  }) => router.call(
    shelf.Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {
        if (json != null) 'content-type': 'application/json',
        ...headers,
      },
      body: json != null ? jsonEncode(json) : bytes,
    ),
  );

  const good = {'x-current-password': password};
  const bad = {'x-current-password': 'wrong'};

  Future<String> snapshotId() async {
    final made = await call('POST', '/api/backups');
    expect(made.statusCode, 200);
    final list = jsonDecode(await made.readAsString())['snapshots'] as List;
    return '${(list.first as Map)['id']}';
  }

  Future<List<int>> fullBackup({required bool keys}) async {
    final res = await call(
      'POST',
      '/api/backups/full',
      json: {'includeSecrets': keys, 'currentPassword': password},
    );
    final text = await res.readAsString();
    expect(res.statusCode, 200, reason: text);
    final token = jsonDecode(text)['token'];
    final download = await call('GET', '/api/backups/full/$token');
    expect(download.statusCode, 200);
    return [await for (final chunk in download.read()) ...chunk];
  }

  test('a full backup needs the password, with or without keys', () async {
    for (final keys in [false, true]) {
      for (final body in [
        {'includeSecrets': keys},
        {'includeSecrets': keys, 'currentPassword': 'wrong'},
      ]) {
        final res = await call('POST', '/api/backups/full', json: body);
        expect(res.statusCode, 401, reason: 'keys: $keys, body: $body');
      }
      expect(await fullBackup(keys: keys), isNotEmpty);
    }
  });

  test('deleting a snapshot needs the password', () async {
    final id = await snapshotId();
    final file = File(p.join(root, 'KoboldManager', 'backups', id));
    for (final headers in [const <String, String>{}, bad]) {
      final res = await call('DELETE', '/api/backups/$id', headers: headers);
      expect(res.statusCode, 401);
      expect(file.existsSync(), isTrue);
    }
    final res = await call('DELETE', '/api/backups/$id', headers: good);
    expect(res.statusCode, 200);
    expect(file.existsSync(), isFalse);
  });

  test('restoring a snapshot needs the password', () async {
    final id = await snapshotId();
    for (final body in [
      <String, Object>{},
      {'currentPassword': 'wrong'},
    ]) {
      final res = await call('POST', '/api/backups/$id/restore', json: body);
      expect(res.statusCode, 401);
      expect(await PendingRestore.read(root), isNull);
    }
    final res = await call(
      'POST',
      '/api/backups/$id/restore',
      json: {'currentPassword': password},
    );
    expect(res.statusCode, 200);
    expect(
      (await PendingRestore.read(root))?.kind,
      PendingRestoreKind.snapshot,
    );
  });

  test('restoring a full backup needs the password in the headers', () async {
    final archive = await fullBackup(keys: false);
    for (final headers in [const <String, String>{}, bad]) {
      final res = await call(
        'POST',
        '/api/backups/full/restore',
        bytes: archive,
        headers: headers,
      );
      expect(res.statusCode, 401);
      expect(await PendingRestore.read(root), isNull);
    }
    final res = await call(
      'POST',
      '/api/backups/full/restore',
      bytes: archive,
      headers: good,
    );
    expect(res.statusCode, 200);
    expect((await PendingRestore.read(root))?.kind, PendingRestoreKind.full);
    await BackupService.cancelPendingRestore();
  });
}
