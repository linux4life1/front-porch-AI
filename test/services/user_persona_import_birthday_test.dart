// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late UserPersonaService personas;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase.forTesting();
    personas = UserPersonaService(db);
    tmp = Directory.systemTemp.createTempSync('persona_import_');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  tearDown(() async {
    personas.dispose();
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<File> nativeFile() async {
    final f = File('${tmp.path}/personas.json');
    await f.writeAsString(
      jsonEncode({
        'personas': [
          {
            'id': 'imp-bday',
            'name': 'Sam',
            'persona': 'A tired PI.',
            'birthday': '1998-03-15',
          },
        ],
      }),
    );
    return f;
  }

  test('native import writes birthday to DB', () async {
    final f = await nativeFile();
    final imported = await personas.importFromJsonFile(f.path);
    expect(imported, isNotNull);
    expect(imported!.birthday, '1998-03-15');
    final rows = await db.getAllPersonas();
    final row = rows.singleWhere((p) => p.id == imported.id);
    expect(row.birthday, '1998-03-15');
  });

  test('duplicate-id rebuild still keeps the birthday', () async {
    final f = await nativeFile();
    final first = await personas.importFromJsonFile(f.path);
    expect(first, isNotNull);
    expect(first!.birthday, '1998-03-15');
    // Native batch returns the parsed object, not the rebuilt row.
    // A second import must persist a new id with the same date.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = await personas.importFromJsonFile(f.path);
    expect(second, isNotNull);
    expect(second!.birthday, '1998-03-15');
    final dated = personas.personas
        .where((p) => p.birthday == '1998-03-15')
        .toList();
    expect(dated.length, 2);
    expect(dated.map((p) => p.id).toSet().length, 2);
    final rows = await db.getAllPersonas();
    final dbDated = rows.where((p) => p.birthday == '1998-03-15').toList();
    expect(dbDated.length, 2);
    expect(dbDated.map((p) => p.id).toSet().length, 2);
  });
}
