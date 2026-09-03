// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Legacy JSON world import must copy climateEnabled / climate_enabled
// into WorldsCompanion. A missing key stays the SQL default (ON / 1).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/data_migration_service.dart';
import 'package:front_porch_ai/database/database.dart';

class _FakeDocsDir extends PathProviderPlatform {
  _FakeDocsDir(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase db;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai_world_mig_');
    PathProviderPlatform.instance = _FakeDocsDir(root.path);
    db = AppDatabase.forTesting();
    await db.select(db.characters).get();
  });

  tearDown(() async {
    await db.close();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test(
    '_migrateWorlds reads climate flags; missing key stays SQL default 1',
    () async {
      final worldsDir = Directory('${root.path}/worlds')
        ..createSync(recursive: true);
      File('${worldsDir.path}/old_place.json').writeAsStringSync(
        '{"name":"Old Place"}',
      );
      File('${worldsDir.path}/soul_society.json').writeAsStringSync(
        '{"name":"Soul Society","climate_enabled":false}',
      );
      File('${worldsDir.path}/camel.json').writeAsStringSync(
        '{"name":"Camel","climateEnabled":false}',
      );

      SharedPreferences.setMockInitialValues({'root_path': root.path});

      await DataMigrationService(db).migrate();

      Future<int> flag(String name) async {
        final row = await db.select(db.worlds).get();
        return row.firstWhere((w) => w.name == name).climateEnabled ? 1 : 0;
      }

      expect(await flag('Old Place'), 1);
      expect(await flag('Soul Society'), 0);
      expect(await flag('Camel'), 0);
    },
  );
}
