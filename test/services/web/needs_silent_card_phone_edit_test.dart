// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone imports a plain card, opens its edit page and saves it. The
// card says nothing about Needs, so (ruling 2026-10-10) its chats follow
// the Porch Life Needs switch. The edit page shows that switch, and because
// the phone always posts the whole form, posting the value it was shown is
// not a choice: the card stays silent. Moving the switch writes it, as the
// desktop editor does. Real facade, repository, importer and PNG on disk.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late CharacterFacade facade;

  Future<void> boot({required bool needsGlobal}) async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'getApplicationDocumentsDirectory' ||
              call.method == 'getTemporaryDirectory') {
            return Directory.systemTemp
                .createTempSync('fpai_phone_needs_')
                .path;
          }
          return null;
        });
    SharedPreferences.setMockInitialValues({'needs_sim_default': needsGlobal});
    db = AppDatabase.forTesting();
    storage = StorageService();
    await storage.initialized;
    repo = CharacterRepository(db, storage);
    await Future<void>.delayed(Duration.zero);
    while (repo.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    facade = CharacterFacade(db, storage, null, null, repo);
  }

  tearDown(() async => db.close());

  Future<String> importPlainCard() async {
    final dir = Directory.systemTemp.createTempSync('fpai_plain_card_');
    final src = p.join(dir.path, 'Plain.png');
    await V2CardService().saveCardAsPng(
      CharacterCard(name: 'Plain', description: 'A neighbor.'),
      src,
      null,
    );
    final res = await facade.importBytes(
      await File(src).readAsBytes(),
      'Plain.png',
    );
    return res!['id'] as String;
  }

  Future<bool?> choiceOnDisk(String id) async {
    final card = repo.characters.singleWhere((c) => c.dbId == id);
    final back = await V2CardService().readCard(card.imagePath!);
    return back!.frontPorchExtensions?.needsSimChoice;
  }

  /// What the phone's edit page posts: the whole realism form, flat.
  Future<Map<String, dynamic>> phoneForm(String id) async {
    final detail = await facade.detail(id);
    return Map<String, dynamic>.from(detail!['realism'] as Map);
  }

  for (final needsGlobal in [true, false]) {
    test('global $needsGlobal: the phone shows it and a save keeps the card '
        'silent', () async {
      await boot(needsGlobal: needsGlobal);
      final id = await importPlainCard();
      expect(await choiceOnDisk(id), isNull);

      final form = await phoneForm(id);
      expect(form['needsSimEnabled'], needsGlobal);

      expect(
        await facade.update(id, {...form, 'description': 'A kind neighbor.'}),
        isTrue,
      );
      expect(
        await choiceOnDisk(id),
        isNull,
        reason: 'a phone save that left the switch alone stamped a choice',
      );
    });
  }

  test('moving the switch on the phone writes the choice', () async {
    await boot(needsGlobal: true);
    final id = await importPlainCard();
    final form = await phoneForm(id);
    await facade.update(id, {...form, 'needsSimEnabled': false});
    expect(await choiceOnDisk(id), isFalse);
  });
}
