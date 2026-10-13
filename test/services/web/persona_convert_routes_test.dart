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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/persona_conversion_facade.dart';
import 'package:front_porch_ai/services/web/routes/persona_convert_routes.dart';

import '../../golden/support/creator_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  test('the phone wizards can show the persona picture a new character '
      'will start with', () async {
    final root = Directory.systemTemp.createTempSync('fpai_persona_portrait_');
    final db = AppDatabase.forTesting(sameIsolate: true);
    final storage = await makeGoldenStorage();
    final personas = UserPersonaService(db);
    addTearDown(() async {
      personas.dispose();
      await db.close();
      root.deleteSync(recursive: true);
    });
    while (personas.personas.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final png = img.encodePng(img.Image(width: 5, height: 4));
    final picture = File(p.join(root.path, 'jo.png'))..writeAsBytesSync(png);
    final withPicture = await personas.createPersona(
      '',
      'Jo',
      '',
      picture.path,
    );
    final without = await personas.createPersona('', 'Kit', '', null);

    final router = Router();
    WebPersonaConvertRoutes(
      PersonaConversionFacade(
        CharacterRepository(db, storage),
        personas,
        storage,
      ),
      router,
    );
    Future<shelf.Response> get(String id) => router.call(
      shelf.Request(
        'GET',
        Uri.parse('http://localhost/api/persona-convert/persona/$id/portrait'),
      ),
    );

    final ok = await get(withPicture);
    expect(ok.statusCode, 200);
    expect(ok.headers['content-type'], 'image/png');
    final served = await ok.read().expand((b) => b).toList();
    expect(served, png);

    expect((await get(without)).statusCode, 404);
    picture.deleteSync();
    expect((await get(withPicture)).statusCode, 404);
  });
}
