// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A boon or bogey added in the editor mid-chat lands at once in every chat
// with that character (maintainer ruling 2026-11-24; GrowthKitAdditions).
// Before it, a chat whose kit had seeded never saw the new entry, and a chat
// without one only got an offer in the Growth panel — the sidebar showed
// nothing either way. Driven through the real ChatService and the same
// `spreadNewKitEntries` call both editors make, plus the web save route's
// facade.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/growth_boons_bogies.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/utils/character_id.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/widgets/trait_kit_editor.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_page.dart'
    show GroupMemberMode;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../integration_test/support/fake_backend.dart';
import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _RepoWithCover extends FakeCharacterRepository {
  @override
  File? coverImageFileFor(CharacterCard card) => null;
}

void main() {
  late Directory root;
  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late ChatService chat;
  late FakeBackendServer backend;

  setUp(() async {
    HttpOverrides.global = null;
    root = Directory.systemTemp.createTempSync('fpai_kit_add_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => root.path,
        );
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    db = AppDatabase.forTesting();
    backend = await FakeBackendServer.start(replyPieces: ['Evening.']);
    storage = StorageService();
    await storage.initialized;
    repo = CharacterRepository(db, storage);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    await storage.memorySettings.setCharacterEvolutionEnabled(true);
    await storage.memorySettings.setBoonsBogiesEnabled(true);
  });

  tearDown(() async {
    chat.dispose();
    await backend.close();
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> settle() async {
    for (
      var i = 0;
      i < 400 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// A library character with a portrait (so its rings key by the image
  /// basename, as in the app), imported the way a dropped .png is.
  Future<CharacterCard> libraryCard(List<TraitKitEntry> kit) async {
    final card = CharacterCard(
      name: 'Mira Vale',
      description: 'Keeps the porch bar.',
      firstMessage: 'Evening.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        traitKit: kit,
      ),
    );
    final png = '${root.path}/incoming_mira.png';
    await V2CardService().saveCardAsPng(card, png, null);
    final imported = await repo.importCharacter(File(png));
    await repo.loadCharacters();
    return repo.characters.singleWhere((c) => c.dbId == imported!.dbId);
  }

  List<String> openRings(CharacterCard c) => [
    for (final r in chat.growthRingsForOwner(chat.characterIdFor(c)))
      if (!r.retired) r.content,
  ];

  Future<List<String>> storedRings(String sessionId, String ownerId) async => [
    for (final r in await db.getGrowthRings(sessionId, ownerId)) r.content,
  ];

  /// What the editor does: change the kit on the very card, save, spread.
  Future<void> editorAdds(CharacterCard c, TraitKitEntry entry) async {
    final before = [...c.frontPorchExtensions!.traitKit];
    c.frontPorchExtensions!.traitKit = [...before, entry];
    await repo.updateCharacter(c);
    await spreadNewKitEntries(chat, c, before);
  }

  final bogey = TraitKitEntry(
    kind: 'bogey',
    text: 'bad temper when cornered',
    tier: 'developing',
    pinned: true,
  );

  test('a seeded chat takes the new bogey at its tier and pin, and so does '
      'a closed chat; one with Boons & Bogies off takes nothing', () async {
    final mira = await libraryCard([
      TraitKitEntry(kind: 'boon', text: 'steady hands', tier: 'developing'),
    ]);
    await chat.setActiveCharacter(mira);
    await chat.sendMessage('Hello.');
    await settle();
    expect(openRings(mira), ['steady hands'], reason: 'the kit seeded');
    final owner = mira.stableGroupId;
    await db.insertSession(
      SessionsCompanion.insert(id: 'closed', characterId: Value(mira.dbId)),
    );
    await db.insertSession(
      SessionsCompanion.insert(
        id: 'bb-off',
        characterId: Value(mira.dbId),
        bbEnabled: const Value(false),
      ),
    );

    await editorAdds(mira, bogey);

    expect(openRings(mira), contains('bad temper when cornered'));
    final ring = chat
        .growthRingsForOwner(chat.characterIdFor(mira))
        .singleWhere((r) => r.content == 'bad temper when cornered');
    expect(ring.category, 'bogey');
    expect(ring.pinned, isTrue, reason: 'the pin the author set');
    expect(BoonsBogies.isKitSeeded(ring), isTrue);
    expect(await storedRings('closed', owner), ['bad temper when cornered']);
    expect(await storedRings('bb-off', owner), isEmpty);
  });

  test('a chat that grew without a kit takes the new boon, and the Growth '
      'panel no longer offers what is already there', () async {
    final mira = await libraryCard(const []);
    await chat.setActiveCharacter(mira);
    await chat.sendMessage('I pour us both a glass of lemonade.');
    await settle();
    await chat.forceGrowthPass();
    await settle();
    expect(openRings(mira), isNotEmpty, reason: 'the chat is growing');

    await editorAdds(
      mira,
      TraitKitEntry(kind: 'boon', text: 'steady hands', tier: 'developing'),
    );

    expect(openRings(mira), contains('steady hands'));
    await chat.forceGrowthPass();
    await settle();
    expect(chat.growthKitOffer, isNull);
    expect(
      openRings(mira).where((t) => t == 'steady hands'),
      hasLength(1),
      reason: 'a second save or pass never adds it twice',
    );
  });

  group('the chat catches up on refresh (when the save-time step missed)', () {
    // Reported live: the save ran on code that could not reach the chats
    // (a hot reload), so the boon was on the card and never in the chat,
    // and no later save counted it as new. A refresh must bring it in.
    Future<void> refresh() => chat.realism.growthDesk.refreshCache();

    Future<CharacterCard> seededChat() async {
      final mira = await libraryCard([
        TraitKitEntry(kind: 'boon', text: 'steady hands', tier: 'developing'),
      ]);
      await chat.setActiveCharacter(mira);
      await chat.sendMessage('Hello.');
      await settle();
      expect(openRings(mira), ['steady hands']);
      return mira;
    }

    test('an entry on the card the chat never took lands on the next '
        'refresh; one the user removes stays removed', () async {
      final mira = await seededChat();
      // The card changes with no spread (the missed save).
      mira.frontPorchExtensions!.traitKit = [
        ...mira.frontPorchExtensions!.traitKit,
        TraitKitEntry(
          kind: 'boon',
          text: 'Able to use elven magical spells',
          tier: 'developing',
        ),
      ];
      await refresh();
      expect(openRings(mira), contains('Able to use elven magical spells'));

      final ring = chat
          .growthRingsForOwner(chat.characterIdFor(mira))
          .singleWhere((r) => r.content == 'Able to use elven magical spells');
      await chat.deleteGrowthRing(ring.id);
      await refresh();
      await refresh();
      expect(
        openRings(mira),
        isNot(contains('Able to use elven magical spells')),
        reason: 'removed from this chat: the catch-up remembers it took it',
      );
    });

    test('a chat from before the record counts its own rings as seen; one '
        'that declined the kit stays without it', () async {
      final mira = await seededChat();
      final session = chat.currentSessionId!;
      // As an older app left it: settled, no record of what it took.
      await db.customStatement(
        "UPDATE growth_state SET kit_seen = NULL WHERE session_id = '$session'",
      );
      mira.frontPorchExtensions!.traitKit = [
        ...mira.frontPorchExtensions!.traitKit,
        bogey,
      ];
      await refresh();
      expect(openRings(mira), contains('bad temper when cornered'));
      expect(
        openRings(mira).where((t) => t == 'steady hands'),
        hasLength(1),
        reason: 'what it already had is not added twice',
      );

      // A declined chat: the old kit stays out.
      await db.customStatement(
        "UPDATE growth_state SET kit_seen = NULL, kit_seed_state = 2 "
        "WHERE session_id = '$session'",
      );
      for (final r in chat.growthRingsForOwner(chat.characterIdFor(mira))) {
        await chat.deleteGrowthRing(r.id);
      }
      await refresh();
      expect(openRings(mira), isEmpty);
    });

    test('Boons & Bogies off for the chat: nothing lands', () async {
      final mira = await seededChat();
      await db.customStatement(
        "UPDATE sessions SET bb_enabled = 0 "
        "WHERE id = '${chat.currentSessionId}'",
      );
      chat.realism.controls.memberSwitches.chatBbSwitch = false;
      mira.frontPorchExtensions!.traitKit = [
        ...mira.frontPorchExtensions!.traitKit,
        bogey,
      ];
      await refresh();
      expect(openRings(mira), ['steady hands']);
    });
  });

  test('retyping an existing entry adds nothing', () async {
    final mira = await libraryCard([
      TraitKitEntry(kind: 'boon', text: 'steady hands', tier: 'developing'),
    ]);
    await chat.setActiveCharacter(mira);
    await chat.sendMessage('Hello.');
    await settle();
    final before = [...mira.frontPorchExtensions!.traitKit];
    mira.frontPorchExtensions!.traitKit = [
      TraitKitEntry(
        kind: 'boon',
        text: 'steady hands, always',
        tier: 'developing',
      ),
    ];
    await repo.updateCharacter(mira);
    await spreadNewKitEntries(chat, mira, before);
    expect(openRings(mira), ['steady hands']);
  });

  test('a group member copy reaches its group chats, keyed by the member, '
      'and skips a chat where that member has Boons & Bogies off', () async {
    await db
        .into(db.groupMembers)
        .insert(
          GroupMembersCompanion.insert(id: 'm1', groupId: 'g1', name: 'Wren'),
        );
    await db.insertSession(
      SessionsCompanion.insert(id: 'g-on', groupId: const Value('g1')),
    );
    await db.insertSession(
      SessionsCompanion.insert(
        id: 'g-off',
        groupId: const Value('g1'),
        groupRealismState: Value(
          jsonEncode({
            'perChar': {
              'm1': {'bb_switch': false},
            },
          }),
        ),
      ),
    );
    final wren = CharacterCard(
      name: 'Wren',
      description: 'A guest.',
      frontPorchExtensions: FrontPorchExtensions(traitKit: []),
    )..dbId = 'm1';
    final before = <TraitKitEntry>[];
    wren.frontPorchExtensions!.traitKit = [bogey];
    await spreadNewKitEntries(chat, wren, before, groupMemberId: 'm1');
    expect(await storedRings('g-on', 'm1'), ['bad temper when cornered']);
    expect(await storedRings('g-off', 'm1'), isEmpty);
  });

  testWidgets('the desktop editor reads the kit before it saves, so a trait '
      'added there is sent on to the chats', (tester) async {
    // The editor's writer replaces the kit on the very card a chat holds;
    // read too late, "what was added" is always empty and nothing is sent.
    // The fake cannot reach the realism door, so the send is seen in the
    // log line the helper writes when the door refuses it.
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late CharacterCard flora;
    final fakeRepo = _RepoWithCover();
    final fakeChat = FakeChatService();
    final fakeStorage = FakeStorageService();
    final fakeWorlds = FakeWorldRepository();
    addTearDown(fakeRepo.dispose);
    addTearDown(fakeChat.dispose);
    addTearDown(fakeStorage.dispose);
    addTearDown(fakeWorlds.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CharacterRepository>.value(value: fakeRepo),
          ChangeNotifierProvider<ChatService>.value(value: fakeChat),
          ChangeNotifierProvider<StorageService>.value(value: fakeStorage),
          ChangeNotifierProvider<WorldRepository>.value(value: fakeWorlds),
        ],
        child: MaterialApp(
          home: EditCharacterPage(
            character: flora = CharacterCard(
              name: 'Flora',
              frontPorchExtensions: FrontPorchExtensions(
                realismEnabled: true,
                traitKit: [TraitKitEntry(kind: 'boon', text: 'steady hands')],
              ),
            ),
            // A group member's copy: its own row, saved by the override
            // (the golden fakes have no library database to save into).
            onSaveOverride: (_) async {},
            member: GroupMemberMode(
              groupName: 'Porch',
              memberId: 'm1',
              others: const [],
              scene: const GroupSceneTime(),
              values: const GroupMemberValues(),
              saveValues: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add trait'));
    await tester.tap(find.text('Add trait'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .descendant(
            of: find.byType(TraitKitEditor),
            matching: find.byType(TextField),
          )
          .last,
      'bad temper when cornered',
    );
    await tester.ensureVisible(find.text('Save'));
    final logs = <String>[];
    final saved = debugPrint;
    debugPrint = (m, {int? wrapWidth}) => logs.add(m ?? '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    debugPrint = saved; // the binding checks it is back before tear-down
    expect(flora.frontPorchExtensions!.traitKit.map((e) => e.text), [
      'steady hands',
      'bad temper when cornered',
    ], reason: 'the trait was typed into the kit');
    expect(
      logs.where((l) => l.contains('new kit entries not added to chats')),
      isNotEmpty,
      reason:
          'the save sent the new trait on (the fake then refused it): $logs',
    );
  });

  test('the web save route adds it too', () async {
    final mira = await libraryCard([
      TraitKitEntry(kind: 'boon', text: 'steady hands', tier: 'developing'),
    ]);
    await chat.setActiveCharacter(mira);
    await chat.sendMessage('Hello.');
    await settle();
    final facade = CharacterFacade(db, storage, null, chat, repo);
    final ok = await facade.update(mira.dbId!, {
      'traitKit': [
        {'kind': 'boon', 'text': 'steady hands', 'tier': 'developing'},
        {
          'kind': 'bogey',
          'text': 'bad temper when cornered',
          'tier': 'developing',
          'pinned': true,
        },
      ],
    });
    expect(ok, isTrue);
    expect(openRings(mira), contains('bad temper when cornered'));
  });
}
