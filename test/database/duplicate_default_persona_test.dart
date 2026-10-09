// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A new install runs two first-run steps that could each add the default
// "User" persona: the persona service seeds one on an empty library, and the
// old JSON-to-database migration (which runs on every new install) added one
// whenever there was no old persona list. The second launch then showed two
// "User" personas. Whichever runs first, the library must end with one, and
// an old install's saved name must still be carried.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/data_migration_service.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

class _EmptyDocsDir extends PathProviderPlatform {
  _EmptyDocsDir(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase db;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fpai_first_run_persona_');
    PathProviderPlatform.instance = _EmptyDocsDir(root.path);
    db = AppDatabase.forTesting(sameIsolate: true);
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  /// A launch's persona service once its first load is in.
  Future<UserPersonaService> launchPersonas() async {
    final personas = UserPersonaService(db);
    addTearDown(personas.dispose);
    final waiting = Stopwatch()..start();
    while (personas.personas.isEmpty) {
      if (waiting.elapsed > const Duration(seconds: 20)) {
        fail('the persona service never loaded its personas');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return personas;
  }

  Future<void> migrate() => DataMigrationService(db).migrate();

  /// The second launch: what the Persona page lists, and what the library
  /// holds.
  Future<List<UserPersona>> secondLaunch() async {
    final personas = await launchPersonas();
    expect(
      await db.getAllPersonas(),
      hasLength(personas.personas.length),
      reason: 'the page lists every live persona in the library',
    );
    return personas.personas;
  }

  group('a new install has one persona on its second launch', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('persona service first, then the migration', () async {
      await launchPersonas();
      await migrate();

      final second = await secondLaunch();
      expect(second.map((p) => p.name), ['User']);
    });

    test('the migration first, then the persona service', () async {
      await migrate();
      await launchPersonas();

      final second = await secondLaunch();
      expect(second.map((p) => p.name), ['User']);
    });

    test('both at once', () async {
      await Future.wait([launchPersonas(), migrate()]);

      final second = await secondLaunch();
      expect(second.map((p) => p.name), ['User']);
    });
  });

  group('an old install\'s saved name is still carried', () {
    setUp(
      () => SharedPreferences.setMockInitialValues({
        'user_name': 'Porch Sitter',
        'user_persona': 'Likes long evenings.',
      }),
    );

    test('the migration first', () async {
      await migrate();
      await launchPersonas();

      final second = await secondLaunch();
      expect(second.map((p) => (p.name, p.persona)), [
        ('Porch Sitter', 'Likes long evenings.'),
      ]);
    });

    test('persona service first: the seed takes the old name', () async {
      await launchPersonas();
      await migrate();

      final second = await secondLaunch();
      expect(second.map((p) => (p.name, p.persona)), [
        ('Porch Sitter', 'Likes long evenings.'),
      ]);
    });
  });
}
