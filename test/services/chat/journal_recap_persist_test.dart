// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The journal pass writes "Where we are" onto the chat's row, not only
// the open chat's memory. Leaving mid-pass must not drop the text the
// cursor just moved past. A review-first proposal is not written yet.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

ChatMessage _msg(String sender, String text, {bool isUser = false}) =>
    ChatMessage(text: text, sender: sender, isUser: isUser);

void main() {
  final host = CharacterCard(name: 'Mara', description: 'Keeps the diary.');

  late AppDatabase db;
  late JournalStore store;

  setUp(() async {
    db = AppDatabase.forTesting(sameIsolate: true);
    store = JournalStore(getDb: () => db);
    await db.insertSession(SessionsCompanion.insert(id: 's1'));
  });

  tearDown(() async {
    await db.close();
  });

  JournalMaintenance pass({
    required String Function() sessionId,
    required bool reviewFirst,
    JournalReview? review,
    required void Function(String) onRecap,
  }) {
    return JournalMaintenance(
      store: store,
      probe: ToolTransportProbe()..markXmlOnly('fake'),
      review:
          review ??
          JournalReview(
            store: store,
            getSessionId: sessionId,
            setRecap: onRecap,
            setCursor: (_) {},
            onSaveChat: () async {},
            onNotify: () {},
            getMaxCards: () => 200,
          ),
      fireLLMEval: (_) async {
        return '<recap>We are still on the porch.</recap>'
            '<memory action="add" msgs="1">evening on the steps</memory>';
      },
      fireToolEval: (p, t) async => null,
      stripThinkBlocks: (t) => t,
      getSessionId: sessionId,
      getActiveCharacter: () => host,
      getActiveGroup: () => null,
      getGroupCharacters: () => const [],
      getCharacterIdFromCard: (c) => c.name.toLowerCase(),
      getMessages: () => [
        _msg('Sam', 'evening', isUser: true),
        _msg('Mara', 'evening yourself'),
      ],
      getUserName: () => 'Sam',
      getCursor: () => 0,
      setCursor: (_) {},
      getRecap: () => '',
      setRecap: onRecap,
      getIsPassRunning: () => false,
      setIsPassRunning: (_) {},
      getReviewFirst: () => reviewFirst,
      getBackendIdentity: () => 'fake',
      getMaxCards: () => 200,
      onNotify: () {},
      onSaveChat: () async {},
      getCurrentStoryDay: () => 1,
      getCurrentStoryClockIso: () => '2026-06-30T09:00:00.000Z',
    );
  }

  test('a pass that finishes after you leave still saves the recap', () async {
    var open = 's1';
    final recaps = <String>[];
    final maintenance = JournalMaintenance(
      store: store,
      probe: ToolTransportProbe()..markXmlOnly('fake'),
      review: JournalReview(
        store: store,
        getSessionId: () => open,
        setRecap: recaps.add,
        setCursor: (_) {},
        onSaveChat: () async {},
        onNotify: () {},
        getMaxCards: () => 200,
      ),
      fireLLMEval: (_) async {
        open = 'somewhere-else';
        return '<recap>We are still on the porch.</recap>';
      },
      fireToolEval: (p, t) async => null,
      stripThinkBlocks: (t) => t,
      getSessionId: () => open,
      getActiveCharacter: () => host,
      getActiveGroup: () => null,
      getGroupCharacters: () => const [],
      getCharacterIdFromCard: (c) => c.name.toLowerCase(),
      getMessages: () => [
        _msg('Sam', 'evening', isUser: true),
        _msg('Mara', 'evening yourself'),
      ],
      getUserName: () => 'Sam',
      getCursor: () => 0,
      setCursor: (_) {},
      getRecap: () => '',
      setRecap: recaps.add,
      getIsPassRunning: () => false,
      setIsPassRunning: (_) {},
      getReviewFirst: () => false,
      getBackendIdentity: () => 'fake',
      getMaxCards: () => 200,
      onNotify: () {},
      onSaveChat: () async {},
      getCurrentStoryDay: () => 1,
      getCurrentStoryClockIso: () => '2026-06-30T09:00:00.000Z',
    );

    await maintenance.runMaintenancePass();

    expect(recaps, isEmpty);
    final row = await db.getSessionById('s1');
    expect(row!.summary, 'We are still on the porch.');
  });

  test('review-first does not write the recap or the cursor yet', () async {
    final review = JournalReview(
      store: store,
      getSessionId: () => 's1',
      setRecap: (_) {},
      setCursor: (_) {},
      onSaveChat: () async {},
      onNotify: () {},
      getMaxCards: () => 200,
    );
    await pass(
      sessionId: () => 's1',
      reviewFirst: true,
      review: review,
      onRecap: (_) {},
    ).runMaintenancePass();

    final row = await db.getSessionById('s1');
    expect(row!.summary, isNull);
    expect(row.summaryLastIndex, isNull);
    expect(review.pending?.recap, 'We are still on the porch.');
  });
}
