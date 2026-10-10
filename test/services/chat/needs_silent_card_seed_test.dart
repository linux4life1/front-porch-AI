// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A card that says nothing about Needs follows the Porch Life Needs switch
// (maintainer ruling, 2026-10-10: "Global fills in"). Before it, a plain
// imported card (Chub, SillyTavern, BYAF: no `needs_sim_enabled` key) started
// every chat with Needs off while the global switch and Realism were on,
// because the switch only AND-gated what the card asked for, and a silent
// card was read as an explicit "no". A card's explicit false still wins, and
// the global switch off still stops Needs everywhere.
//
// Real ChatService, real CharacterRepository and importer, in-memory database.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';
import '../../helpers/chat_db_teardown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_silent_needs_').path;
        }
        return null;
      });

  AppDatabase? db;
  StorageService? storage;
  CharacterRepository? repo;
  ChatService? chat;

  Future<void> boot({bool needsGlobal = true}) async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': needsGlobal,
      'passage_of_time_default': true,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    repo = CharacterRepository(db!, storage!);
    chat =
        ChatService(
            KoboldService(storage!),
            UserPersonaService(db!),
            storage!,
            WorldRepository(storage!, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo!);
    await storage!.initialized;
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  CharacterCard card(String name, FrontPorchExtensions? ext) => CharacterCard(
    name: name,
    firstMessage: 'Evening, neighbor.',
    frontPorchExtensions: ext,
  );

  void expectNeedsOn(String why) {
    expect(chat!.needsSimEnabled, isTrue, reason: why);
    expect(chat!.needsActive, isTrue, reason: why);
    expect(
      chat!.needsSimulation.vector,
      isNotEmpty,
      reason: 'the bars are seeded, or the first turn stamps nothing',
    );
  }

  group('opening a character for the first time', () {
    test('a card that says nothing follows the global switch', () async {
      await boot();
      final carmen = card('Carmen', FrontPorchExtensions(realismEnabled: true));
      expect(carmen.frontPorchExtensions!.needsSimChoice, isNull);
      await repo!.addCharacter(carmen);
      await chat!.setActiveCharacter(carmen);
      expectNeedsOn('a silent card took the Porch Life switch (on)');
    });

    test('a card with no Front Porch settings at all follows it too', () async {
      await boot();
      final plain = card('Plain', null);
      await repo!.addCharacter(plain);
      await chat!.setActiveCharacter(plain);
      expect(chat!.realismEnabled, isTrue);
      expectNeedsOn('the plain-card branch seeded Needs from the global');
    });

    test('an explicit false on the card still wins', () async {
      await boot();
      final no = card(
        'Nora',
        FrontPorchExtensions(realismEnabled: true, needsSimEnabled: false),
      );
      await repo!.addCharacter(no);
      await chat!.setActiveCharacter(no);
      expect(chat!.needsSimEnabled, isFalse);
      expect(chat!.needsActive, isFalse);
    });

    test('the global switch off stops a card that asks', () async {
      await boot(needsGlobal: false);
      final yes = card(
        'Yara',
        FrontPorchExtensions(realismEnabled: true, needsSimEnabled: true),
      );
      await repo!.addCharacter(yes);
      await chat!.setActiveCharacter(yes);
      expect(chat!.needsSimEnabled, isFalse);
      expect(chat!.needsActive, isFalse);

      final quiet = card('Quinn', FrontPorchExtensions(realismEnabled: true));
      await repo!.addCharacter(quiet);
      await chat!.setActiveCharacter(quiet);
      expect(chat!.needsActive, isFalse);
    });
  });

  group('reopening a chat saved with Needs off and no bars', () {
    // The chat was started while the Porch Life switch was off, so its row
    // says off with no saved bars: the stale row the hydrate promotion is
    // for. With the switch back on, a card that asks gets Needs on reopen;
    // a silent card must too, and a card that chose off must not.
    Future<CharacterCard> savedOffThenReopen(FrontPorchExtensions ext) async {
      await boot(needsGlobal: false);
      final c = card('Carmen', ext);
      final other = card('Other', FrontPorchExtensions());
      await repo!.addCharacter(c);
      await repo!.addCharacter(other);
      await chat!.setActiveCharacter(c);
      final sid = chat!.currentSessionId;
      expect(sid, isNotNull, reason: 'opening saves the greeting chat');
      final row = await db!.getSessionById(sid!);
      expect(row?.needsSimEnabled, isFalse);
      expect(row?.needsVector ?? '', isEmpty);

      await storage!.realismSettings.setNeedsSimDefault(true);
      await chat!.setActiveCharacter(other);
      await chat!.setActiveCharacter(c);
      expect(chat!.currentSessionId, sid, reason: 'the saved chat reopened');
      return c;
    }

    test('a silent card is promoted to Needs on', () async {
      await savedOffThenReopen(FrontPorchExtensions(realismEnabled: true));
      expectNeedsOn('hydrate treats a silent card as asking when global on');
    });

    test('a card that chose off stays off', () async {
      await savedOffThenReopen(
        FrontPorchExtensions(realismEnabled: true, needsSimEnabled: false),
      );
      expect(chat!.needsSimEnabled, isFalse);
    });
  });

  test('New Chat with a silent card follows the global switch', () async {
    await boot();
    final carmen = card('Carmen', FrontPorchExtensions(realismEnabled: true));
    await repo!.addCharacter(carmen);
    await chat!.setActiveCharacter(carmen);
    await chat!.setNeedsSimEnabled(false);

    await chat!.startNewChat();

    expectNeedsOn('New Chat re-seeds Needs from the silent card + global');
    final row = await db!.getSessionById(chat!.currentSessionId!);
    expect(row?.needsSimEnabled, isTrue);
  });

  test('a transcript imported onto a silent card follows it', () async {
    await boot();
    final carmen = card('Carmen', FrontPorchExtensions(realismEnabled: true));
    await repo!.addCharacter(carmen);
    await chat!.setActiveCharacter(carmen);
    await chat!.setNeedsSimEnabled(false);

    final transcript = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'messages': [
            {'name': 'User', 'is_user': true, 'mes': 'hello'},
            {'name': 'Carmen', 'is_user': false, 'mes': 'evening'},
          ],
        }),
      ),
    );
    await chat!.importChatPackage(transcript);

    expectNeedsOn('the import seed re-read the silent card + global');
  });

  test('a plain card through the real importer stays silent and starts '
      'its chat with Needs on', () async {
    await boot();
    final src = p.join(
      Directory.systemTemp.createTempSync('fpai_plain_png_').path,
      'Plain.png',
    );
    await V2CardService().saveCardAsPng(card('Plain', null), src, null);

    final imported = await repo!.importCharacter(File(src));
    expect(imported, isNotNull);
    expect(imported!.frontPorchExtensions?.needsSimChoice, isNull);

    final onDisk = await V2CardService().readCard(imported.imagePath!);
    expect(
      onDisk!.frontPorchExtensions?.needsSimChoice,
      isNull,
      reason: 'the import wrote an explicit Needs choice the card never had',
    );

    await chat!.setActiveCharacter(imported);
    expectNeedsOn('an imported plain card follows the Porch Life switch');
  });

  test('New Chat in a group honours the global Needs switch', () async {
    await boot();
    final blobs = buildGroupRealismBlobs(
      seeds: {
        'mem-ana': defaultGroupMemberRealismSeed(),
        'mem-bea': defaultGroupMemberRealismSeed(),
      },
      needsEnabled: true,
      timeOfDay: 'morning',
      dayCount: 1,
    );
    await db!.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-needs',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    for (final m in [('mem-ana', 'Ana'), ('mem-bea', 'Bea')]) {
      await db!.insertGroupMember(
        GroupMembersCompanion.insert(
          id: m.$1,
          groupId: 'grp-needs',
          name: m.$2,
          firstMessage: const Value('Evening.'),
        ),
      );
    }
    await chat!.setActiveGroup(
      GroupChat(
        id: 'grp-needs',
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage!, db!),
    );
    expect(chat!.needsSimEnabled, isTrue);

    await storage!.realismSettings.setNeedsSimDefault(false);
    await chat!.startNewChat();

    expect(
      chat!.needsSimEnabled,
      isFalse,
      reason: 'group New Chat seeds like group entry: off with the global off',
    );
  });
}
