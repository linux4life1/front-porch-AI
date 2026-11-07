// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The per-chat Pockets & Wardrobe switch (docs/design/pockets-wardrobe-chat-
// toggle.md). The card flag stopped being runtime law: it SEEDS a chat's own
// switch, and from then on the stored value is what the gate answers.
//
// The promises this pins, one test each:
//
//   * OFF means SILENT — no pockets model call leaves the house. The eval
//     prompt is watched at the LLM boundary, not inferred from a quiet kit.
//   * OFF means HIDDEN, never erased — the record survives byte-identical
//     and resumes on Yes. (The write-hold siblings live in
//     pockets_per_char_off_write_test.dart.)
//   * ON seeds the card's starting kit ONCE, and only a chat that holds no
//     record at all. Never a retroactive scan.
//   * The stored switch is LAW across reopen: the v64 column wins over the
//     card default; a NULL column (a pre-v64 chat) derives from the card
//     ONCE and then the derived value is law too (maintainer ruling D1).
//   * GROUPS are per member: the maintainer's worked example — group ON +
//     Ben's card OFF ⇒ Mara and Shawn start tracked, Ben starts untracked;
//     flipping one member mid-chat silences only their track.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show Pockets, PocketItem;
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_pw_chat_').path;
        }
        return null;
      });
}

/// Answers the reply prompts and RECORDS every prompt it saw, so a test can
/// prove the pockets eval was not asked — the zero-model-call promise needs
/// the watch at the LLM boundary, not a quiet kit.
class _ScriptedLlm extends LLMService {
  String inventoryJson = '{"inventory_ops": []}';
  final List<String> prompts = [];

