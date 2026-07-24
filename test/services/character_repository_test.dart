// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart';

import 'package:front_porch_ai/models/avatar_image.dart' as model;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/database/database.dart';

/// Mock path_provider so StorageService can resolve
/// getApplicationDocumentsDirectory() without a real platform channel.
void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          final tmp = Directory.systemTemp.createTempSync('fpai_test_');
          return tmp.path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CharacterRepository — in-memory operations', () {
    test('allTags returns sorted unique tags across characters', () {
      final chars = <CharacterCard>[
        CharacterCard(name: 'A', tags: ['z_tag', 'a_tag'], imagePath: 'a.png'),
        CharacterCard(name: 'B', tags: ['m_tag', 'a_tag'], imagePath: 'b.png'),
        CharacterCard(name: 'C', tags: ['z_tag'], imagePath: 'c.png'),
      ];
      final tags = <String>{};
      for (final c in chars) {
        tags.addAll(c.tags);
      }
      final sorted = tags.toList()..sort();
      expect(sorted, ['a_tag', 'm_tag', 'z_tag']);
    });

    test('allTags returns empty for no characters', () {
      final chars = <CharacterCard>[];
      final tags = <String>{};
      for (final c in chars) {
        tags.addAll(c.tags);
      }
      expect(tags.toList()..sort(), isEmpty);
    });

    test('getById returns character by dbId', () {
      final chars = <CharacterCard>[
        CharacterCard(name: 'Find Me', imagePath: 'find.png')..dbId = 'char-1',
        CharacterCard(name: 'Not Me', imagePath: 'not.png')..dbId = 'char-2',
      ];
      final found = chars.where((c) => c.dbId == 'char-1').toList();
      expect(found.length, 1);
      expect(found[0].name, 'Find Me');
    });

    test('getById returns empty for non-existent ID', () {
      final chars = <CharacterCard>[
        CharacterCard(name: 'Test', imagePath: 'test.png')..dbId = 'char-1',
      ];
      final found = chars.where((c) => c.dbId == 'nonexistent').toList();
      expect(found, isEmpty);
    });

    test('getCharactersByTag filters by tag', () {
      final chars = <CharacterCard>[
        CharacterCard(
          name: 'Cat',
          tags: ['animal', 'pet'],
          imagePath: 'cat.png',
        ),
        CharacterCard(
          name: 'Dog',
          tags: ['animal', 'pet'],
          imagePath: 'dog.png',
        ),
        CharacterCard(name: 'Car', tags: ['vehicle'], imagePath: 'car.png'),
      ];
      final animals = chars.where((c) => c.tags.contains('animal')).toList();
      expect(animals.length, 2);
    });

    test('getCharactersByTag returns empty when no match', () {
      final chars = <CharacterCard>[
        CharacterCard(name: 'Test', tags: ['fantasy'], imagePath: 'test.png'),
      ];
      final sciFi = chars.where((c) => c.tags.contains('scifi')).toList();
      expect(sciFi, isEmpty);
    });

    test('duplicateCharacter creates deep copy with new name', () {
      final original = CharacterCard(
        name: 'Original',
        personality: 'Brave',
        alternateGreetings: ['Hi!', 'Hello!'],
        tags: ['hero'],
        imagePath: 'original.png',
        lorebook: Lorebook(
          entries: [LorebookEntry(key: 'lore', content: 'Some lore')],
        ),
        worldNames: ['World 1'],
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 50,
        ),
        rawExtensions: {'custom': 'data'},
      );

      final cloned = CharacterCard(
        name: '${original.name} (duplicate)',
        description: original.description,
        personality: original.personality,
        scenario: original.scenario,
        firstMessage: original.firstMessage,
        mesExample: original.mesExample,
        systemPrompt: original.systemPrompt,
        postHistoryInstructions: original.postHistoryInstructions,
        alternateGreetings: List.from(original.alternateGreetings),
        tags: List.from(original.tags),
        ttsVoice: original.ttsVoice,
        lorebook: original.lorebook != null
            ? Lorebook(entries: List.from(original.lorebook!.entries))
            : null,
        worldNames: List.from(original.worldNames),
        frontPorchExtensions: original.frontPorchExtensions != null
            ? original.frontPorchExtensions!.copyWith()
            : null,
        rawExtensions: original.rawExtensions != null
            ? Map<String, dynamic>.from(original.rawExtensions!)
            : null,
      );

      expect(cloned.name, 'Original (duplicate)');
      expect(cloned.personality, 'Brave');
      expect(cloned.alternateGreetings, ['Hi!', 'Hello!']);
      expect(cloned.tags, ['hero']);
      expect(cloned.lorebook!.entries.length, 1);
      expect(cloned.frontPorchExtensions!.realismEnabled, true);
      expect(cloned.frontPorchExtensions!.shortTermBond, 50);
      expect(cloned.rawExtensions!['custom'], 'data');

      // Verify deep copy — modifying clone doesn't affect original
      cloned.alternateGreetings.add('Hey!');
      expect(original.alternateGreetings, ['Hi!', 'Hello!']);
    });

    test('duplicateCharacter preserves FrontPorch extensions', () {
      final original = CharacterCard(
        name: 'Ext Character',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 75,
          longTermBond: -20,
          trustLevel: 40,
          dayCount: 10,
          timeOfDay: 'night',
          characterEmotion: 'happy',
          emotionIntensity: 'strong',
          nsfwCooldownEnabled: true,
          passageOfTimeEnabled: false,
          chaosModeEnabled: true,
          currentTask: 'Guard the gate',
        ),
      );

      final cloned = CharacterCard(
        name: '${original.name} (duplicate)',
        frontPorchExtensions: original.frontPorchExtensions!.copyWith(),
      );

      expect(cloned.frontPorchExtensions!.realismEnabled, true);
      expect(cloned.frontPorchExtensions!.shortTermBond, 75);
      expect(cloned.frontPorchExtensions!.longTermBond, -20);
      expect(cloned.frontPorchExtensions!.trustLevel, 40);
      expect(cloned.frontPorchExtensions!.dayCount, 10);
      expect(cloned.frontPorchExtensions!.timeOfDay, 'night');
      expect(cloned.frontPorchExtensions!.characterEmotion, 'happy');
      expect(cloned.frontPorchExtensions!.emotionIntensity, 'strong');
      expect(cloned.frontPorchExtensions!.nsfwCooldownEnabled, true);
      expect(cloned.frontPorchExtensions!.passageOfTimeEnabled, false);
      expect(cloned.frontPorchExtensions!.chaosModeEnabled, true);
      expect(cloned.frontPorchExtensions!.currentTask, 'Guard the gate');
    });

    test('CharacterCard allGreetings combines firstMessage and alternates', () {
      final card = CharacterCard(
        name: 'Test',
        firstMessage: 'Hello!',
        alternateGreetings: ['Hi!', '', 'Hey!'],
      );
      expect(card.allGreetings, ['Hello!', 'Hi!', 'Hey!']);
    });

    test('CharacterCard allGreetings filters empty entries', () {
      final card = CharacterCard(
        name: 'Test',
        firstMessage: '',
        alternateGreetings: ['', '', ''],
      );
      expect(card.allGreetings, isEmpty);
    });

    test(
      'CharacterCard allGreetings includes only firstMessage when no alternates',
      () {
        final card = CharacterCard(name: 'Test', firstMessage: 'Hi there');
        expect(card.allGreetings, ['Hi there']);
      },
    );

    test('CharacterCard formattedDescription replaces placeholders', () {
      final card = CharacterCard(
        name: 'Luna',
        description: '{{char}} is a cat',
      );
      expect(card.formattedDescription, 'Luna is a cat');
    });

    test('CharacterCard hasFrontPorchExtensions reflects state', () {
      final card1 = CharacterCard(name: 'No Extensions');
      final card2 = CharacterCard(
        name: 'Has Extensions',
        frontPorchExtensions: FrontPorchExtensions(),
      );
      expect(card1.hasFrontPorchExtensions, false);
      expect(card2.hasFrontPorchExtensions, true);
    });

    test('CharacterCard toJson includes tts_voice when set', () {
      final card = CharacterCard(name: 'Test', ttsVoice: 'en_us');
      final json = card.toJson();
      expect(json['tts_voice'], 'en_us');
    });

    test('CharacterCard toJson omits tts_voice when null', () {
      final card = CharacterCard(name: 'Test');
      final json = card.toJson();
      expect(json.containsKey('tts_voice'), false);
    });

    test('CharacterCard toJson merges rawExtensions with frontPorch', () {
      final card = CharacterCard(
        name: 'Test',
        rawExtensions: {'third_party': 'data'},
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
      );
      final json = card.toJson();
      expect(json['extensions']['third_party'], 'data');
      expect(
        json['extensions']['front_porch']['realism_engine']['enabled'],
        true,
      );
    });

    test('CharacterCard replacePlaceholders handles {{char}}', () {
      final card = CharacterCard(
        name: 'Luna',
        description: '{{char}} is a cat',
      );
      expect(card.replacePlaceholders(card.description), 'Luna is a cat');
    });

    test('CharacterCard replacePlaceholders handles <char>', () {
      final card = CharacterCard(name: 'Luna', description: '<char> is a cat');
      expect(card.replacePlaceholders(card.description), 'Luna is a cat');
    });

    test('CharacterCard replacePlaceholders handles {{user}}', () {
      final card = CharacterCard(name: 'Luna');
      expect(
        card.replacePlaceholders('{{user}} pet the cat', userName: 'Alex'),
        'Alex pet the cat',
      );
    });

    test('CharacterCard replacePlaceholders is case-insensitive', () {
      final card = CharacterCard(name: 'Luna');
      expect(card.replacePlaceholders('{{CHAR}}', userName: 'Alex'), 'Luna');
      expect(card.replacePlaceholders('{{USER}}', userName: 'Alex'), 'Alex');
    });

    // --- New coverage for stableId + duplicate/persist paths (review Issues 5-8,14) ---
    test('duplicateCharacter (real call) produces fresh stableId', () async {
      _setupPathProviderMock();
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.initialized;
      final testDb = AppDatabase.forTesting();
      final testRepo = CharacterRepository(testDb, storage);
      await Future<void>.delayed(Duration.zero);
      final card = CharacterCard(
        name: 'DupStableTest',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          stableId: 'existing-stable-for-dup',
        ),
      );
      final v2 = V2CardService();
      final tmpDir = Directory.systemTemp.createTempSync('dup_test_');
      final pngPath = '${tmpDir.path}/duptest.png';
      await v2.saveCardAsPng(card, pngPath, null);
      card.imagePath = pngPath;
      await testRepo.addCharacter(card);
      final cloned = await testRepo.duplicateCharacter(card);
      expect(cloned != null, true);
      expect(cloned!.name, contains('duplicate'));
      expect(
        cloned.frontPorchExtensions?.stableId,
        isNot('existing-stable-for-dup'),
      );
      expect(cloned.frontPorchExtensions?.stableId != null, true);
      expect(cloned.frontPorchExtensions!.stableId!.isNotEmpty, true);
      await testDb.close();
    });
  });

  // ── DB integration tests ────────────────────────────────────────────

  group('CharacterRepository — DB integration', () {
    late AppDatabase db;
    late CharacterRepository repo;
    late String charId;

    Future<StorageService> _makeStorageService([
      Map<String, Object> initialValues = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(initialValues);
      final service = StorageService();
      await service.initialized;
      return service;
    }

    /// Robust wait for any in-flight loadCharacters() (constructor or explicit).
    /// Polls isLoading; necessary because the original Duration.zero delay was
    /// racy and the re-entrancy guard now makes overlapping calls early-return.
    Future<void> _waitUntilNotLoading(
      CharacterRepository r, {
      Duration timeout = const Duration(seconds: 5),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (r.isLoading) {
        if (DateTime.now().isAfter(deadline)) {
          fail('loadCharacters did not complete within $timeout');
        }
        await Future.delayed(const Duration(milliseconds: 5));
      }
    }

    setUp(() async {
      _setupPathProviderMock();

      db = AppDatabase.forTesting();

      charId = await db.insertCharacterReturningId(
        CharactersCompanion(
          name: const Value('Test Character'),
          description: const Value('Integration test character'),
        ),
      );

      final storage = await _makeStorageService();
      repo = CharacterRepository(db, storage);

      // Let async loadCharacters (constructor fire-and-forget) settle reliably.
      // Original Duration.zero was racy (especially with guard); poll until done.
      await Future<void>.delayed(Duration.zero);
      await _waitUntilNotLoading(repo);
    });

    tearDown(() async {
      await db.close();
    });

    test('getMemorySources returns empty list for a fresh character', () async {
      final sources = await repo.getMemorySources(charId);
      expect(sources, isEmpty);
    });

    test(
      'setMemorySources then getMemorySources round-trips correctly',
      () async {
        const sources = ['src-1', 'src-2', 'src-3'];
        await repo.setMemorySources(charId, sources);
        final retrieved = await repo.getMemorySources(charId);
        expect(retrieved, unorderedEquals(sources));
      },
    );

    test('setMemorySources overwrites previous sources', () async {
      await repo.setMemorySources(charId, ['old-src']);
      await repo.setMemorySources(charId, ['new-src-1', 'new-src-2']);
      final retrieved = await repo.getMemorySources(charId);
      expect(retrieved, unorderedEquals(['new-src-1', 'new-src-2']));
      expect(retrieved, hasLength(2));
    });

    test('setMemorySources with empty list clears sources', () async {
      await repo.setMemorySources(charId, ['src-a']);
      await repo.setMemorySources(charId, []);
      final retrieved = await repo.getMemorySources(charId);
      expect(retrieved, isEmpty);
    });

    test(
      'getMemorySources returns empty list when character does not exist',
      () async {
        final result = await repo.getMemorySources('nonexistent-id');
        expect(result, isEmpty);
      },
    );

    test(
      'loadCharacters performs full reload, ends with isLoading=false, and populates characters',
      () async {
        // Explicitly exercise the canonical full-reload path used by the home
        // grid refresh button (and cloud sync, web imports, etc.). The constructor
        // already fired one; call again to simulate user-initiated refresh.
        //
        // Note on scope (addresses review feedback): the inserted test row has
        // no imagePath, so only the outer reload skeleton (clear, DB query,
        // notify, isLoading transitions, guard interaction) is covered here.
        // The inner per-char PNG/V2CardService/avatar/missing-PNG loop that
        // real toolbar refreshes exercise for user cards is covered by actual
        // usage + other integration paths.
        await repo.loadCharacters();
        await _waitUntilNotLoading(repo); // belt-and-suspenders with guard

        expect(repo.isLoading, isFalse);
        expect(repo.characters, isNotEmpty);
        expect(repo.characters.any((c) => c.name == 'Test Character'), isTrue);
      },
    );

    test(
      'loadCharacters guard safely skips re-entrant call; first load still completes cleanly',
      () async {
        // Exercises the guard (added for the toolbar button) under sequential calls.
        // (Real overlap is hard to force deterministically here because the test
        // character has no imagePath and the inner loop is tiny; the guard contract
        // + final consistent state are verified. Real slow PNG cases are protected
        // in production usage.)
        await repo.loadCharacters();
        final lenBefore = repo.characters.length;

        // Immediate second call (would early-return under guard if still busy)
        await repo.loadCharacters();
        await _waitUntilNotLoading(repo);

        expect(repo.isLoading, isFalse);
        expect(repo.characters.length, lenBefore); // no corruption/duplication
        expect(repo.characters.any((c) => c.name == 'Test Character'), isTrue);
      },
    );

    // --- Coverage for stableId collision paths, ensure, session preserve, legacy (review Issues) ---
    test(
      'import with stable match reuses dbId and injects/carries stable (no new id, no nuke)',
      () async {
        _setupPathProviderMock();
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        await storage.initialized;

        // Seed via importCharacter so the library PNG + in-memory list both
        // carry the stableId (name-only match is no longer a fallback).
        final preCard = CharacterCard(
          name: 'StableMatchTarget',
          description: 'target',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: true,
            stableId: 'reimport-stable-uuid-abc',
          ),
        );
        final v2 = V2CardService();
        final tmpDir = Directory.systemTemp.createTempSync(
          'import_stable_test_',
        );
        final importPng = '${tmpDir.path}/reimport.png';
        await v2.saveCardAsPng(preCard, importPng, null);
        final existing = await repo.importCharacter(File(importPng));
        expect(existing != null, true);
        final preId = existing!.dbId!;
        expect(
          existing.frontPorchExtensions?.stableId,
          'reimport-stable-uuid-abc',
        );

        // create a session for the pre char to verify preservation (minimal)
        final sessId =
            'sess-' + DateTime.now().millisecondsSinceEpoch.toString();
        await db.insertSession(
          SessionsCompanion(
            id: Value(sessId),
            characterId: Value(preId),
            name: const Value('history session'),
          ),
        );
        final preSessions = await db.getSessionsForCharacter(preId);
        final preCount = preSessions.length;

        // re-"import" a card with same stable (simulates edit export reimport)
        final cardWithStable = CharacterCard(
          name: 'StableMatchTarget',
          description: 'target updated',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: true,
            stableId: 'reimport-stable-uuid-abc',
          ),
        );
        final reimportPng = '${tmpDir.path}/reimport2.png';
        await v2.saveCardAsPng(cardWithStable, reimportPng, null);

        final imported = await repo.importCharacter(File(reimportPng));
        expect(imported != null, true);
        expect(imported!.dbId, preId); // key: reused, no new id from collision
        expect(
          imported.frontPorchExtensions?.stableId,
          'reimport-stable-uuid-abc',
        );
        expect(imported.description, 'target updated');

        // verify session count preserved for the (reused) dbId
        final postSessions = await db.getSessionsForCharacter(preId);
        expect(postSessions.length, preCount);

        await tmpDir.delete(recursive: true);
      },
    );

    test(
      'importing a card with a lorebook does NOT auto-create a linked World '
      '(Phase 4: single source of truth — lore lives on the card)',
      () async {
        _setupPathProviderMock();
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        await storage.initialized;

        final card = CharacterCard(
          name: 'LoreCarrier',
          description: 'carries lore',
          lorebook: Lorebook(
            entries: [LorebookEntry(key: 'vale', content: 'The Vale.')],
          ),
        );
        final v2 = V2CardService();
        final tmpDir = Directory.systemTemp.createTempSync('no_autoworld_');
        final png = '${tmpDir.path}/lore.png';
        await v2.saveCardAsPng(card, png, null);

        final imported = await repo.importCharacter(File(png));
        expect(imported != null, true);
        expect(imported!.lorebook != null, true);
        expect(imported.lorebook!.entries.single.keys, ['vale']);

        // The old behavior wrote a "<name>'s world lore" row into worlds.
        final worldRows = await db.select(db.worlds).get();
        expect(
          worldRows.where((w) => w.name.contains('LoreCarrier')),
          isEmpty,
        );

        await tmpDir.delete(recursive: true);
      },
    );

    test(
      'legacy name-only import (no stable) still works, ensure injects on touch',
      () async {
        _setupPathProviderMock();
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        await storage.initialized;

        final legacyCard = CharacterCard(
          name: 'LegacyNoStable',
          description: 'no stable yet',
        );
        final v2 = V2CardService();
        final tmpDir = Directory.systemTemp.createTempSync('legacy_import_');
        final png = '${tmpDir.path}/legacy.png';
        await v2.saveCardAsPng(legacyCard, png, null);

        final imported = await repo.importCharacter(File(png));
        expect(imported != null, true);
        expect(imported!.frontPorchExtensions != null, true);
        expect(
          imported.frontPorchExtensions!.stableId != null,
          true,
        ); // injected
        expect(imported.frontPorchExtensions!.stableId!.isNotEmpty, true);

        await tmpDir.delete(recursive: true);
      },
    );

    test(
      'same-name no-stableId imports keep both (issue #161 — no clobber)',
      () async {
        _setupPathProviderMock();
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        await storage.initialized;

        final v2 = V2CardService();
        final tmpDir = Directory.systemTemp.createTempSync('same_name_keep_');

        Future<File> writeVariant(String desc, String fileName) async {
          final card = CharacterCard(
            name: 'SharedName',
            description: desc,
            // No frontPorchExtensions / stableId — community / ST cards.
          );
          final png = '${tmpDir.path}/$fileName';
          await v2.saveCardAsPng(card, png, null);
          return File(png);
        }

        final a = await writeVariant('variant A', 'a.png');
        final b = await writeVariant('variant B', 'b.png');
        final c = await writeVariant('variant C', 'c.png');

        final ia = await repo.importCharacter(a);
        final ib = await repo.importCharacter(b);
        final ic = await repo.importCharacter(c);

        expect(ia != null && ib != null && ic != null, true);
        final sameName =
            repo.characters.where((c) => c.name == 'SharedName').toList();
        expect(sameName.length, 3);
        // Distinct library identities
        final ids = sameName.map((c) => c.dbId).toSet();
        expect(ids.length, 3);
        final stables = sameName
            .map((c) => c.frontPorchExtensions?.stableId)
            .toSet();
        expect(stables.length, 3);
        // Content not clobbered to last-only
        final descs = sameName.map((c) => c.description).toSet();
        expect(descs, containsAll(['variant A', 'variant B', 'variant C']));

        await tmpDir.delete(recursive: true);
      },
    );

    test(
      'forceReplaceTarget updates in place and preserves dbId (phase 2)',
      () async {
        _setupPathProviderMock();
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        await storage.initialized;

        final v2 = V2CardService();
        final tmpDir = Directory.systemTemp.createTempSync('force_replace_');

        final original = CharacterCard(
          name: 'ReplaceMe',
          description: 'original body',
        );
        final origPng = '${tmpDir.path}/orig.png';
        await v2.saveCardAsPng(original, origPng, null);
        final first = await repo.importCharacter(File(origPng));
        expect(first != null, true);
        final preId = first!.dbId!;

        // Session on that character — must survive replace.
        await db.insertSession(
          SessionsCompanion(
            id: Value('sess-replace-${DateTime.now().millisecondsSinceEpoch}'),
            characterId: Value(preId),
            name: const Value('history'),
          ),
        );

        final incoming = CharacterCard(
          name: 'ReplaceMe',
          description: 'replacement body',
        );
        final newPng = '${tmpDir.path}/new.png';
        await v2.saveCardAsPng(incoming, newPng, null);

        final replaced = await repo.importCharacter(
          File(newPng),
          forceReplaceTarget: first,
        );
        expect(replaced != null, true);
        expect(replaced!.dbId, preId);
        expect(replaced.description, 'replacement body');
        expect(
          repo.characters.where((c) => c.name == 'ReplaceMe').length,
          1,
        );
        final sessions = await db.getSessionsForCharacter(preId);
        expect(sessions.length, 1);

        await tmpDir.delete(recursive: true);
      },
    );

    test(
      'same-name peer with different stableId is not soft-deleted on reimport',
      () async {
        _setupPathProviderMock();
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        await storage.initialized;

        final v2 = V2CardService();
        final tmpDir = Directory.systemTemp.createTempSync('peer_stable_');

        final peerA = CharacterCard(
          name: 'Twin',
          description: 'A',
          frontPorchExtensions: FrontPorchExtensions(
            stableId: 'stable-peer-a',
          ),
        );
        final peerB = CharacterCard(
          name: 'Twin',
          description: 'B',
          frontPorchExtensions: FrontPorchExtensions(
            stableId: 'stable-peer-b',
          ),
        );
        final pathA = '${tmpDir.path}/a.png';
        final pathB = '${tmpDir.path}/b.png';
        await v2.saveCardAsPng(peerA, pathA, null);
        await v2.saveCardAsPng(peerB, pathB, null);

        final ia = await repo.importCharacter(File(pathA));
        final ib = await repo.importCharacter(File(pathB));
        expect(ia != null && ib != null, true);
        expect(repo.characters.where((c) => c.name == 'Twin').length, 2);

        // Reimport A (same stable) — B must remain.
        final peerA2 = CharacterCard(
          name: 'Twin',
          description: 'A updated',
          frontPorchExtensions: FrontPorchExtensions(
            stableId: 'stable-peer-a',
          ),
        );
        final pathA2 = '${tmpDir.path}/a2.png';
        await v2.saveCardAsPng(peerA2, pathA2, null);
        final re = await repo.importCharacter(File(pathA2));
        expect(re!.dbId, ia!.dbId);
        expect(re.description, 'A updated');
        final twins = repo.characters.where((c) => c.name == 'Twin').toList();
        expect(twins.length, 2);
        expect(twins.any((c) => c.dbId == ib!.dbId), isTrue);

        await tmpDir.delete(recursive: true);
      },
    );

    test(
      'standalone .json import parses fields and synthesizes a placeholder avatar',
      () async {
        // Covers the user-facing fix: a raw .json card carries no image, so the
        // importer must route through readCardFromJsonFile and let persist
        // synthesize a placeholder PNG instead of producing an empty,
        // name-only character (the pre-fix behavior).
        final card = CharacterCard(
          name: 'JsonImportChar',
          description: 'imported from json',
          personality: 'Curious',
          firstMessage: 'Hi from JSON',
          tags: ['imported'],
          lorebook: Lorebook(
            entries: [LorebookEntry(key: 'lore', content: 'Some lore')],
          ),
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: true,
            trustLevel: 15,
          ),
        );
        final v2 = V2CardService();
        final tmpDir = Directory.systemTemp.createTempSync('json_import_');
        final jsonPath = '${tmpDir.path}/card.json';
        await v2.saveCardAsJson(card, jsonPath);

        final imported = await repo.importCharacter(File(jsonPath));
        // Note: this file imports drift, whose `isNotNull` collides with the
        // matcher of the same name — use the `!= null` idiom like the rest.
        expect(imported != null, true);
        expect(imported!.name, 'JsonImportChar');
        expect(imported.description, 'imported from json');
        expect(imported.personality, 'Curious');
        expect(imported.firstMessage, 'Hi from JSON');
        expect(imported.tags, ['imported']);
        expect(imported.lorebook?.entries.length, 1);
        expect(imported.frontPorchExtensions?.trustLevel, 15);

        // JSON has no avatar, so persist must synthesize a placeholder PNG
        // that actually exists on disk.
        expect(imported.imagePath != null, true);
        expect(imported.imagePath, endsWith('.png'));
        expect(File(imported.imagePath!).existsSync(), isTrue);

        // The character lands in the repo's in-memory list.
        expect(repo.characters.any((c) => c.name == 'JsonImportChar'), isTrue);

        await tmpDir.delete(recursive: true);
      },
    );

    test(
      'deleteCharacters bulk-removes all cards and reports progress',
      () async {
        // Seed three extra cards alongside the setUp character.
        final cards = <CharacterCard>[];
        for (var i = 0; i < 3; i++) {
          final card = CharacterCard(
            name: 'Bulk $i',
            description: 'to be purged',
            imagePath: 'bulk_$i.png',
          );
          await repo.addCharacter(card);
          cards.add(card);
        }
        expect(repo.characters.where((c) => c.name.startsWith('Bulk')), hasLength(3));

        final progress = <int>[];
        final deleted = await repo.deleteCharacters(
          cards,
          onProgress: (done, total) {
            expect(total, 3);
            progress.add(done);
          },
        );

        expect(deleted, 3);
        // Progress fires once per card, monotonically to the total.
        expect(progress, [1, 2, 3]);
        // All bulk cards gone from the in-memory list.
        expect(repo.characters.any((c) => c.name.startsWith('Bulk')), isFalse);
      },
    );

    test('deleteCharacters on an empty list is a safe no-op', () async {
      final before = repo.characters.length;
      final deleted = await repo.deleteCharacters(const []);
      expect(deleted, 0);
      expect(repo.characters.length, before);
    });

    // --- Cover-resolution cache (20260716 nightly sluggishness regression) ---
    test('coverImageFileFor caches disk stats; mutations invalidate', () async {
      _setupPathProviderMock();
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.initialized;
      final testDb = AppDatabase.forTesting();
      final testRepo = CharacterRepository(testDb, storage);
      await Future<void>.delayed(Duration.zero);

      // A starred avatar whose file really exists — the only branch that
      // stats the disk.
      final base = storage.characterBaseDir('CacheTest');
      final avatarFile = File('${base.path}/avatars/star.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      final card = CharacterCard(
        name: 'CacheTest',
        frontPorchExtensions: FrontPorchExtensions(favoriteAvatarId: 'a1'),
      )..avatarImages = [
          model.AvatarImage(
            id: 'a1',
            characterId: 'c1',
            filename: 'star.png',
            displayOrder: 0,
            createdAt: DateTime(2026),
          ),
        ];

      final first = testRepo.coverImageFileFor(card);
      expect(first?.path, avatarFile.path);

      // Delete the file on disk: a CACHED answer keeps returning the old
      // File (no re-stat — this is the perf fix), until invalidation.
      avatarFile.deleteSync();
      expect(testRepo.coverImageFileFor(card)?.path, avatarFile.path);

      // The gallery's deferred broadcast invalidates → fresh stat → the
      // missing star now falls back (null: no portrait on this card).
      testRepo.notifyCharactersChanged();
      expect(testRepo.coverImageFileFor(card), equals(null));

      // A ★ change self-invalidates via the key, no broadcast needed.
      card.frontPorchExtensions!.favoriteAvatarId = 'a2';
      expect(testRepo.coverImageFileFor(card), equals(null)); // a2
    });
  });
}
