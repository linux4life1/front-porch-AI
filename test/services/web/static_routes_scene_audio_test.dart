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
// byte ranges work (an <audio> element asks for them), a revisit
// revalidates with a 304, a missing file is a 404 rather than the SPA's
// index.html, only MP3s are served, and a path cannot climb out.

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
    File(p.join(scene.path, 'LICENSE.md')).writeAsStringSync('CC0');
    // A decoy one level up, where `..` out of the scene folder would land.
    File(p.join(root.path, 'audio', 'secret.mp3')).writeAsStringSync('no');
    routes = StaticRoutes.at(webApp.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  shelf.Request get(String path, {Map<String, String> headers = const {}}) =>
      shelf.Request(
        'GET',
        Uri.parse('http://localhost/$path'),
        headers: headers,
      );

  shelf.Response ranged(String range) =>
      routes.handle(get('audio/scene/rain.mp3', headers: {'range': range}));

  Future<List<int>> body(shelf.Response r) =>
      r.read().expand((c) => c).toList();

  test('a scene sound is served whole as MP3', () async {
    final res = routes.handle(get('audio/scene/rain.mp3'));
    expect(res.statusCode, 200);
    expect(res.headers['content-type'], 'audio/mpeg');
    expect(res.headers['accept-ranges'], 'bytes');
    expect(await body(res), hasLength(100));
  });

  test('byte ranges come back as 206 with their slice', () async {
    final res = ranged('bytes=10-19');
    expect(res.statusCode, 206);
    expect(res.headers['content-range'], 'bytes 10-19/100');
    expect(await body(res), List<int>.generate(10, (i) => 10 + i));

    final open = ranged('bytes=0-');
    expect(open.statusCode, 206);
    expect(open.headers['content-range'], 'bytes 0-99/100');

    expect(ranged('bytes=-5').headers['content-range'], 'bytes 95-99/100');
  });

  test('a range it cannot satisfy is a 416; several get the whole', () async {
    for (final r in ['bytes=200-300', 'bytes=10-5', 'bytes=-0']) {
      final res = ranged(r);
      expect(res.statusCode, 416, reason: r);
      expect(res.headers['content-range'], 'bytes */100', reason: r);
    }
    final multi = ranged('bytes=0-1,5-6');
    expect(multi.statusCode, 200);
    expect(await body(multi), hasLength(100));
  });

  test('a revisit with the ETag is a 304', () async {
    final first = routes.handle(get('audio/scene/rain.mp3'));
    final tag = first.headers['etag']!;
    expect(tag, matches(RegExp(r'^"64-[0-9a-f]+"$')));
    expect(first.headers['last-modified'], isNotNull);

    final again = routes.handle(
      get('audio/scene/rain.mp3', headers: {'if-none-match': tag}),
    );
    expect(again.statusCode, 304);
    expect(await body(again), isEmpty);

    final stale = routes.handle(
      get('audio/scene/rain.mp3', headers: {'if-none-match': '"1-1"'}),
    );
    expect(stale.statusCode, 200);
  });

  test('only MP3s, nothing missing, and nothing climbs out', () {
    expect(routes.handle(get('audio/scene/hail.mp3')).statusCode, 404);
    expect(
      routes.handle(get('audio/scene/LICENSE.md')).statusCode,
      404,
      reason: 'the licence record is not served as a sound',
    );
    // An encoded slash survives URI parsing, so the guard itself is what
    // stops this one (a literal `../` is collapsed before the handler).
    expect(routes.handle(get('audio/scene/..%2Fsecret.mp3')).statusCode, 404);
  });
}
