// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Regen races an in-flight Journal/Growth pass. Those passes are
// fire-and-forget after a reply. Regen throws away citing cards, then
// generates. The old pass can still apply XML after tools abort — a
// tools abort was treated as "try XML instead," so cancel did not stop
// apply.
//
// Proven red: with the startedEpoch check removed from _runExchange, this
// test's XML prompt list is non-empty and the stale add lands.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/llm_service.dart';

ChatMessage _msg(String sender, String text, {bool isUser = false}) =>
    ChatMessage(text: text, sender: sender, isUser: isUser);

void main() {
  late AppDatabase db;
  late JournalStore store;

  setUp(() {
    db = AppDatabase.forTesting(sameIsolate: true);
    store = JournalStore(getDb: () => db);
  });
  tearDown(() async => db.close());

  final mara = CharacterCard(
    name: 'Mara',
    description: 'd',
    personality: 'p',
    scenario: 's',
  );

  JournalMaintenance journal({
    required int Function() getPassEpoch,
    required Future<LlmToolResponse?> Function(
      String,
      List<Map<String, dynamic>>,
    )
    fireToolEval,
    required List<String> xmlPrompts,
  }) {
    var running = false;
    return JournalMaintenance(
      store: store,
      probe: ToolTransportProbe(),
      review: JournalReview(
        store: store,
        getSessionId: () => 's1',
        setRecap: (_) {},
        setCursor: (_) {},
        onSaveChat: () async {},
        onNotify: () {},
        getMaxCards: () => 200,
      ),
      fireLLMEval: (p) async {
        xmlPrompts.add(p);
        return '<memory action="add">stale window</memory>'
            '<recap>should not land</recap>';
      },
      fireToolEval: fireToolEval,
      stripThinkBlocks: (t) => t,
      getSessionId: () => 's1',
      getActiveCharacter: () => mara,
      getActiveGroup: () => null,
      getGroupCharacters: () => const [],
      getCharacterIdFromCard: (c) => c.name.toLowerCase(),
      getMessages: () => [_msg('Sam', 'hi', isUser: true), _msg('Mara', 'hey')],
      getUserName: () => 'Sam',
      getCursor: () => 0,
      setCursor: (_) {},
      getRecap: () => '',
      setRecap: (_) {},
      getIsPassRunning: () => running,
      setIsPassRunning: (v) => running = v,
      getReviewFirst: () => false,
      getBackendIdentity: () => 'test-backend',
      getMaxCards: () => 200,
      onNotify: () {},
      onSaveChat: () async {},
      getCurrentStoryDay: () => 1,
      getCurrentStoryClockIso: () => '2026-06-30T09:00:00.000Z',
      getPassEpoch: getPassEpoch,
    );
  }

  test('tools abort after regen does not fall through to XML apply', () async {
    var epoch = 1;
    final xmlPrompts = <String>[];
    final m = journal(
      getPassEpoch: () => epoch,
      xmlPrompts: xmlPrompts,
      fireToolEval: (p, t) async {
        epoch = 2;
        throw Exception('SocketException: Connection reset by peer');
      },
    );
    await m.runMaintenancePass();
    expect(
      xmlPrompts,
      isEmpty,
      reason:
          'regen tore the tools call down; XML must not apply the rejected window',
    );
    expect(await store.cardsFor('s1', 'mara'), isEmpty);
  });

  test('regen bumps the shared epoch; both passes read it', () {
    final regen = File(
      'lib/services/chat/chat_service_reprocess.dart',
    ).readAsStringSync();
    expect(regen, contains('_memoryPassEpoch++'));
    final journal = File(
      'lib/services/chat/journal_maintenance.dart',
    ).readAsStringSync();
    expect(
      journal,
      contains('if (getPassEpoch() != startedEpoch) return null;'),
    );
    final growth = File(
      'lib/services/chat/growth_service.dart',
    ).readAsStringSync();
    expect(
      growth,
      contains('if (getPassEpoch() != startedEpoch) return null;'),
    );
  });
}
