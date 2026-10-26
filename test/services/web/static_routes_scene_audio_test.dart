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

// The web chat plays the scene sound from /audio/scene/<file>, served from
// the desktop's own bundled assets/audio/scene (docs/design/ambient-stage.md
// §5), not a second copy in the Vite bundle: the file comes back as MP3,
// byte ranges work (an <audio> element asks for them), a missing file is a
// 404 rather than the SPA's index.html, and a path cannot climb out.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;

import 'package:front_porch_ai/services/web/routes/static_routes.dart';

void main() {
  late Directory root;
  late StaticRoutes routes;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fpa_scene_audio');
    final webApp = Directory(p.join(root.path, 'web_app'))..createSync();
    File(p.join(webApp.path, 'index.html')).writeAsStringSync('<html>');
    final scene = Directory(p.join(root.path, 'audio', 'scene'))
      ..createSync(recursive: true);
    File(
      p.join(scene.path, 'rain.mp3'),
    ).writeAsBytesSync(List<int>.generate(100, (i) => i));
    File(p.join(root.path, 'secret.txt')).writeAsStringSync('no');
    routes = StaticRoutes.at(webApp.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  shelf.Request get(String path, {String? range}) => shelf.Request(
    'GET',
    Uri.parse('http://localhost/$path'),
    headers: {'range': ?range},
  );

  test('a scene sound is served whole as MP3', () async {
    final res = routes.handle(get('audio/scene/rain.mp3'));
    expect(res.statusCode, 200);
    expect(res.headers['content-type'], 'audio/mpeg');
    expect(res.headers['accept-ranges'], 'bytes');
    expect(await res.read().expand((c) => c).toList(), hasLength(100));
  });

  test('byte ranges come back as 206 with their slice', () async {
    final res = routes.handle(
      get('audio/scene/rain.mp3', range: 'bytes=10-19'),
    );
    expect(res.statusCode, 206);
    expect(res.headers['content-range'], 'bytes 10-19/100');
    expect(
      await res.read().expand((c) => c).toList(),
      List<int>.generate(10, (i) => 10 + i),
    );

    final open = routes.handle(get('audio/scene/rain.mp3', range: 'bytes=0-'));
    expect(open.statusCode, 206);
    expect(open.headers['content-range'], 'bytes 0-99/100');

    final tail = routes.handle(get('audio/scene/rain.mp3', range: 'bytes=-5'));
    expect(tail.headers['content-range'], 'bytes 95-99/100');

    final past = routes.handle(
      get('audio/scene/rain.mp3', range: 'bytes=200-300'),
    );
    expect(past.statusCode, 416);
  });

  test('a missing sound is a 404, and nothing climbs out', () async {
    expect(routes.handle(get('audio/scene/hail.mp3')).statusCode, 404);
    for (final path in [
      'audio/scene/../../secret.txt',
      'audio/scene/%2E%2E/%2E%2E/secret.txt',
      'audio/scene/..%2F..%2Fsecret.txt',
    ]) {
      final res = routes.handle(get(path));
      final body = String.fromCharCodes(
        await res.read().expand((c) => c).toList(),
      );
      expect(body, isNot('no'), reason: path);
    }
  });
}
