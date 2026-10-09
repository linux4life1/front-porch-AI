// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Legacy JSON group import brings in EXISTING groups. One saved before the
// inherit field existed always inherited member lorebooks, so a missing key
// must import on (only new groups default off). A saved value is kept.

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
    root = Directory.systemTemp.createTempSync('fpai_group_mig_');
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

  test('an old group without the key inherits; a saved false stays', () async {
    final dir = Directory('${root.path}/chats/groups')
      ..createSync(recursive: true);
    File(
      '${dir.path}/old.json',
    ).writeAsStringSync('{"id":"g-old","name":"Old Porch"}');
    File('${dir.path}/off.json').writeAsStringSync(
      '{"id":"g-off","name":"Quiet Porch","inherit_character_lorebooks":false}',
    );
    SharedPreferences.setMockInitialValues({'root_path': root.path});

    await DataMigrationService(db).migrate();

    expect((await db.getGroupById('g-old'))!.inheritCharacterLorebooks, isTrue);
    expect(
      (await db.getGroupById('g-off'))!.inheritCharacterLorebooks,
      isFalse,
    );
  });
}
