// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// HOLD pins: a per-char-off kit HIDES, it is never invented or erased.
//
//   * Transfer-to-off (Bug Hunter): Ana (on) handing Bea (off) an item
//     must not seed or write Bea's session kit. Roster excludes her.
//   * Fork/import wipe (Senior Dev): stamp-less rewind must not null a
//     hidden kit just because the global is on.
//   * Middle-delete invent (Senior Dev): invert must not `pocketsFor ??
//     Pockets()` + setPocketsFor an off member.
//   * .fpchat 1:1 import (Bug Hunter): Phase-0 `_pockets=null` then gated
//     restore must not drop the suitcase kit captured from raw `_pockets`.
//
// Proven red: skip the recipient `pocketsEnabledFor` gate on transfer
// apply, or keep the global-only wipe/invent paths, and these fail.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show Pockets, PocketItem;

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_pw_off_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  String inventoryJson = '{"inventory_ops": []}';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*They nod on the porch.*';
      return;
    }
    final p = params.prompt;
    if (p.contains('You are keeping track of what')) {
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
    await storage.realismSettings.setPocketTransfersEnabled(true);
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  Future<void> drainUntil(bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> insertMember({
    required String groupId,
    required String id,
    required String name,
    required bool pocketsOn,
    List<String> carrying = const ['house keys'],
  }) {
    return db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: id,
        groupId: groupId,
        name: name,
        frontPorchExtensions: Value(
          jsonEncode(
            FrontPorchExtensions(
              pocketsEnabled: pocketsOn,
              inventory: Pockets.cardJsonFrom(
                worn: const [],
                carrying: carrying,
              ),
            ).toJson(),
          ),
        ),
      ),
    );
  }

  Future<void> openGroup(String groupId) async {
    await chat.setActiveGroup(
      GroupChat(id: groupId, name: 'The Porch'),
      groupRepo: GroupChatRepository(storage, db),
    );
  }

  CharacterCard member(String name) =>
      chat.groupCharacters.firstWhere((c) => c.name == name);

  String idOf(String name) => chat.characterIdFor(member(name));

  /// Turn the live card flag on so [pocketsFor] reveals the stored kit.
  void reveal(CharacterCard c) {
    c.frontPorchExtensions!.pocketsEnabled = true;
  }

  Pockets? revealedKit(String name) {
    reveal(member(name));
    return chat.pocketsFor(idOf(name));
  }

  void plantHidden(String name, String item) {
    chat.setPocketsFor(idOf(name), Pockets(carrying: [PocketItem(item)]));
    expect(
      chat.pocketsFor(idOf(name)),
      isNull,
      reason: 'planted kit must stay hidden while authored off',
    );
  }

  test(
    'transfer to a per-char-off member does not write their hidden kit',
    () async {
      await db.insertGroup(
        GroupsCompanion.insert(id: 'grp-xfer', name: 'The Porch'),
      );
      await insertMember(
        groupId: 'grp-xfer',
        id: 'mem-ana',
        name: 'Ana',
        pocketsOn: true,
      );
      await insertMember(
        groupId: 'grp-xfer',
        id: 'mem-bea',
        name: 'Bea',
        pocketsOn: false,
        carrying: const ['linen handkerchief'],
      );
      await openGroup('grp-xfer');

      expect(chat.pocketsEnabledFor(idOf('Ana')), isTrue);
      expect(chat.pocketsEnabledFor(idOf('Bea')), isFalse);
      plantHidden('Bea', 'lucky coin');

      llm.inventoryJson =
          '{"inventory_ops": [{"op": "give", "item": "keys", "to": "Bea"}]}';
      await chat.sendMessage('Hand Bea the keys.');
      await drainUntil(
        () =>
            !chat.isGenerating &&
            !chat.isSettlingTurn &&
            (chat
                        .pocketsFor(idOf('Ana'))
                        ?.carrying
                        .any((i) => i.name == 'house keys') ??
                    true) ==
                false,
      );

      expect(
        chat.pocketsFor(idOf('Bea')),
        isNull,
        reason: 'still hidden after the hand-off',
      );
      final bea = revealedKit('Bea');
      expect(
        bea?.carrying.map((i) => i.name),
        contains('lucky coin'),
        reason: 'HIDES≠erase — planted kit must survive the refused transfer',
      );
      expect(
        bea?.carrying.map((i) => i.name) ?? const [],
        isNot(contains('house keys')),
        reason: 'THE BUG: fallback seed + setPocketsFor planted Ana\'s keys',
      );
    },
  );

  test(
    'stamp-less 1:1 fork does not erase a per-char-off session kit',
    () async {
      final c = CharacterCard(
        name: 'Bea',
        firstMessage: 'Hi.',
        frontPorchExtensions: FrontPorchExtensions(
          pocketsEnabled: false,
          inventory: Pockets.cardJsonFrom(
            worn: const [],
            carrying: const ['house keys'],
          ),
        ),
      )..dbId = 'char-fork-off';
      await chat.setActiveCharacter(c);
      final id = chat.characterIdFor(c);
      expect(chat.pocketsEnabledFor(id), isFalse);

      chat.setPocketsFor(
        id,
        Pockets(carrying: [const PocketItem('lucky coin')]),
      );
      expect(chat.pocketsFor(id), isNull);
      expect(chat.messages, isNotEmpty);

      for (final m in chat.messages) {
        m.metadata?.remove('realism_state');
        for (final swipe in m.swipeMetadata) {
          swipe?.remove('realism_state');
        }
      }

      await chat.forkFromMessage(chat.messages.length - 1);
      chat.activeCharacter!.frontPorchExtensions!.pocketsEnabled = true;
      expect(
        chat.pocketsFor(id)?.carrying.map((i) => i.name),
        contains('lucky coin'),
        reason:
            'THE BUG: `_pockets = null` then seed-skip erased the hidden kit',
      );
    },
  );

  test(
    'group fork walk-back keeps a per-char-off member\'s hidden kit',
    () async {
      await db.insertGroup(
        GroupsCompanion.insert(id: 'grp-fork', name: 'The Porch'),
      );
      await insertMember(
        groupId: 'grp-fork',
        id: 'mem-ana-f',
        name: 'Ana',
        pocketsOn: true,
      );
      await insertMember(
        groupId: 'grp-fork',
        id: 'mem-bea-f',
        name: 'Bea',
        pocketsOn: false,
      );
      await openGroup('grp-fork');
      plantHidden('Bea', 'lucky coin');

      llm.inventoryJson = '{"inventory_ops": []}';
      await chat.sendMessage('Just sitting.');
      await drainUntil(() => !chat.isGenerating && !chat.isSettlingTurn);
      expect(chat.messages, isNotEmpty);

      await chat.forkFromMessage(chat.messages.length - 1);

      final bea = revealedKit('Bea');
      expect(
        bea?.carrying.map((i) => i.name),
        contains('lucky coin'),
        reason:
            'THE BUG: global-on walk-back dropped keptPockets then seed-skipped',
      );
    },
  );

  test('middle-delete invert does not invent/wipe a per-char-off kit', () async {
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-del', name: 'The Porch'),
    );
    await insertMember(
      groupId: 'grp-del',
      id: 'mem-ana-d',
      name: 'Ana',
      pocketsOn: true,
    );
    await insertMember(
      groupId: 'grp-del',
      id: 'mem-bea-d',
      name: 'Bea',
      pocketsOn: false,
    );
    await openGroup('grp-del');
    plantHidden('Bea', 'lucky coin');

    llm.inventoryJson =
        '{"inventory_ops": [{"op": "setdown", "item": "keys", '
        '"where": "on the hallway table"}]}';
    await chat.sendMessage('Ana, set the keys down.');
    await drainUntil(
      () => chat.pocketsFor(idOf('Ana'))?.setAside.isNotEmpty ?? false,
    );

    final parkedIndex = chat.messages.lastIndexWhere(
      (m) => !m.isUser && m.sender != 'System',
    );
    expect(parkedIndex, greaterThanOrEqualTo(0));

    llm.inventoryJson = '{"inventory_ops": []}';
    await chat.sendMessage('Just checking.');
    await drainUntil(() => !chat.isGenerating && !chat.isSettlingTurn);
    expect(chat.messages.length - 1, greaterThan(parkedIndex));

    chat.deleteMessage(parkedIndex);
    await drainUntil(() => !chat.isGenerating && !chat.isSettlingTurn);

    final bea = revealedKit('Bea');
    expect(
      bea?.carrying.map((i) => i.name),
      contains('lucky coin'),
      reason:
          'THE BUG: pocketsFor-null ?? Pockets() then setPocketsFor wiped Bea',
    );
  });

  test('.fpchat 1:1 import keeps a per-char-off captured kit', () async {
    final c = CharacterCard(
      name: 'Bea',
      firstMessage: 'Hi.',
      frontPorchExtensions: FrontPorchExtensions(
        pocketsEnabled: false,
        inventory: Pockets.cardJsonFrom(
          worn: const [],
          carrying: const ['house keys'],
        ),
      ),
    )..dbId = 'char-fpchat-off';
    await chat.setActiveCharacter(c);
    final id = chat.characterIdFor(c);
    expect(chat.pocketsEnabledFor(id), isFalse);
    expect(chat.messages, isNotEmpty);

    chat.setPocketsFor(
      id,
      Pockets(carrying: [const PocketItem('suitcase keys')]),
    );
    expect(chat.pocketsFor(id), isNull);

    final bytes = await chat.exportToFpchat();
    expect(bytes, isNotNull, reason: 'full package must capture raw _pockets');

    chat.setPocketsFor(id, Pockets(carrying: [const PocketItem('bleed coin')]));

    final outcome = await chat.importChatPackage(bytes!);
    expect(outcome.fullRestore, isTrue);

    chat.activeCharacter!.frontPorchExtensions!.pocketsEnabled = true;
    expect(
      chat.pocketsFor(id)?.carrying.map((i) => i.name),
      contains('suitcase keys'),
      reason: 'THE BUG: Phase-0 null + gated restore dropped the suitcase kit',
    );
    expect(
      chat.pocketsFor(id)?.carrying.map((i) => i.name) ?? const [],
      isNot(contains('bleed coin')),
      reason: 'prior-chat hidden kit must not bleed into the import',
    );
  });
}
