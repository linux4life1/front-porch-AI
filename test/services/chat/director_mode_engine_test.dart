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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart'
    show kCastFeelingsMaxDelta;
import 'package:front_porch_ai/services/chat/director/director.dart';
import 'package:front_porch_ai/utils/utils.dart' show groupMemberStoreId;
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

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

/// Also plays the narrator and the char→char judge, so a test can see what
/// each was asked and hand back a known answer.
class _SceneLlm extends _PromptRecordingLlm {
  final List<String> narrationPrompts = [];
  String narration = 'Narration: Rain starts drumming on the porch roof.';
  String castFeelings = '{"feelings": []}';
  int castFeelingsCalls = 0;

  @override
  Stream<String> generateStream(GenerationParams params) {
    final p = params.prompt;
    if (p.contains('You are the narrator of a roleplay scene')) {
      narrationPrompts.add(p);
      return Stream.value(narration);
    }
    if (p.contains('just replied. Judge how this reply')) {
      castFeelingsCalls++;
      return Stream.value(castFeelings);
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
      // A third member, so one can leave while the user directs.
      final nora = needsCard('Nora');
      await h.repo.addCharacter(nora);
      await h.chat.joinFull(nora);
      await h.settleTurn();
      expect(h.chat.groupCharacters, hasLength(3));
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

  test('while directing, the second-to-last character cannot leave', () async {
    await h.groupWithTwoReplies(aOff: const []);
    h.chat.setGroupChatRepository(GroupChatRepository(h.storage, h.db));
    await h.chat.sendMessage('/director');
    await h.settleTurn();
    expect(h.chat.canRemoveCastMember, isFalse);
    final before = h.chat.messages.length;

    await h.chat.sendMessage('/exit Bram');
    await h.settleTurn();

    expect(h.chat.groupCharacters.map((c) => c.name), contains('Bram'));
    expect(h.chat.messages, hasLength(before), reason: 'no goodbye turn');
    expect(h.chat.guestActivityStatus, contains('at least two characters'));
    expect(h.chat.guestActivityIsError, isTrue);

    // The next note is still a director's note in the same group.
    h.chat.setNextCharacter(member('Ayla'));
    await h.chat.sendMessage('The porch light flickers out.');
    await h.settleTurn();
    expect(h.chat.isGroupMode, isTrue);
    expect(h.chat.observerMode, isTrue);
    expect(
      h.chat.messages[h.chat.messages.length - 2].characterId,
      kDirectorCharacterId,
    );
  });

  test('the open undo names the user until a note closes it, and a refusal '
      'shows one warning sign', () async {
    await h.groupWithTwoReplies(aOff: const []);
    await h.chat.sendMessage('/director');
    await h.settleTurn();
    expect(h.chat.exitUndoIsUserStep, isTrue);
    expect(h.chat.exitUndoName, isNotNull);
    h.chat.consumeExitUndoOffer(); // the desktop SnackBar was shown
    expect(h.chat.exitUndoName, isNotNull, reason: 'web still offers UNDO');

    h.chat.setNextCharacter(member('Ayla'));
    await h.chat.sendMessage('The porch light flickers out.');
    await h.settleTurn();
    expect(h.chat.exitUndoName, isNull);

    await h.chat.sendMessage('/director');
    await h.settleTurn();
    expect(h.chat.guestActivityStatus, startsWith('You are already directing'));
    await h.chat.sendMessage('/director sideways');
    await h.settleTurn();
    expect(h.chat.guestActivityStatus, startsWith('Use /director'));
    expect(h.chat.guestActivityIsError, isTrue);
  });

  test('the auto-chat delay saves and applies to the running scene', () async {
    await h.groupWithTwoReplies(aOff: const []);
    await h.chat.setSavedDirectorDelay(4.5);
    expect(h.chat.savedDirectorDelay, 4.5);
    expect(h.chat.directorDelaySec, 4.5);
  });

  testWidgets('while directing, a member card keeps its state and marks '
      'feelings toward the user as held', (tester) async {
    // The harness's database answers in real time only, so the setup and
    // the save that directing makes run outside the widget clock.
    await tester.runAsync(() async {
      await h.groupWithTwoReplies(aOff: const []);
      h.chat.setObserverMode(true);
      await h.settleTurn();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: GroupMemberCard(
                character: member('Ayla'),
                chatService: h.chat,
                avatarColor: AppColors.formMasterAccent,
                isNextSpeaker: false,
                isExpanded: true,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Held while you direct'), findsOneWidget);
    expect(find.textContaining('Realism off'), findsNothing);
    // Dispose here: the binding checks debugPrint is handed back.
    await tester.runAsync(h.dispose);
  });
  group('the director\'s tools', () {
    late _SceneLlm scene;
    setUp(() {
      scene = _SceneLlm();
      llm = scene;
      h.llm = scene;
      h.chat.testLlmServiceOverride = scene;
    });

    test('a pinned goal reaches every speaker, a whisper only its member, '
        'and both survive a reload', () async {
      await h.groupWithTwoReplies(aOff: const []);
      await h.chat.sendMessage('/goal Find the lost key before dawn');
      await h.settleTurn();
      expect(h.chat.directorGoal, isEmpty, reason: 'only while directing');

      await h.chat.sendMessage('/director');
      await h.settleTurn();
      await h.chat.sendMessage('/goal Find the lost key before dawn');
      await h.chat.sendMessage('/whisper Ayla You took the key yourself.');
      await h.settleTurn();
      expect(h.chat.directorGoal, 'Find the lost key before dawn');
      expect(h.chat.directorWhisperRows.single.name, 'Ayla');

      h.chat.setNextCharacter(member('Ayla'));
      await h.chat.sendMessage('The porch light flickers out.');
      await h.settleTurn();
      expect(scene.replyPrompts.last, contains('Find the lost key'));
      expect(scene.replyPrompts.last, contains('You took the key yourself.'));

      h.chat.setNextCharacter(member('Bram'));
      await h.chat.sendMessage('Somebody knocks.');
      await h.settleTurn();
      expect(scene.replyPrompts.last, contains('Find the lost key'));
      expect(
        scene.replyPrompts.last,
        isNot(contains('You took the key yourself.')),
        reason: 'a whisper is for one member only',
      );

      final sid = h.chat.currentSessionId!;
      await h.chat.startNewChat();
      await h.settleTurn();
      expect(h.chat.directorGoal, isEmpty);
      await h.chat.loadSession(sid);
      await h.settleTurn();
      expect(h.chat.directorGoal, 'Find the lost key before dawn');
      expect(
        h.chat.directorWhisperRows.single.text,
        'You took the key yourself.',
      );

      await h.chat.sendMessage('/whisper Ayla off');
      await h.settleTurn();
      expect(h.chat.directorWhisperRows, isEmpty);
    });

    test('/narrate lands a narrator beat in the transcript and the cast '
        'answers it', () async {
      await h.groupWithTwoReplies(aOff: const []);
      await h.chat.sendMessage('/director');
      await h.settleTurn();
      final before = h.chat.messages.length;

      await h.chat.sendMessage('/narrate a storm rolls in');
      await h.settleTurn();

      expect(scene.narrationPrompts.last, contains('a storm rolls in'));
      final beat = h.chat.messages[before];
      expect(beat.isDirectorNarration, isTrue);
      expect(beat.sender, 'Narrator');
      expect(beat.characterId, kDirectorCharacterId);
      expect(beat.text, 'Rain starts drumming on the porch roof.');
      expect(h.chat.messages, hasLength(before + 2));
      expect(h.chat.messages.last.isUser, isFalse);
      expect(
        scene.replyPrompts.last,
        contains('[Narration: Rain starts drumming on the porch roof.]'),
      );
    });

    test('auto-chat stops itself when its run of turns is spent', () async {
      await h.groupWithTwoReplies(aOff: const []);
      await h.chat.sendMessage('/director');
      await h.settleTurn();
      h.chat.directorDelaySec = 0;
      await h.chat.setSavedDirectorTurnBudget(2);
      final before = h.chat.messages.length;

      h.chat.startAutoPlay();
      expect(h.chat.autoChatTurnsLeft, 2);
      for (var i = 0; i < 20 && h.chat.autoPlayActive; i++) {
        await h.settleTurn();
      }

      expect(h.chat.autoPlayActive, isFalse);
      expect(h.chat.messages, hasLength(before + 2));
      expect(h.chat.guestActivityStatus, contains('run of turns is done'));
    });

    test('auto-chat pauses when a character speaks to the user', () async {
      await h.groupWithTwoReplies(aOff: const []);
      await h.chat.sendMessage('/director');
      await h.settleTurn();
      h.chat.directorDelaySec = 0;
      scene.mouth =
          '*She squints at the dark yard.* "User, are you out there?"';
      final before = h.chat.messages.length;

      h.chat.startAutoPlay();
      for (var i = 0; i < 20 && h.chat.autoPlayActive; i++) {
        await h.settleTurn();
      }

      expect(h.chat.autoPlayActive, isFalse);
      expect(h.chat.messages, hasLength(before + 1));
      expect(h.chat.guestActivityStatus, contains('spoke to you'));
    });

    test('the char-to-char judge moves the speaker\'s feelings toward the '
        'member the reply involved', () async {
      await h.groupWithTwoReplies(aOff: const []);
      await h.chat.sendMessage('/director');
      await h.settleTurn();
      final rel = h.chat.relationshipService;
      final aylaId = groupMemberStoreId(member('Ayla'));
      final bramKey = groupMemberStoreId(member('Bram'));
      final before = Map<String, int>.of(
        rel.getInterCharacterRelationships(aylaId),
      );
      expect(before.keys, contains(bramKey));
      scene.castFeelings = '{"feelings": [{"name": "bram", "delta": 9}]}';

      h.chat.setNextCharacter(member('Ayla'));
      await h.chat.sendMessage('Bram hands Ayla a warm mug.');
      await h.settleTurn();

      expect(scene.castFeelingsCalls, greaterThan(0));
      expect(
        rel.getInterCharacterRelationships(aylaId)[bramKey],
        before[bramKey]! + kCastFeelingsMaxDelta,
        reason: 'the judged delta, clamped, moves Ayla toward Bram',
      );
    });
  });
}
