// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The state zone (docs/design/prompt-state-injection.md §6.1) — guards for
// the 2026-08-08 fix to a REPORTED bug, not a hypothetical one. A user ran
// Kimi 2.6 and its visible thinking block read, verbatim:
//
//   "Actually, I think the user included a stale recap block by mistake"
//   "I should follow Linus's message as the primary driver ... while
//    disregarding the outdated 'current task' since that's already happened."
//
// Three defects made that reasonable: the recap is rewritten only every
// journalInterval user messages (default 10) but asserts itself in bare
// present tense; objective steps complete in a fire-and-forget background
// check so the named step can already be history; and nothing anywhere said
// which source wins when they disagree.
//
// The recap's own half of that has since been REPLACED rather than tuned: it
// first carried a clause announcing that it was behind, and the A/B against
// the same model showed the clause being quoted back as the contradiction. A
// block scoped to the past ("Earlier in this story") has nothing to reconcile
// against the present. See buildRecapBlock's doc for the numbers.
//
// The fix is WORDS, not a message role. Moving these blocks into the leading
// system message was tried the same day and reverted: it re-prefills the whole
// transcript on every reply (508 vs 5,020 of 5.5k tokens per warm turn on
// gemma-4-31B), and the Journal's own mood ordering moves the bytes on 41% of
// real turns, so no amount of de-churning buys the prefix back. The zone stays
// in the user turn after the transcript and says out loud who wrote it.
//
// The last test is the end-to-end one: a real ChatService turn against the
// fake backend, reading the actual JSON that goes on the wire.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../integration_test/support/fake_backend.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('recap is scoped to the past, not stamped as stale', () {
    // Supersedes the "staleness stamp" guards written earlier the same day.
    // That stamp — " — the conversation has moved on since it was written",
    // added whenever the Journal pass cursor said the recap was behind — was
    // an ANNOTATED conflict rather than a removed one, and the A/B says it
    // backfired: of the 461 conflict sentences the fixed arm produced, 19
    // named the recap and the modal one was our own clause quoted back ("But
    // the notes say the conversation has moved on since the recap was
    // written"). The head now scopes the block to the past instead, so there
    // is no competing claim about NOW left to reconcile.
    const recap = 'They met on the porch.';

    test('the head puts the recap in the past', () {
      expect(
        buildRecapBlock(recap: recap),
        '\n[Earlier in this story (a recap for memory; not new prose — do not '
        'continue or restate it): They met on the porch.]\n',
      );
    });

    test('nothing in it invites a comparison against the transcript', () {
      // The failure mode this replaces, in every shape it has taken: a
      // staleness stamp, a "may be out of date" hedge, or a boundary claim
      // ("from before the messages above") that a short chat makes false.
      // Precedence for the cases where the model compares anyway is stated
      // once, for the whole zone, by buildStateZoneFrame — not here.
      final block = buildRecapBlock(recap: recap);
      for (final tell in const [
        'moved on',
        'since it was written',
        'out of date',
        'stale',
        'behind',
        'conversation',
        'transcript',
        'above',
        'below',
      ]) {
        expect(
          block.toLowerCase(),
          isNot(contains(tell)),
          reason: '"$tell" re-opens the recap-vs-transcript comparison',
        );
      }
    });

    test('carries no counter — the bytes move only when the recap does', () {
      // An earlier version interpolated the live lag, which changes by two on
      // every turn. Put any per-turn token back (a count, a timestamp, a turn
      // number) and this goes red.
      final block = buildRecapBlock(recap: recap);
      expect(RegExp(r'\d').hasMatch(block), isFalse);
      expect(buildRecapBlock(recap: recap), block);
    });

    test('keeps the anti-echo guard — load-bearing after the transcript', () {
      // This is the last prose the model reads before it writes. Without the
      // guard the nearest continuation target is the recap itself.
      expect(
        buildRecapBlock(recap: recap),
        contains('not new prose — do not continue or restate it'),
      );
    });

    test('says nothing at all when there is no recap', () {
      expect(buildRecapBlock(recap: ''), '');
    });

    test(
      'opens with its own separator so it cannot glue to the block above',
      () {
        expect(buildRecapBlock(recap: recap), startsWith('\n['));
      },
    );
  });

  group('state zone frame', () {
    final frame = buildStateZoneFrame(
      userName: 'Linus',
      characterName: 'Malumbra',
    );

    test('attributes the zone to the app, not to the human', () {
      // The whole point of keeping the zone in the user turn: the attribution
      // has to be carried by the words, because the message role now says the
      // opposite.
      expect(frame, contains('written by the app'));
      expect(frame, contains('Linus did not type them'));
      expect(frame, contains('nothing here needs a reply'));
    });

    test('gives EVENTS to the transcript', () {
      expect(
        frame,
        contains(
          'where these notes disagree with it about events the conversation '
          'is right',
        ),
      );
    });

    test('gives FEELINGS to the notes — so it cannot contradict the Journal\'s '
        'own "truer guide" frame', () {
      expect(frame, contains('on feelings and inner state'));
      expect(frame, contains('the notes are the truer guide'));
    });

    test('states the precedence rule exactly once', () {
      // The register audit (§1) named repetition as the disease. One "the
      // conversation is right", one "truer guide", in one sentence.
      expect('conversation is right'.allMatches(frame).length, 1);
      expect('truer guide'.allMatches(frame).length, 1);
    });

    test('names the KINDS it covers, so it never claims the author-directive '
        'blocks that render between the zone\'s two runs', () {
      // post_history / author_note / the @AN lorebook buckets sit between
      // journal and objectives in render order, and they genuinely ARE the
      // user's. A frame that said "everything below" would swap one lie for
      // another.
      expect(frame, contains('what has happened'));
      expect(frame, contains('how Malumbra feels and how they are right now'));
      expect(frame, contains('what they are working toward'));
      expect(frame, contains('where they are'));
      expect(frame.toLowerCase(), isNot(contains('everything below')));
    });

    test('opens with its own separator so it cannot glue to the last line', () {
      // The transcript carries no trailing newline. Without this the frame
      // reads as the tail of whatever the human just typed — the exact
      // misattribution it exists to prevent.
      expect(frame, startsWith('\n['));
    });

    test('is pronoun-free apart from the ungendered "they" (§3 policy)', () {
      expect(frame.toLowerCase(), isNot(contains(' she ')));
      expect(frame.toLowerCase(), isNot(contains(' he ')));
      expect(frame.toLowerCase(), isNot(contains(' her ')));
      expect(frame.toLowerCase(), isNot(contains(' his ')));
    });

    test('falls back to generic nouns rather than emitting a blank name', () {
      final f = buildStateZoneFrame(userName: '  ', characterName: '');
      expect(f, contains('the user did not type them'));
      expect(f, contains('how the character feels'));
    });
  });

  group('objective step staleness hedge', () {
    AuthorNoteBuilder builderFor(List<Map<String, dynamic>> tasks) =>
        AuthorNoteBuilder(
          getActiveObjectives: () => [
            {
              'objective': 'Reach the sentinel',
              'injectionDepth': 4,
              'isPrimary': true,
            },
          ],
          getPrimaryObjective: () => {
            'objective': 'Reach the sentinel',
            'injectionDepth': 4,
            'isPrimary': true,
          },
          tasksForObjective: (_) => tasks,
          getSecondaryObjectives: () => const [],
        );

    test('a named step carries the "tracking lags the story" hedge once', () {
      final txt = builderFor([
        {'description': 'Kneel before the sentinel', 'completed': false},
      ]).buildObjectiveInjection();
      expect(txt, contains('Current Task: Kneel before the sentinel'));
      expect(
        txt,
        contains('Progress is tracked in the background and can lag'),
      );
      expect(txt, contains('carry on from there instead of staging it again'));
      expect('Progress is tracked'.allMatches(txt).length, 1);
    });

    test(
      'an objective with no step at all gets no hedge (nothing to hedge)',
      () {
        final txt = builderFor(const []).buildObjectiveInjection();
        expect(txt, contains('Current Primary Objective'));
        expect(txt, isNot(contains('Progress is tracked')));
      },
    );
  });

  test('END TO END: the whole state zone rides the USER turn after the '
      'transcript, behind one frame', () async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    final backend = await FakeBackendServer.start(
      replyPieces: ['The sentinel does not move.'],
    );
    final llm = OpenRouterService(
      apiUrl: '${backend.baseUrl}/v1',
      modelName: 'smoke-model',
    );
    final db = AppDatabase.forTesting();
    final storage = StorageService();
    final chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..testLlmServiceOverride = llm;
    addTearDown(() async {
      await disposeChatThenCloseDb(chat, db);
      await backend.close();
    });
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Malumbra',
        description: 'Exists only inside the state-zone placement test.',
        firstMessage: 'The hall is cold.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
          // Gives the character-state block something to say with the
          // engine OFF (the Tastes line is deliberately not realism-gated),
          // so the last member of the zone is non-empty too.
          likes: const ['thunderstorms'],
        ),
      )..dbId = 'char-statezone',
    );
    chat.setSummary('The sentinel knelt at the threshold.');

    await chat.sendMessage('And then what happened?');

    final messages =
        (jsonDecode(backend.lastChatBody) as Map)['messages'] as List;
    expect(messages.length, 2, reason: 'exactly two messages on the wire');
    expect(messages.first['role'], 'system');
    expect(messages.last['role'], 'user');
    final system = messages.first['content'] as String;
    final user = messages.last['content'] as String;

    // ── the load-bearing assertion ──
    // Nothing that changes from turn to turn may sit in the system message,
    // because everything after the first differing byte gets re-prefilled
    // and the transcript is all of it. Move any of these into the system
    // message and this goes red.
    // (The recap is suppressed on this turn — see below — so the
    // character-state block carries this assertion. It is the zone's last
    // member, so if IT is in the user turn the whole zone is.)
    expect(user, contains('drawn to thunderstorms'));
    expect(system, isNot(contains('drawn to thunderstorms')));
    expect(system, isNot(contains('The sentinel knelt at the threshold.')));

    // The transcript is the user's, and the card is the app's — unchanged.
    expect(user, contains('And then what happened?'));
    expect(user, contains('<START>'));
    expect(system, contains('Malumbra\'s Persona'));
    expect(system, isNot(contains('And then what happened?')));

    // ── one frame, and it opens the zone ──
    expect(system, isNot(contains('Story state —')));
    expect('Story state —'.allMatches(user).length, 1);
    expect(
      user.indexOf('And then what happened?'),
      lessThan(user.indexOf('Story state —')),
      reason: 'the frame must come after the transcript it defers to',
    );
    // NO RECAP HERE, AND THAT IS THE RULE, NOT AN OMISSION. This chat is a
    // handful of messages, so nothing was dropped from the transcript — every
    // event the recap describes is readable directly below. The recap is
    // suppressed on exactly those turns because a compressed, older second
    // account of visible events is not memory, it is a contradiction the model
    // has to spend reasoning on. Measured: "recap" was named in 19 of 461
    // conflict sentences on the maintainer's real chats, and rewording it
    // moved the rate 33% -> 33% (p=1.00) because the conflict was real.
    // The recap-IS-present ordering is covered by the sibling test below,
    // which shrinks the context until the transcript genuinely loses history.
    expect(
      user,
      isNot(contains('Earlier in this story')),
      reason:
          'nothing was dropped, so the recap can only duplicate the '
          'transcript — it must not be injected',
    );
    expect(
      user.indexOf('Story state —'),
      lessThan(user.indexOf('drawn to thunderstorms')),
      reason: 'and the character-state block, the zone\'s last member',
    );

    // ── Continue strips the zone, and the frame goes with it ──
    // Continue is meant to be the plain transcript plus the partial line, so
    // the runtime blocks come out. On this chat the recap is suppressed too
    // (nothing dropped), which leaves the zone empty — and a frame announcing
    // an empty zone is pure noise, the exact register problem the design
    // audit named. So both must be absent.
    //
    // The frame-SURVIVES-a-partial-strip case is the sibling assertion above:
    // on the normal turn the zone has content and carries exactly one frame.
    await chat.continueGeneration();
    final contUser =
        (jsonDecode(backend.lastChatBody) as Map)['messages'].last['content']
            as String;
    expect(contUser, isNot(contains('drawn to thunderstorms')));
    expect(contUser, isNot(contains('The sentinel knelt at the threshold.')));
    expect(contUser, isNot(contains('Earlier in this story')));
    expect(
      contUser,
      isNot(contains('Story state —')),
      reason: 'the strip emptied the zone, so the frame introduces nothing',
    );
  });
}