  bool get askedPockets =>
      prompts.any((p) => p.contains('You are keeping track of what'));

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*They nod on the porch.*';
      return;
    }
    prompts.add(params.prompt);
    if (params.prompt.contains('You are keeping track of what')) {
      yield inventoryJson;
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ScriptedLlm llm;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'pockets_enabled': true,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = llm;
    await storage.initialized;
    await storage.realismSettings.setPocketsEnabled(true);
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> drainUntil(bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> drainTurn() =>
      drainUntil(() => !chat.isGenerating && !chat.isSettlingTurn);

  CharacterCard bea({
    bool pocketsDefault = true,
    List<String> carrying = const ['house keys'],
  }) => CharacterCard(
    name: 'Bea',
    firstMessage: 'Hi.',
    frontPorchExtensions: FrontPorchExtensions(
      pocketsEnabled: pocketsDefault,
      inventory: Pockets.cardJsonFrom(worn: const [], carrying: carrying),
    ),
  )..dbId = 'char-toggle-bea';

  Future<int?> columnOf(String sessionId) async {
    final row = await db
        .customSelect(
          'SELECT pockets_enabled FROM sessions WHERE id = ?',
          variables: [Variable(sessionId)],
        )
        .getSingle();
    return row.readNullable<int>('pockets_enabled');
  }

  group('1:1 — off is silent and hides without erasing', () {
    test(
      'off chat: no pockets model call, and the kit resumes identical',
      () async {
        final c = bea();
        await chat.setActiveCharacter(c);
        final id = chat.characterIdFor(c);
        expect(chat.pocketsEnabledFor(id), isTrue);

        await chat.sendMessage('Just sitting.');
        await drainTurn();
        final before = chat.pocketsFor(id);
        expect(before, isNotNull, reason: 'on chat runs the pass');

        await chat.setPocketsEnabled(false);
        expect(chat.pocketsEnabledFor(id), isFalse);
        expect(chat.pocketsFor(id), isNull, reason: 'hide');

        llm.prompts.clear();
        llm.inventoryJson =
            '{"inventory_ops": [{"op": "add", "item": "gift box"}]}';
        await chat.sendMessage('Here, I brought something.');
        await drainTurn();

        expect(llm.askedPockets, isFalse, reason: 'ZERO pockets model call');

        await chat.setPocketsEnabled(true);
        final after = chat.pocketsFor(id);
        expect(
          jsonEncode(after?.toJson()),
          jsonEncode(before?.toJson()),
          reason: 'HIDES≠erase — byte-identical resume, no catch-up, no seed',
        );
      },
    );
  });

  group('1:1 — enabling seeds the card kit once, empty-record only', () {
    test(
      'card-default-off chat seeds on enable; a held record never re-seeds',
      () async {
        final c = bea(pocketsDefault: false);
        await chat.setActiveCharacter(c);
        final id = chat.characterIdFor(c);
        expect(chat.pocketsEnabledFor(id), isFalse);
        expect(chat.pocketsFor(id), isNull);

        await chat.setPocketsEnabled(true);
        expect(
          chat.pocketsFor(id)?.carrying.map((i) => i.name),
          contains('house keys'),
          reason:
              'empty chat gets the card kit once, like Needs seeds the vector',
        );

        // Change the record, freeze it, thaw it: the CHANGED record resumes —
        // the card kit must not clap back over it.
        chat.setPocketsFor(
          id,
          Pockets(carrying: [const PocketItem('rail pass')]),
        );
        await chat.setPocketsEnabled(false);
        await chat.setPocketsEnabled(true);
        expect(
          chat.pocketsFor(id)?.carrying.map((i) => i.name),
          contains('rail pass'),
        );
        expect(
          chat.pocketsFor(id)?.carrying.map((i) => i.name) ?? const [],
          isNot(contains('house keys')),
          reason: 'resume, not re-seed',
        );
      },
    );
  });

  group('1:1 — the stored switch is law across reopen (v64 column)', () {
    test(
      'an explicit OFF survives reopen against a card default of ON',
      () async {
        final c = bea();
        await chat.setActiveCharacter(c);
        final id = chat.characterIdFor(c);
        await chat.sendMessage('Hello.');
        await drainTurn();
        final sessionId = chat.currentSessionId;
        expect(sessionId, isNotNull);
        expect(await columnOf(sessionId!), 1, reason: 'new chat persists ON');

        await chat.setPocketsEnabled(false);
        expect(await columnOf(sessionId), 0);

        // Reopen for real: the same-character call early-returns on a live
        // session, so detach first — this must go through session restore,
        // where the column is read and the card's ON must lose.
        await chat.setActiveCharacter(null);
        await chat.setActiveCharacter(bea());
        expect(chat.pocketsEnabledFor(id), isFalse);
      },
    );

    test(
      'a NULL column derives from the card ONCE, then the value is law',
      () async {
        final c = bea();
        await chat.setActiveCharacter(c);
        final id = chat.characterIdFor(c);
        await chat.sendMessage('Hello.');
        await drainTurn();
        final sessionId = chat.currentSessionId!;

        // Simulate the pre-v64 row: wipe the column back to NULL.
        await db.customStatement(
          'UPDATE sessions SET pockets_enabled = NULL WHERE id = ?',
          [sessionId],
        );

        // Reopen derives it once from the card default (ON here) — detach
        // first so this really is a session restore, not the in-memory chat.
        await chat.setActiveCharacter(null);
        await chat.setActiveCharacter(bea());
        expect(chat.pocketsEnabledFor(id), isTrue);

        // Flip OFF in the chat and save; reopen — the derived-then-stored OFF
        // survives: a card that says ON must not re-arm it forever.
        await chat.setPocketsEnabled(false);
        expect(await columnOf(sessionId), 0);
        await chat.setActiveCharacter(null);
        await chat.setActiveCharacter(bea());
        expect(chat.pocketsEnabledFor(id), isFalse);
      },
    );
  });

  group('groups — per member: seed by default, silence only the flipped one', () {
    Future<void> insertMember({
      required String groupId,
      required String id,
      required String name,
      required bool pocketsDefault,
    }) {
      return db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: groupId,
          name: name,
          frontPorchExtensions: Value(
            jsonEncode(
              FrontPorchExtensions(
                pocketsEnabled: pocketsDefault,
                inventory: Pockets.cardJsonFrom(
                  worn: const [],
                  carrying: const ['house keys'],
                ),
              ).toJson(),
            ),
          ),
        ),
      );
    }

    Future<void> openGroup(String groupId) => chat.setActiveGroup(
      GroupChat(id: groupId, name: 'The Porch'),
      groupRepo: GroupChatRepository(storage, db),
    );

    CharacterCard member(String name) =>
        chat.groupCharacters.firstWhere((c) => c.name == name);
    String idOf(String name) => chat.characterIdFor(member(name));

    test(
      'maintainer example: group ON + Ben card OFF ⇒ Ben starts untracked',
      () async {
        await db.insertGroup(
          GroupsCompanion.insert(id: 'grp-seed', name: 'The Porch'),
        );
        await insertMember(
          groupId: 'grp-seed',
          id: 'm-mara',
          name: 'Mara',
          pocketsDefault: true,
        );
        await insertMember(
          groupId: 'grp-seed',
          id: 'm-ben',
          name: 'Ben',
          pocketsDefault: false,
        );
        await insertMember(
          groupId: 'grp-seed',
          id: 'm-shawn',
          name: 'Shawn',
          pocketsDefault: true,
        );

        await openGroup('grp-seed');

        expect(chat.pocketsEnabledFor(idOf('Mara')), isTrue);
        expect(chat.pocketsEnabledFor(idOf('Shawn')), isTrue);
        expect(
          chat.pocketsEnabledFor(idOf('Ben')),
          isFalse,
          reason: 'group ON AND card OFF ⇒ off (the worked example)',
        );

        // Flipping Ben on mid-chat works and seeds his card kit once.
        await chat.setMemberPocketsEnabled(idOf('Ben'), true);
        expect(chat.pocketsEnabledFor(idOf('Ben')), isTrue);
        expect(
          chat.pocketsFor(idOf('Ben'))?.carrying.map((i) => i.name),
          contains('house keys'),
        );
      },
    );

    test(
      'flipping one member off silences only their track, and the flip survives reopen',
      () async {
        await db.insertGroup(
          GroupsCompanion.insert(id: 'grp-flip', name: 'The Porch'),
        );
        await insertMember(
          groupId: 'grp-flip',
          id: 'f-ana',
          name: 'Ana',
          pocketsDefault: true,
        );
        await insertMember(
          groupId: 'grp-flip',
          id: 'f-bo',
          name: 'Bo',
          pocketsDefault: true,
        );

        await openGroup('grp-flip');
        await chat.sendMessage('Morning all.');
        await drainTurn();

        await chat.setMemberPocketsEnabled(idOf('Ana'), false);
        expect(chat.pocketsEnabledFor(idOf('Ana')), isFalse);
        expect(chat.pocketsEnabledFor(idOf('Bo')), isTrue, reason: 'only Ana');
        expect(chat.pocketsFor(idOf('Ana')), isNull);
        expect(chat.pocketsFor(idOf('Bo')), isNotNull);

        // Re-open for real (detach the group first): the bag carries the flip
        // — the card default (ON) must lose.
        await chat.setActiveCharacter(null);
        await openGroup('grp-flip');
        expect(
          chat.pocketsEnabledFor(idOf('Ana')),
          isFalse,
          reason: 'mid-chat flips survive reopen',
        );
        expect(chat.pocketsEnabledFor(idOf('Bo')), isTrue);
      },
    );
  });

  group('.fpchat — the switch rides the package', () {
    test(
      'export captures the switch; import restores it against an ON card',
      () async {
        final c = bea();
        await chat.setActiveCharacter(c);
        final id = chat.characterIdFor(c);
        await chat.sendMessage('Hello.');
        await drainTurn();
        await chat.setPocketsEnabled(false);

        final bytes = await chat.exportToFpchat();
        expect(bytes, isNotNull);

        // Turn it back on (seeds nothing: record exists), then import: the
        // package's OFF must land as law despite the card saying ON.
        await chat.setPocketsEnabled(true);
        final outcome = await chat.importChatPackage(bytes!);
        expect(outcome.fullRestore, isTrue);
        expect(chat.pocketsEnabledFor(id), isFalse);

        await chat.setPocketsEnabled(true);
        expect(
          chat.pocketsFor(id)?.carrying.map((i) => i.name),
          contains('house keys'),
          reason: 'the kit captured at export comes back',
        );
      },
    );
  });
}
