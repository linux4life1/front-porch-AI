// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group AFK must pick the idle speaker and load that member's needs before
// stamping needs_pre_turn_vector. Stamping the live scalars first baked in
// whoever spoke last, so the AFK chip subtracted the wrong member.
//
// Proven red: moving the stamp above _pickPresentGroupSpeaker in
// chat_service_idle_autonomous.dart stamps Bram's bars on Ayla's bubble.

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/reprocess_needs_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
  });
  tearDown(() => h.dispose());

  Map<String, int> barsOf(ChatMessage m) {
    final needs = (m.activeMetadata?['realism_state'] as Map?)?['needs'];
    return Map<String, int>.from((needs as Map)['vector'] as Map);
  }

  test(
    'group AFK stamps the idle speaker\'s bars, not the last speaker\'s',
    () async {
      await h.groupWithTwoReplies(aOff: const []);
      CharacterCard member(String n) =>
          h.chat.groupCharacters.firstWhere((c) => c.name == n);

      // Bram speaks again on a harder day, so the live scalars are his and
      // differ from Ayla's.
      h.llm.liveNeedsReply =
          '{"hunger_delta": -20, "bladder_delta": -20, "energy_delta": -20, '
          '"social_delta": -20, "fun_delta": -20, "hygiene_delta": -20, '
          '"comfort_delta": -20, "reason": "a double shift"}';
      h.chat.setNextCharacter(member('Bram'));
      await h.chat.sendMessage('Bram, rough one?');
      await h.settleTurn();
      final aylaBars = barsOf(
        h.chat.messages.lastWhere((m) => m.sender == 'Ayla'),
      );
      final bramBars = barsOf(
        h.chat.messages.lastWhere((m) => m.sender == 'Bram'),
      );
      expect(h.chat.needsSimulation.vector, bramBars);
      expect(aylaBars, isNot(bramBars));

      await h.storage.generationSettings.setDynamicResponses(true);
      h.chat.setNextCharacter(member('Ayla'));
      final before = h.chat.messages.length;
      h.chat.debugFireIdleTimerForTest();
      await h.settleTurn();

      expect(h.chat.messages.length, before + 1);
      final afk = h.chat.messages.last;
      expect(afk.sender, 'Ayla');
      expect(
        Map<String, int>.from(
          afk.activeMetadata?['needs_pre_turn_vector'] as Map,
        ),
        aylaBars,
        reason: 'the AFK baseline must be the AFK speaker\'s own bars',
      );
    },
  );
}
