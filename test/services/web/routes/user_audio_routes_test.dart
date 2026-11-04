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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/storage/user_audio_store.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/routes/user_audio_routes.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

void main() {
  late Directory root;
  late StorageService storage;
  late AppDatabase db;
  late Router router;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fpai_user_audio_route');
    storage = StorageService.sandbox(root.path);
    db = AppDatabase.forTesting();
    router = Router();
    UserAudioRoutes(
      WebServerDeps(storage: storage, db: db, auth: AuthService(db)),
      router,
    );
    UserAudioStore.testLoadOverride = null;
  });

  tearDown(() async {
    UserAudioStore.testLoadOverride = null;
    await db.close();
    root.deleteSync(recursive: true);
  });

  Future<shelf.Response> handle(shelf.Request r) => router.call(r);

  Future<List<int>> body(shelf.Response r) =>
      r.read().expand((c) => c).toList();

  test(
    'a user sound is served from the live root with streamed ranges',
    () async {
      final audio = Directory(p.join(root.path, 'audio'))..createSync();
      File(
        p.join(audio.path, 'forest.mp3'),
      ).writeAsBytesSync(List<int>.generate(100, (i) => i));
      final res = await handle(
        shelf.Request(
          'GET',
          Uri.parse('http://localhost/api/user/audio/forest.mp3'),
          headers: {'range': 'bytes=10-19'},
        ),
      );
      expect(res.statusCode, 206);
      expect(res.headers['content-type'], 'audio/mpeg');
      expect(res.headers['content-range'], 'bytes 10-19/100');
      expect(await body(res), List<int>.generate(10, (i) => 10 + i));
    },
  );

  test('a climbing name is refused', () async {
    Directory(p.join(root.path, 'audio')).createSync();
    File(p.join(root.path, 'secret.mp3')).writeAsStringSync('no');
    final res = await handle(
      shelf.Request(
        'GET',
        Uri.parse('http://localhost/api/user/audio/..%2Fsecret.mp3'),
      ),
    );
    expect(res.statusCode, 404);
  });

  test(
    'the library endpoint returns names, sizes and mtimes newest first',
    () async {
      final audio = Directory(p.join(root.path, 'audio'))..createSync();
      final old = File(p.join(audio.path, 'old rain.mp3'))
        ..writeAsBytesSync(List<int>.filled(40, 7));
      File(p.join(audio.path, 'notes.txt')).writeAsStringSync('not a sound');
      final fresh = File(p.join(audio.path, 'creek.mp3'))
        ..writeAsBytesSync(List<int>.filled(90, 7));
      final now = DateTime.now();
      old.setLastModifiedSync(now.subtract(const Duration(days: 2)));
      fresh.setLastModifiedSync(now);

      final res = await handle(
        shelf.Request('GET', Uri.parse('http://localhost/api/user/audio')),
      );
      expect(res.statusCode, 200);
      final json =
          jsonDecode(utf8.decode(await body(res))) as Map<String, dynamic>;
      final sounds = (json['sounds'] as List).cast<Map<String, dynamic>>();
      expect(sounds.map((s) => s['name']).toList(), [
        'creek.mp3',
        'old rain.mp3',
      ]);
      expect(sounds.first['bytes'], 90);
      expect(sounds.last['bytes'], 40);
      expect(
        sounds.first['modifiedMs'],
        greaterThan(sounds.last['modifiedMs']),
      );
    },
  );

  test('an upload stores a bare name and rejects a bad header', () async {
    UserAudioStore.testLoadOverride = (path) async {};
    final ok = await handle(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/worlds/audio?name=ok.mp3'),
        body: Uint8List.fromList([0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0]),
      ),
    );
    expect(ok.statusCode, 200);
    expect(File(p.join(root.path, 'audio', 'ok.mp3')).existsSync(), isTrue);

    final bad = await handle(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/worlds/audio?name=bad.mp3'),
        body: Uint8List.fromList([0, 0]),
      ),
    );
    expect(bad.statusCode, 400);
    expect(File(p.join(root.path, 'audio', 'bad.mp3')).existsSync(), isFalse);
  });
}
