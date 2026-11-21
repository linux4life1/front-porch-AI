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

// A character's Title beside its name, end to end: a Backyard archive's
// `name` is what chats call the character and its `displayName` (Backyard's
// title) is kept as the title; the title lives in the card PNG and survives a
// library reload; the web editor, list and search see it. The V2 credits that
// share the PNG-only storage (creator, notes, version) survive an edit after a
// reload too. Everything goes through the importer, repository and web facade
// the app uses, on a real in-memory database and real PNG files.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a character title', () {
    late Directory root;
    late AppDatabase db;
    late StorageService storage;
    late CharacterRepository repo;
    late CharacterFacade facade;

    Future<void> settle() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (repo.isLoading) {
        if (DateTime.now().isAfter(deadline)) fail('repo did not settle');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    Future<CharacterCard> reloaded(String id) async {
      await repo.loadCharacters();
      await settle();
      return repo.characters.singleWhere((c) => c.dbId == id);
    }

    /// A v1-spec-shaped Backyard archive (invented content). [name] and
    /// [displayName] are left out when null, as an archive may.
    List<int> byaf({String? name, String? displayName}) {
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({
              'schemaVersion': 1,
              'characters': ['characters/juniper1/character.json'],
              'scenarios': ['scenarios/scenario1.json'],
            }),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'characters/juniper1/character.json',
            jsonEncode({
              'schemaVersion': 1,
              'id': 'juniper1',
              'name': ?name,
              'displayName': ?displayName,
              'isNSFW': false,
              'persona': '{character} paints the harbour for {user}.',
              'loreItems': <dynamic>[],
              'images': <dynamic>[],
            }),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'scenarios/scenario1.json',
            jsonEncode({
              'schemaVersion': 1,
              'title': 'Harbour evenings',
              'firstMessages': [
                {'text': '*{character} looks up.* Hi, {user}.'},
              ],
              'messages': <dynamic>[],
            }),
          ),
        );
      return ZipEncoder().encode(archive);
    }

    /// Imports [card] the way a dropped .png is imported; returns its id.
    Future<String> importPng(CharacterCard card) async {
      final png = '${root.path}/incoming_${card.name}.png';
      await V2CardService().saveCardAsPng(card, png, null);
      final imported = await repo.importCharacter(File(png));
      return imported!.dbId!;
    }

    setUp(() async {
      root = Directory.systemTemp.createTempSync('fpai_card_title_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => root.path,
          );
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      storage = StorageService();
      await storage.initialized;
      repo = CharacterRepository(db, storage);
      await Future<void>.delayed(Duration.zero);
      await settle();
      facade = CharacterFacade(db, storage, null, null, repo);
    });

    tearDown(() async {
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('a Backyard name is the chat name, its displayName the title, and '
        'both survive a library reload', () async {
      final result = await facade.importBytes(
        byaf(name: 'Juniper', displayName: 'Juniper Fixture'),
        'juniper.byaf',
      );
      expect(result?['name'], 'Juniper');
      final id = result!['id'] as String;

      final card = await reloaded(id);
      expect(card.name, 'Juniper');
      expect(card.title, 'Juniper Fixture');
      // {character} became {{char}}, which a chat fills with the name.
      expect(
        card.replacePlaceholders(card.firstMessage, userName: 'Rowan'),
        '*Juniper looks up.* Hi, Rowan.',
      );

      final detail = await facade.detail(id);
      expect(detail?['name'], 'Juniper');
      expect(detail?['title'], 'Juniper Fixture');

      final row = (await facade.list()).singleWhere((r) => r['id'] == id);
      expect(row['title'], 'Juniper Fixture');
      // Only the title says "fixture": a title search finds the card.
      final found = await facade.list(
        search: 'fixture',
        scope: 'allCharacters',
      );
      expect([for (final r in found) r['id']], [id]);
    });

    test('an archive with only a displayName keeps it as the name and no '
        'title', () async {
      final result = await facade.importBytes(
        byaf(displayName: 'Juniper Fixture'),
        'juniper.byaf',
      );
      final card = await reloaded(result!['id'] as String);
      expect(card.name, 'Juniper Fixture');
      expect(card.title, '');
    });

    test('a title typed in the web editor survives a reload, and clearing it '
        'clears it', () async {
      final id = await importPng(CharacterCard(name: 'Misty'));

      expect(
        await facade.update(id, {
          'title': '  Misty Meadows, Misguided Meteorologist  ',
        }),
        isTrue,
      );
      expect(
        (await reloaded(id)).title,
        'Misty Meadows, Misguided Meteorologist',
      );
      expect((await facade.detail(id))?['title'], isNotEmpty);

      // An edit that does not send a title leaves it alone.
      await facade.update(id, {'description': 'Forecasts badly.'});
      expect(
        (await reloaded(id)).title,
        'Misty Meadows, Misguided Meteorologist',
      );

      await facade.update(id, {'title': ''});
      expect((await reloaded(id)).title, '');
    });

    test('an edit after a reload keeps the card\'s V2 credits', () async {
      final id = await importPng(
        CharacterCard(
          name: 'Credited',
          creator: 'Fixture Author',
          creatorNotes: 'Made for the harbour scenes.',
          characterVersion: '1.2',
        ),
      );
      // The reload rebuilds the card from its row and PNG; the edit then
      // rewrites the PNG from that card.
      await reloaded(id);
      await facade.update(id, {'description': 'Edited after a restart.'});

      final card = await reloaded(id);
      expect(card.description, 'Edited after a restart.');
      expect(card.creator, 'Fixture Author');
      expect(card.creatorNotes, 'Made for the harbour scenes.');
      expect(card.characterVersion, '1.2');
    });

    test('a duplicate keeps the title and the credits', () async {
      final id = await importPng(
        CharacterCard(
          name: 'Alice',
          title: 'Alice Smith',
          creator: 'Fixture Author',
        ),
      );
      final copy = await repo.duplicateCharacter(await reloaded(id));
      final again = await reloaded(copy!.dbId!);
      expect(again.title, 'Alice Smith');
      expect(again.creator, 'Fixture Author');
    });
  });

  group('adoptTitle (a Backyard title or a Stoop listing name)', () {
    test('takes a name that says more than the card name', () {
      final card = CharacterCard(name: 'Misty')
        ..adoptTitle('  Misty Meadows, Misguided Meteorologist ');
      expect(card.title, 'Misty Meadows, Misguided Meteorologist');
    });

    test('ignores the name again, in any case, and blanks', () {
      for (final same in ['Misty', '  misty ', '', '   ', null]) {
        final card = CharacterCard(name: 'Misty')..adoptTitle(same);
        expect(card.title, '', reason: '"$same" only repeats the name');
      }
    });

    test('never replaces a title the card already has', () {
      final card = CharacterCard(name: 'Misty', title: 'Weather Girl')
        ..adoptTitle('Misty Meadows');
      expect(card.title, 'Weather Girl');
    });
  });
}
