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

// The phone's .porch relay (issue #348): /api/porch/export hands back the
// file the desktop would save, named by the server, and /api/porch/import
// reads it into another library and answers in the desktop's words. The
// real routes, facade, exporter and importer run in process.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/porch/porch.dart';
import 'package:front_porch_ai/services/web/facade/porch_facade.dart';
import 'package:front_porch_ai/services/web/routes/porch_routes.dart';
import '../porch/porch_test_library.dart';

void main() {
  setUpPorchTestPlatform();

  late Directory tmp;
  late PorchTestLibrary a;
  late PorchTestLibrary b;

  setUp(() {
    resetPorchTestPrefs();
    tmp = Directory.systemTemp.createTempSync('fpai_porch_web_');
    a = PorchTestLibrary('${tmp.path}/library-a');
    b = PorchTestLibrary('${tmp.path}/library-b');
  });

  tearDown(() async {
    await a.close();
    await b.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Router routerFor(PorchTestLibrary lib) {
    final router = Router();
    WebPorchRoutes(PorchFacade(lib.repo, lib.chat, lib.storage), router);
    return router;
  }

  Future<shelf.Response> post(Router r, String path, Object body) => r.call(
    shelf.Request(
      'POST',
      Uri.parse('http://localhost$path'),
      body: body is String ? body : body as List<int>,
    ),
  );

  test('two characters export as one .porchpack named by the server, and the '
      'same file imported elsewhere, then again, says what it did', () async {
    final aria = await a.seed('Aria Vale', 1);
    final bram = await a.seed('Bram Elder', 2);

    final out = await post(
      routerFor(a),
      '/api/porch/export',
      jsonEncode({
        'ids': [aria.dbId, bram.dbId, 'group_1700000000000'],
      }),
    );
    expect(out.statusCode, 200);
    expect(
      out.headers['content-disposition'],
      "attachment; filename*=UTF-8''Front%20Porch%20characters%20(2).porchpack",
    );
    final bytes = await out.read().expand((c) => c).toList();

    final url =
        '/api/porch/import?filename=Front%20Porch%20characters.porchpack';
    final first = await post(routerFor(b), url, bytes);
    expect(first.statusCode, 200);
    final report = jsonDecode(await first.readAsString()) as Map;
    expect(report['imported'], ['Aria Vale', 'Bram Elder']);
    expect(report['message'], 'Imported 2 characters.');

    final again = await post(routerFor(b), url, bytes);
    final second = jsonDecode(await again.readAsString()) as Map;
    expect(
      second['message'],
      'Skipped 2 you already have: Aria Vale, Bram Elder.',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a selection with no character, and a file that is not a .porch, are '
      'refused in plain words', () async {
    final none = await post(
      routerFor(a),
      '/api/porch/export',
      jsonEncode({
        'ids': ['group_1700000000000'],
      }),
    );
    expect(none.statusCode, 409);
    expect(
      (jsonDecode(await none.readAsString()) as Map)['error'],
      startsWith('Pick at least one character to export.'),
    );

    final png = await post(
      routerFor(a),
      '/api/porch/import?filename=card.png',
      porchTestPicture(3),
    );
    expect(png.statusCode, 200);
    final report = jsonDecode(await png.readAsString()) as Map;
    expect(report['imported'], isEmpty);
    expect(
      report['message'],
      startsWith('“card.png” isn’t a .porch or .porchpack file'),
    );
    expect(kPorchExtension, 'porch');
  });
}
