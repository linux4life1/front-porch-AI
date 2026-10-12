// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Director Mode turns: {{user}} is off stage, so nothing scores the director's
// note (bond and trust toward the user hold still), while each speaker's own
// Needs keep running and save into that member's group state, exactly as on
// any group turn. Also pins /director stepping out and back in, its undo, and
// Director Mode surviving a reload while a new chat starts from the default.
//
// Proven red: dropping the `_prepareDirectedSpeaker` call in
// chat_service_generation.dart stamps the previous speaker's bars on the
// directed speaker; restoring the observer early return in
// needs_impact_call.dart leaves the speaker's Needs where they were;
// skipping the group host revert in chat_service_regen_revert.dart double
// applies a regenerated directed turn; dropping the session key in
// chat_service_session_state_save.dart loses Director Mode on reload.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/director/director.dart';

import '../../helpers/reprocess_needs_harness.dart';

/// Records the full prompt of every character reply, so a test can see the
/// one-shot stage direction the model was handed.
class _PromptRecordingLlm extends RecordingLlm {
  final List<String> replyPrompts = [];

  @override
  Stream<String> generateStream(GenerationParams params) {
    if (params.systemPrompt != null) {
      replyPrompts.add('${params.systemPrompt}\n${params.prompt}');
    }
    return super.generateStream(params);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  late _PromptRecordingLlm llm;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
    llm = _PromptRecordingLlm();
    h.llm = llm;
    h.chat.testLlmServiceOverride = llm;
  });
  tearDown(() => h.dispose());

  CharacterCard member(String n) =>
      h.chat.groupCharacters.firstWhere((c) => c.name == n);

  Map<String, int> preTurnBars(ChatMessage m) =>
      Map<String, int>.from(m.activeMetadata?['needs_pre_turn_vector'] as Map);

  test('a directed turn runs the speaker\'s own Needs and leaves bond and '
      'trust toward the user alone', () async {
    await h.groupWithTwoReplies(aOff: const []);
    // Bram has a harder day, so his live bars differ from Ayla's.
    h.llm.liveNeedsReply =
        '{"hunger_delta": -20, "bladder_delta": -20, "energy_delta": -20, '
        '"social_delta": -20, "fun_delta": -20, "hygiene_delta": -20, '
        '"comfort_delta": -20, "reason": "a double shift"}';
    h.chat.setNextCharacter(member('Bram'));
    await h.chat.sendMessage('Bram, rough one?');
    await h.settleTurn();
    h.llm.liveNeedsReply = RecordingLlm().liveNeedsReply;
    final aylaBefore = h.chat.getNeedsForGroupCharacter(member('Ayla'));
    final aylaRealism = h.chat.getRealismStateForGroupCharacter(
      member('Ayla'),
    )!;
    expect(h.chat.needsSimulation.vector, isNot(aylaBefore));

    h.chat.setObserverMode(true);
    h.chat.setNextCharacter(member('Ayla'));
    await h.chat.sendMessage('The porch light flickers out.');
    await h.settleTurn();

    final note = h.chat.messages[h.chat.messages.length - 2];
    expect(note.characterId, kDirectorCharacterId);
    expect(note.sender, 'Director');
    final reply = h.chat.messages.last;
    expect(reply.sender, 'Ayla');
    expect(
      preTurnBars(reply),
      aylaBefore,
      reason: 'the directed speaker must start from her own bars',
    );

    final aylaAfter = h.chat.getNeedsForGroupCharacter(member('Ayla'));
    final deltas = reply.activeMetadata?['needs_deltas'] as Map;
    expect(
      (deltas['hunger'] as Map)['reason'],
      'a long walk',
      reason: 'the Needs judge must run on a directed turn',
    );
    for (final n in kAllNeeds) {
      expect(
        aylaAfter[n],
        lessThan(aylaBefore[n]!),
        reason: '$n must move and save into Ayla\'s own state',
      );
    }
    final after = h.chat.getRealismStateForGroupCharacter(member('Ayla'))!;
    expect(after['affection'], aylaRealism['affection']);
    expect(after['trust'], aylaRealism['trust']);
  });

  test('regenerating a directed turn rewinds the speaker\'s Needs '
      'instead of applying them twice', () async {
    await h.groupWithTwoReplies(aOff: const []);
    h.chat.setObserverMode(true);
    h.chat.setNextCharacter(member('Ayla'));
    await h.chat.sendMessage('The porch light flickers out.');
    await h.settleTurn();
    final first = h.chat.getNeedsForGroupCharacter(member('Ayla'));

    await h.chat.regenerateLastMessage();
    await h.settleTurn();

    expect(h.chat.messages.last.sender, 'Ayla');
    expect(h.chat.getNeedsForGroupCharacter(member('Ayla')), first);
  });

  test('/director steps the user out with a narrated goodbye, and undo '
      'puts them back', () async {
    await h.groupWithTwoReplies(aOff: const []);
    final before = h.chat.messages.length;

    await h.chat.sendMessage('/director');
    await h.settleTurn();

    expect(h.chat.observerMode, isTrue);
    expect(h.chat.messages, hasLength(before + 1));
    expect(h.chat.messages.last.isUser, isFalse);
    expect(llm.replyPrompts.last, contains('is stepping away from the scene'));

    await h.chat.undoLastExit();
    await h.settleTurn();

    expect(h.chat.observerMode, isFalse);
    expect(h.chat.messages, hasLength(before));
  });

  test(
    'a member who leaves after /director is the one UNDO brings back',
    () async {
      await h.groupWithTwoReplies(aOff: const []);
      h.chat.setGroupChatRepository(GroupChatRepository(h.storage, h.db));
      await h.chat.sendMessage('/director');
      await h.settleTurn();
      await h.chat.sendMessage('/exit Bram');
      await h.settleTurn();
      expect(
        h.chat.groupCharacters.map((c) => c.name),
        isNot(contains('Bram')),
      );

      await h.chat.undoLastExit();
      await h.settleTurn();

      expect(h.chat.groupCharacters.map((c) => c.name), contains('Bram'));
      expect(h.chat.observerMode, isTrue, reason: 'the user stays off stage');
    },
  );

  test('/director off brings the user back with a greeting', () async {
    await h.groupWithTwoReplies(aOff: const []);
    await h.chat.sendMessage('/director');
    await h.settleTurn();
    final before = h.chat.messages.length;

    await h.chat.sendMessage('/director off');
    await h.settleTurn();

    expect(h.chat.observerMode, isFalse);
    expect(h.chat.messages, hasLength(before + 1));
    expect(llm.replyPrompts.last, contains('comes back into the scene'));
  });

  test('/director in a plain 1:1 is refused', () async {
    await h.oneToOneWithStampedReply(needsCard('Mara'));
    final before = h.chat.messages.length;

    await h.chat.sendMessage('/director');
    await h.settleTurn();

    expect(h.chat.isGroupMode, isFalse);
    expect(h.chat.observerMode, isFalse);
    expect(h.chat.messages, hasLength(before));
    expect(h.chat.guestActivityStatus, contains('needs a cast'));
  });

  test(
    '/director in a 1:1 with a guest makes it a group, then directs',
    () async {
      await h.repo.addCharacter(needsCard('Nora'));
      h.chat.setGroupChatRepository(GroupChatRepository(h.storage, h.db));
      await h.oneToOneWithStampedReply(needsCard('Mara'));
      await h.chat.sendMessage('/join Nora');
      await h.settleTurn();
      expect(h.chat.isGroupMode, isFalse);

      await h.chat.sendMessage('/director');
      await h.settleTurn();

      expect(h.chat.isGroupMode, isTrue);
      expect(h.chat.observerMode, isTrue);
      expect(
        llm.replyPrompts.last,
        contains('is stepping away from the scene'),
      );
    },
  );

  test('Director Mode survives a reload; a new chat starts from the '
      'group default', () async {
    await h.groupWithTwoReplies(aOff: const []);
    await h.chat.sendMessage('/director');
    await h.settleTurn();
    final sid = h.chat.currentSessionId!;

    await h.chat.startNewChat();
    await h.settleTurn();
    expect(h.chat.observerMode, isFalse);

    await h.chat.loadSession(sid);
    await h.settleTurn();
    expect(h.chat.observerMode, isTrue);
  });
}
