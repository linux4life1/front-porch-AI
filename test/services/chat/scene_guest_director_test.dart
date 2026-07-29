// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for SceneGuestDirector (Scene Guests / Lite NPC auto chime-in leaf).
// The director is pure orchestration over injected closures, so the whole
// decision surface is unit-coverable: the name/nickname heuristic (skips the
// LLM), the LLM relevance gate (yes/no/empty-default-no), scene ordering, the
// at-most-once-per-guest rule, the hard chime-in cap (truncation), the disabled
// flag, and that a refreshed tail is fed to later guests' gates.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/scene_guest_director.dart';

CharacterCard _guest(String name, {String description = ''}) => CharacterCard(
  name: name,
  description: description,
  frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
);

void main() {
  group('SceneGuestDirector', () {
    late List<CharacterCard> guests;
    late List<String> spoke; // names of guests whose turn ran, in order
    late List<String> gatePrompts; // prompts the LLM gate received
    bool enabled = true;

    // Maps a guest name -> the gate's raw JSON reply (null = empty/backend down).
    late Map<String, String?> gateReplies;

    SceneGuestDirector build({String latestAfterEachTurn = ''}) {
      return SceneGuestDirector(
        getSceneGuestCards: () => guests,
        generateGuestTurn: (g) async => spoke.add(g.name),
        getLatestAssistantText: () => latestAfterEachTurn,
        fireGateEval: (prompt) async {
          gatePrompts.add(prompt);
          // The gated guest's name appears in the prompt; match by membership.
          for (final entry in gateReplies.entries) {
            if (prompt.contains(entry.key)) return entry.value;
          }
          return null;
        },
        stripThinkBlocks: (t) => t,
        extractJsonBool: (t, key) {
          final m = RegExp('"$key"\\s*:\\s*(true|false)').firstMatch(t);
          return m != null ? m.group(1) == 'true' : null;
        },
        getHostName: () => 'Host',
        isEnabled: () => enabled,
      );
    }

    setUp(() {
      guests = [];
      spoke = [];
      gatePrompts = [];
      gateReplies = {};
      enabled = true;
    });

    test('exposes a small constant cap', () {
      expect(SceneGuestDirector.maxChimeInsPerTurn, 2);
    });

    test('no-op when disabled', () async {
      enabled = false;
      guests = [_guest('Mara')];
      await build().runChimeIns(userText: 'hi Mara', primaryResponse: '');
      expect(spoke, isEmpty);
      expect(gatePrompts, isEmpty); // heuristic never even runs
    });

    test('no-op when no guests are present', () async {
      await build().runChimeIns(userText: 'hello', primaryResponse: 'hi');
      expect(spoke, isEmpty);
    });

    test(
      'heuristic: full-name mention in user text speaks without the LLM',
      () async {
        guests = [_guest('Mara')];
        await build().runChimeIns(
          userText: 'What do you think, Mara?',
          primaryResponse: 'I am unsure.',
        );
        expect(spoke, ['Mara']);
        expect(gatePrompts, isEmpty); // gate skipped
      },
    );

    test(
      'heuristic: nickname (first token) mention in primary response speaks',
      () async {
        guests = [_guest('Mara Vance')];
        await build().runChimeIns(
          userText: 'tell me more',
          primaryResponse: 'Even Mara would agree with that.',
        );
        expect(spoke, ['Mara Vance']);
        expect(gatePrompts, isEmpty);
      },
    );

    test(
      'heuristic miss: short single-letter names do not false-match',
      () async {
        guests = [_guest('A')];
        gateReplies = {'A': '{"speak": false}'};
        await build().runChimeIns(
          userText: 'a cat sat',
          primaryResponse: 'a dog ran',
        );
        expect(spoke, isEmpty);
        expect(gatePrompts, hasLength(1)); // fell through to the gate
      },
    );

    test('gate YES makes an unaddressed guest speak', () async {
      guests = [_guest('Mara')];
      gateReplies = {'Mara': '{"speak": true}'};
      await build().runChimeIns(
        userText: 'nice weather',
        primaryResponse: 'indeed it is',
      );
      expect(spoke, ['Mara']);
      expect(gatePrompts, hasLength(1));
    });

    test('gate NO keeps an unaddressed guest silent', () async {
      guests = [_guest('Mara')];
      gateReplies = {'Mara': '{"speak": false}'};
      await build().runChimeIns(
        userText: 'nice weather',
        primaryResponse: 'indeed it is',
      );
      expect(spoke, isEmpty);
    });

    test(
      'gate empty/null defaults to NO (KoboldCPP empty-eval gotcha)',
      () async {
        guests = [_guest('Mara')];
        gateReplies = {'Mara': null};
        await build().runChimeIns(
          userText: 'nice weather',
          primaryResponse: 'indeed it is',
        );
        expect(spoke, isEmpty);
      },
    );

    test('evaluates guests in scene order', () async {
      guests = [_guest('Ann'), _guest('Bob')];
      gateReplies = {'Ann': '{"speak": true}', 'Bob': '{"speak": true}'};
      await build().runChimeIns(userText: 'hello all', primaryResponse: 'hi');
      expect(spoke, ['Ann', 'Bob']);
    });

    test(
      'caps total chime-ins at maxChimeInsPerTurn (truncates extras)',
      () async {
        guests = [_guest('Ann'), _guest('Bob'), _guest('Cal')];
        gateReplies = {
          'Ann': '{"speak": true}',
          'Bob': '{"speak": true}',
          'Cal': '{"speak": true}',
        };
        await build().runChimeIns(userText: 'hello all', primaryResponse: 'hi');
        // Cap is 2 — the third willing guest is truncated.
        expect(spoke, ['Ann', 'Bob']);
        expect(spoke, hasLength(SceneGuestDirector.maxChimeInsPerTurn));
      },
    );

    test('each guest is evaluated at most once per turn', () async {
      guests = [_guest('Ann')];
      gateReplies = {'Ann': '{"speak": true}'};
      await build().runChimeIns(userText: 'hi', primaryResponse: 'hi');
      expect(spoke, ['Ann']);
      expect(
        gatePrompts.where((p) => p.contains('Ann')),
        hasLength(1), // gated exactly once — never re-evaluated
        reason: 'Ann was evaluated via the gate exactly once',
      );
    });

    test(
      'later guest gate sees the refreshed tail after an earlier turn',
      () async {
        guests = [_guest('Ann'), _guest('Bob')];
        gateReplies = {'Ann': '{"speak": true}', 'Bob': '{"speak": true}'};
        // After Ann speaks, the latest assistant text becomes this line.
        final dir = build(latestAfterEachTurn: 'ANNS_NEW_LINE');
        await dir.runChimeIns(userText: 'go', primaryResponse: 'PRIMARY_LINE');
        // Bob's gate prompt must contain Ann's refreshed line, not the primary's.
        final bobPrompt = gatePrompts.firstWhere((p) => p.contains('Bob'));
        expect(bobPrompt, contains('ANNS_NEW_LINE'));
        expect(bobPrompt, isNot(contains('PRIMARY_LINE')));
      },
    );

    test('a title first-name ("Major Tom") is NOT used as a nickname', () async {
      guests = [_guest('Major Tom')];
      gateReplies = {'Major Tom': '{"speak": false}'}; // gate decides, says no
      await build().runChimeIns(
        // "major" appears but is a title, not the guest — must not force a turn.
        userText: 'the major inspected the troops',
        primaryResponse: 'all quiet',
      );
      expect(spoke, isEmpty);
      expect(gatePrompts, hasLength(1),
          reason: 'should fall through to the LLM gate, not the nickname');
    });

    test('a normal first-name nickname still fires (Mara ← "Mara Vance")',
        () async {
      guests = [_guest('Mara Vance')];
      await build().runChimeIns(
        userText: 'have you seen Mara today?',
        primaryResponse: 'not yet',
      );
      expect(spoke, ['Mara Vance']);
      expect(gatePrompts, isEmpty, reason: 'nickname heuristic short-circuits');
    });

    test('exclude: a routed direct-address speaker never re-chimes', () async {
      guests = [_guest('Ann'), _guest('Bob')];
      gateReplies = {'Bob': '{"speak": true}'};
      // "Ann" saturates the user text (heuristic hit), but Ann already spoke
      // via the direct-address route — she must be skipped entirely.
      await build().runChimeIns(
        userText: 'Ann - what do you think?',
        primaryResponse: 'ANN_REPLY mentioning Ann herself',
        exclude: guests.first,
      );
      expect(spoke, ['Bob'], reason: 'Ann is excluded, Bob gates in');
      expect(
        gatePrompts.where((p) => p.contains('Would Ann')),
        isEmpty,
        reason: 'the excluded guest is never even gate-evaluated',
      );
    });

    group('directlyAddressedGuest', () {
      test('leading vocative with dash routes (the Discord report shape)', () {
        guests = [_guest('Evelyn')];
        final got = build().directlyAddressedGuest(
          'Evelyn - I was hoping you could clarify your point from before',
        );
        expect(got?.name, 'Evelyn');
      });

      test('leading vocative with comma routes', () {
        guests = [_guest('Mara Vance')];
        expect(
          build().directlyAddressedGuest('Mara, can you help me?')?.name,
          'Mara Vance',
        );
      });

      test('bare name routes', () {
        guests = [_guest('Evelyn')];
        expect(build().directlyAddressedGuest('Evelyn?')?.name, 'Evelyn');
      });

      test('trailing vocative routes', () {
        guests = [_guest('Mara Vance')];
        expect(
          build().directlyAddressedGuest('What do you think, Mara?')?.name,
          'Mara Vance',
        );
      });

      test('quoted roleplay wrapper still anchors', () {
        guests = [_guest('Evelyn')];
        expect(
          build().directlyAddressedGuest('"Evelyn, help!"')?.name,
          'Evelyn',
        );
      });

      test('a mid-sentence mention does NOT route', () {
        guests = [_guest('Evelyn')];
        expect(
          build().directlyAddressedGuest('I told Evelyn about the trip'),
          isNull,
        );
      });

      test('narration starting with the name does NOT route', () {
        guests = [_guest('Evelyn')];
        expect(
          build().directlyAddressedGuest('Evelyn walked into the room'),
          isNull,
        );
      });

      test('a hyphenated OTHER name does NOT route (leading or trailing)', () {
        guests = [_guest('Mara')];
        final dir = build();
        expect(dir.directlyAddressedGuest('Mara-Lynn came by today'), isNull);
        expect(dir.directlyAddressedGuest('I met Anna-Mara.'), isNull);
        // …while a real spaced-dash vocative still routes.
        expect(dir.directlyAddressedGuest('Mara - got a second?')?.name, 'Mara');
      });

      test('a possessive does NOT route', () {
        guests = [_guest('Evelyn')];
        expect(
          build().directlyAddressedGuest("Evelyn's point was interesting"),
          isNull,
        );
      });

      test('addressing the HOST does NOT route to a guest', () {
        guests = [_guest('Evelyn')];
        expect(
          build().directlyAddressedGuest('Host, what do you think?'),
          isNull,
        );
      });

      test('a title first-name is not a routable nickname', () {
        guests = [_guest('Major Tom')];
        final dir = build();
        expect(dir.directlyAddressedGuest('Major, report!'), isNull);
        expect(
          dir.directlyAddressedGuest('Major Tom, report!')?.name,
          'Major Tom',
        );
      });

      test('disabled director never routes', () {
        enabled = false;
        guests = [_guest('Evelyn')];
        expect(build().directlyAddressedGuest('Evelyn, hi!'), isNull);
        expect(build().directlyAddressedGuest('@Evelyn hi!'), isNull);
      });

      test('@Name routes without punctuation, anywhere in the line', () {
        guests = [_guest('Evelyn')];
        final dir = build();
        expect(
          dir.directlyAddressedGuest('@Evelyn what did you mean')?.name,
          'Evelyn',
        );
        expect(
          dir.directlyAddressedGuest('so hey @Evelyn any thoughts')?.name,
          'Evelyn',
        );
      });

      test('an @ of the HOST anywhere keeps the turn with the host', () {
        guests = [_guest('Evelyn')];
        final dir = build();
        expect(
          dir.directlyAddressedGuest('@Host and @Evelyn — thoughts?'),
          isNull,
        );
        // The veto is absolute: it also beats a guest VOCATIVE later in the
        // same line (Grok finding, review session 2026-07-28).
        expect(
          dir.directlyAddressedGuest('@Host what do you think, Evelyn?'),
          isNull,
        );
      });
    });

    group('atMentionedCard (static @-matcher)', () {
      test('matches first-name nickname and full name, case-insensitive', () {
        final cards = [_guest('Mara Vance'), _guest('Evelyn')];
        expect(
          SceneGuestDirector.atMentionedCard(cards, 'hey @mara, hi')?.name,
          'Mara Vance',
        );
        expect(
          SceneGuestDirector.atMentionedCard(cards, '@Mara Vance hello')?.name,
          'Mara Vance',
        );
      });

      test('earliest @ in text order wins', () {
        final cards = [_guest('Ann'), _guest('Bob')];
        expect(
          SceneGuestDirector.atMentionedCard(
            cards,
            'tell @Bob first, then @Ann',
          )?.name,
          'Bob',
        );
      });

      test('same-@ tie goes to the longer name, not list order', () {
        // "Mara Quinn" is FIRST in the list and her "Mara" nickname matches
        // the same @ — the full-name match must still win.
        final cards = [_guest('Mara Quinn'), _guest('Mara Vance')];
        expect(
          SceneGuestDirector.atMentionedCard(cards, '@Mara Vance hello')?.name,
          'Mara Vance',
        );
      });

      test('@ after punctuation still routes (no space required)', () {
        final cards = [_guest('Evelyn')];
        expect(
          SceneGuestDirector.atMentionedCard(cards, 'hey,@Evelyn hi')?.name,
          'Evelyn',
        );
        expect(
          SceneGuestDirector.atMentionedCard(cards, '[@Evelyn] thoughts?')?.name,
          'Evelyn',
        );
      });

      test('email-like and hyphenated forms never match', () {
        final cards = [_guest('Evelyn'), _guest('Mara')];
        expect(
          SceneGuestDirector.atMentionedCard(cards, 'mail me@evelyn.com'),
          isNull,
        );
        expect(
          SceneGuestDirector.atMentionedCard(cards, 'ask @Mara-Lynn about it'),
          isNull,
        );
      });

      test('no @ in text short-circuits to null', () {
        final cards = [_guest('Evelyn')];
        expect(
          SceneGuestDirector.atMentionedCard(cards, 'Evelyn what gives'),
          isNull,
        );
      });
    });

    test('bails between guests when context becomes invalid', () async {
      guests = [_guest('Ann'), _guest('Bob')];
      gateReplies = {'Ann': '{"speak": true}', 'Bob': '{"speak": true}'};
      var valid = true;
      final dir = build();
      // Invalidate after the first guest speaks (simulate a chat switch).
      await dir.runChimeIns(
        userText: 'go',
        primaryResponse: 'p',
        isContextValid: () {
          if (spoke.isNotEmpty) valid = false;
          return valid;
        },
      );
      expect(spoke, ['Ann'], reason: 'Bob must not speak after context invalid');
    });
  });
}
