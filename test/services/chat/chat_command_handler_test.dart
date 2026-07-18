// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for ChatCommandHandler (Scene Guests / Lite NPC slash-command leaf).
// The handler is pure dispatch/parsing over injected closures, so the whole
// surface is unit-coverable: non-commands fall through, expression set/clear
// dispatch, unknown commands fall through, /create parsing + mint wiring
// (success + failure + guards), and /exit selection (named, partial, omitted,
// missing, no-guests) with departure arming + primary-turn trigger.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/chat_command_handler.dart';

CharacterCard _guest(String name) => CharacterCard(
  name: name,
  frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
);

void main() {
  group('ChatCommandHandler', () {
    late List<CharacterCard> guests;
    late List<String> systemMessages;
    late List<String?> expressionCalls;
    late List<(String, String)> createCalls;
    late List<CharacterCard> exited;
    late List<CharacterCard> joinable;
    late List<CharacterCard> joined;
    late List<CharacterCard> joinedFull;
    late int scenePromotions;
    late List<CharacterCard> spoke;
    late List<CharacterCard> undoArmed;
    late List<String> pickerRequests;
    late List<bool> pickerFull;
    late String? pendingDeparture;
    late int primaryTurns;
    late int castScans;
    late List<CharacterCard> groupMembers;
    late List<CharacterCard> groupJoinable;
    late List<CharacterCard> removedMembers;
    late List<CharacterCard> spokeMembers;
    late bool turnOrderRandom;
    late List<(bool, List<CharacterCard>?)> turnOrderCalls;
    late List<(bool, int?, int?)> afkCalls;
    late List<String> imageCalls;
    bool castScanFound = false;

    ChatCommandHandler build({bool activeSet = true}) {
      return ChatCommandHandler(
        setExpression: expressionCalls.add,
        activeCharacterIsSet: () => activeSet,
        getSceneGuestCards: () => guests,
        setPendingGuestDeparture: (n) => pendingDeparture = n,
        onSystemMessage: systemMessages.add,
        generatePrimaryTurn: () async => primaryTurns++,
        createGuest: (name, concept) async => createCalls.add((name, concept)),
        exitGuest: (g) async => exited.add(g),
        getJoinableCharacters: () => joinable,
        joinGuest: (g) async => joined.add(g),
        joinFull: (c) async => joinedFull.add(c),
        promoteScene: () async => scenePromotions++,
        requestGuestPicker: (filter, full) {
          pickerRequests.add(filter);
          pickerFull.add(full);
        },
        runCastScan: () async {
          castScans++;
          return castScanFound;
        },
        speakGuest: (g) async => spoke.add(g),
        armExitUndo: (g) => undoArmed.add(g),
        getGroupMembers: () => groupMembers,
        getGroupJoinableCharacters: () => groupJoinable,
        removeGroupMember: (m) async {
          removedMembers.add(m);
          return true;
        },
        speakGroupMember: (m) async => spokeMembers.add(m),
        isGroupTurnOrderRandom: () => turnOrderRandom,
        setGroupTurnOrder: (random, order) async {
          turnOrderCalls.add((random, order));
        },
        configureAfk: (enabled, maxMessages, intervalSeconds) {
          afkCalls.add((enabled, maxMessages, intervalSeconds));
          return (
            enabled: enabled,
            maxMessages: maxMessages ?? 3,
            intervalSeconds: intervalSeconds ?? 60,
          );
        },
        generateImage: (args) async => imageCalls.add(args),
      );
    }

    setUp(() {
      guests = [];
      systemMessages = [];
      expressionCalls = [];
      createCalls = [];
      exited = [];
      joinable = [];
      joined = [];
      joinedFull = [];
      scenePromotions = 0;
      spoke = [];
      undoArmed = [];
      pickerRequests = [];
      pickerFull = [];
      pendingDeparture = null;
      primaryTurns = 0;
      castScans = 0;
      groupMembers = [];
      groupJoinable = [];
      removedMembers = [];
      spokeMembers = [];
      turnOrderRandom = false;
      turnOrderCalls = [];
      afkCalls = [];
      imageCalls = [];
      castScanFound = false;
    });

    test('non-command input is not handled', () async {
      expect(await build().handle('hello there'), false);
    });

    test('unknown command falls through (not handled)', () async {
      expect(await build().handle('/wobble foo'), false);
    });

    test(
      '/expression sets a manual label, /expression-clear clears it',
      () async {
        final h = build();
        expect(await h.handle('/expression happy'), true);
        expect(await h.handle('/expression'), true); // empty args -> clear
        expect(await h.handle('/expression-clear'), true);
        expect(expressionCalls, ['happy', null, null]);
      },
    );

    test('/create outside a 1:1 chat is rejected before creating', () async {
      final h = build(activeSet: false);
      expect(await h.handle('/create Bob: a baker'), true);
      expect(systemMessages.single, contains('1:1'));
      expect(createCalls, isEmpty);
    });

    test('/create with empty args shows usage', () async {
      final h = build();
      expect(await h.handle('/create'), true);
      expect(systemMessages.last, contains('Usage'));
      expect(createCalls, isEmpty);
    });

    test('/create splits name/concept on ":" and delegates', () async {
      final h = build();
      expect(await h.handle('/create Bob: a cheerful baker'), true);
      expect(createCalls.single, ('Bob', 'a cheerful baker'));
    });

    test('/create splits name/concept on "|"', () async {
      final h = build();
      await h.handle('/create Mara | a stoic guard');
      expect(createCalls.single, ('Mara', 'a stoic guard'));
    });

    test('/create with name only yields empty concept', () async {
      final h = build();
      await h.handle('/create Solo');
      expect(createCalls.single, ('Solo', ''));
    });

    test('/exit with no guests surfaces a message and is handled', () async {
      final h = build();
      expect(await h.handle('/exit'), true);
      expect(systemMessages.single, contains('no scene guests'));
      expect(exited, isEmpty);
      expect(primaryTurns, 0);
    });

    test('/exit (no name) removes the last guest and arms departure', () async {
      guests = [_guest('Aria'), _guest('Bram')];
      final h = build();
      expect(await h.handle('/exit'), true);
      expect(exited.single.name, 'Bram'); // most-recent guest
      expect(pendingDeparture, 'Bram');
      expect(primaryTurns, 1);
      // Undo is armed (after the departure turn) for the exited guest.
      expect(undoArmed.single.name, 'Bram');
    });

    test('a failed /exit (unknown name) does NOT arm undo', () async {
      guests = [_guest('Aria')];
      final h = build();
      await h.handle('/exit zzz');
      expect(undoArmed, isEmpty);
    });

    test('/exit <name> selects the named guest (case-insensitive)', () async {
      guests = [_guest('Aria'), _guest('Bram')];
      final h = build();
      expect(await h.handle('/exit aria'), true);
      expect(exited.single.name, 'Aria');
      expect(pendingDeparture, 'Aria');
    });

    test('/exit partial-name match falls back to contains()', () async {
      guests = [_guest('Aria the Brave')];
      final h = build();
      expect(await h.handle('/exit brave'), true);
      expect(pendingDeparture, 'Aria the Brave');
    });

    test(
      '/exit with an unknown name surfaces an error, no departure',
      () async {
        guests = [_guest('Aria')];
        final h = build();
        expect(await h.handle('/exit zzz'), true);
        expect(systemMessages.single, contains('zzz'));
        expect(pendingDeparture, isNull);
        expect(exited, isEmpty);
        expect(primaryTurns, 0);
      },
    );

    test('/join with no chat open (no 1:1, no group) is rejected', () async {
      joinable = [_guest('Nora')];
      final h = build(
        activeSet: false,
      ); // not a 1:1 and groupMembers stays empty
      expect(await h.handle('/join Nora'), true);
      expect(systemMessages.single, contains('Open a chat'));
      expect(joined, isEmpty);
      expect(pickerRequests, isEmpty);
    });

    test(
      '/join <name> in a group routes to a FULL join (no lite tier)',
      () async {
        groupMembers = [_guest('Aria'), _guest('Bryn')];
        groupJoinable = [_guest('Nora')];
        final h = build(
          activeSet: false,
        ); // group mode (activeCharacterIsSet false)
        expect(await h.handle('/join Nora'), true);
        expect(joinedFull.single.name, 'Nora'); // full, not lite
        expect(joined, isEmpty);
        expect(pickerRequests, isEmpty);
      },
    );

    test('/join --full <name> in a group adds the member', () async {
      groupMembers = [_guest('Aria'), _guest('Bryn')];
      groupJoinable = [_guest('Nora')];
      final h = build(activeSet: false);
      expect(await h.handle('/join --full Nora'), true);
      expect(joinedFull.single.name, 'Nora');
    });

    test('/exit <name> in a group removes that full member', () async {
      groupMembers = [_guest('Aria'), _guest('Bryn')];
      final h = build(activeSet: false);
      expect(await h.handle('/exit Bryn'), true);
      expect(removedMembers.single.name, 'Bryn');
      expect(exited, isEmpty); // not the Lite-NPC path
    });

    test('/exit (no name) in a group asks which member', () async {
      groupMembers = [_guest('Aria'), _guest('Bryn')];
      final h = build(activeSet: false);
      expect(await h.handle('/exit'), true);
      expect(removedMembers, isEmpty);
      expect(systemMessages.single, contains('Who should leave'));
    });

    test('/exit <unknown> in a group surfaces a message', () async {
      groupMembers = [_guest('Aria'), _guest('Bryn')];
      final h = build(activeSet: false);
      expect(await h.handle('/exit Zed'), true);
      expect(removedMembers, isEmpty);
      expect(systemMessages.single, contains('No group member'));
    });

    test(
      '/speak <name> in a group forces that member to take a turn',
      () async {
        groupMembers = [_guest('Aria'), _guest('Bryn')];
        final h = build(activeSet: false);
        expect(await h.handle('/speak Bryn'), true);
        expect(spokeMembers.single.name, 'Bryn');
        expect(spoke, isEmpty); // not the Lite-NPC path
      },
    );

    test(
      '/speak <unique substring> in a group forces the single match',
      () async {
        groupMembers = [_guest('Aria'), _guest('Bryn')];
        final h = build(activeSet: false);
        expect(await h.handle('/speak bry'), true);
        expect(spokeMembers.single.name, 'Bryn');
      },
    );

    test('/speak (no name) in a group asks which member', () async {
      groupMembers = [_guest('Aria'), _guest('Bryn')];
      final h = build(activeSet: false);
      expect(await h.handle('/speak'), true);
      expect(spokeMembers, isEmpty);
      expect(systemMessages.single, contains('Who should speak'));
    });

    test(
      '/speak <unknown> in a group speaks nobody and surfaces a message',
      () async {
        groupMembers = [_guest('Aria'), _guest('Bryn')];
        final h = build(activeSet: false);
        expect(await h.handle('/speak Zed'), true);
        expect(spokeMembers, isEmpty);
        expect(systemMessages.single, contains('No group member'));
      },
    );

    test('/speak <ambiguous substring> in a group speaks nobody', () async {
      groupMembers = [_guest('Aria'), _guest('Arien')];
      final h = build(activeSet: false);
      expect(await h.handle('/speak Ar'), true);
      expect(spokeMembers, isEmpty);
      expect(systemMessages.single, contains('matches multiple members'));
    });

    test('/turnorder random sets random mode', () async {
      groupMembers = [_guest('Aria'), _guest('Bryn')];
      final h = build(activeSet: false);
      expect(await h.handle('/turnorder random'), true);
      expect(turnOrderCalls.single.$1, true);
      expect(turnOrderCalls.single.$2, isNull);
    });

    test('/turnorder roundrobin sets round-robin mode', () async {
      groupMembers = [_guest('Aria'), _guest('Bryn')];
      final h = build(activeSet: false);
      expect(await h.handle('/turnorder roundrobin'), true);
      expect(turnOrderCalls.single.$1, false);
      expect(turnOrderCalls.single.$2, isNull);
    });

    test(
      '/turnorder <names> sets an explicit order (unnamed appended)',
      () async {
        groupMembers = [_guest('Aria'), _guest('Bryn'), _guest('Cleo')];
        final h = build(activeSet: false);
        expect(await h.handle('/turnorder Bryn, Aria'), true);
        final call = turnOrderCalls.single;
        expect(call.$1, false);
        expect(call.$2!.map((c) => c.name).toList(), ['Bryn', 'Aria', 'Cleo']);
      },
    );

    test(
      '/turnorder accepts a "you"/{{user}} slot (skipped in AI rotation)',
      () async {
        groupMembers = [_guest('Aria'), _guest('Bryn'), _guest('Cleo')];
        final h = build(activeSet: false);
        expect(await h.handle('/turnorder Bryn, {{user}}, Aria'), true);
        final call = turnOrderCalls.single;
        expect(call.$1, false);
        // The user token is NOT a character — rotation is the named members
        // (unnamed appended), and the confirmation mentions "you".
        expect(call.$2!.map((c) => c.name).toList(), ['Bryn', 'Aria', 'Cleo']);
        expect(systemMessages.single, contains('you'));
      },
    );

    test('/turnorder <unknown name> errors and sets nothing', () async {
      groupMembers = [_guest('Aria'), _guest('Bryn')];
      final h = build(activeSet: false);
      expect(await h.handle('/turnorder Zed'), true);
      expect(turnOrderCalls, isEmpty);
      expect(systemMessages.single, contains('No group member matches'));
    });

    test('/turnorder (no args) reports current mode, sets nothing', () async {
      groupMembers = [_guest('Aria'), _guest('Bryn')];
      turnOrderRandom = true;
      final h = build(activeSet: false);
      expect(await h.handle('/turnorder'), true);
      expect(turnOrderCalls, isEmpty);
      expect(systemMessages.single, contains('random'));
    });

    test('/turnorder outside a group is rejected', () async {
      final h = build(); // 1:1, no group members
      expect(await h.handle('/turnorder random'), true);
      expect(turnOrderCalls, isEmpty);
      expect(systemMessages.single, contains('only applies inside a group'));
    });

    test('/exit cannot remove the only remaining group member', () async {
      groupMembers = [_guest('Aria')];
      final h = build(activeSet: false);
      expect(await h.handle('/exit Aria'), true);
      expect(removedMembers, isEmpty);
      expect(systemMessages.single, contains('only remaining'));
    });

    test('/join with no joinable characters surfaces a message', () async {
      final h = build();
      expect(await h.handle('/join'), true);
      expect(systemMessages.single, contains('No other characters'));
      expect(pickerRequests, isEmpty);
    });

    test('/join (no name) opens the picker with an empty filter', () async {
      joinable = [_guest('Nora'), _guest('Pax')];
      final h = build();
      expect(await h.handle('/join'), true);
      expect(pickerRequests.single, '');
      expect(joined, isEmpty);
    });

    test('/join <exact name> joins outright (case-insensitive)', () async {
      joinable = [_guest('Nora'), _guest('Pax')];
      final h = build();
      expect(await h.handle('/join nora'), true);
      expect(joined.single.name, 'Nora');
      expect(pickerRequests, isEmpty);
    });

    test('/join <unique substring> joins the single match', () async {
      joinable = [_guest('Nora Vance'), _guest('Pax')];
      final h = build();
      await h.handle('/join vance');
      expect(joined.single.name, 'Nora Vance');
      expect(pickerRequests, isEmpty);
    });

    test('/join <ambiguous substring> opens the picker pre-filtered', () async {
      joinable = [_guest('Nora'), _guest('Norbert')];
      final h = build();
      await h.handle('/join nor');
      expect(joined, isEmpty);
      expect(pickerRequests.single, 'nor');
    });

    test('/join <no match> opens the picker pre-filtered', () async {
      joinable = [_guest('Nora')];
      final h = build();
      await h.handle('/join zzz');
      expect(joined, isEmpty);
      expect(pickerRequests.single, 'zzz');
    });

    test('/join --full <exact name> routes to full join, not lite', () async {
      joinable = [_guest('Nora'), _guest('Pax')];
      final h = build();
      expect(await h.handle('/join --full nora'), true);
      expect(joinedFull.single.name, 'Nora');
      expect(joined, isEmpty); // not a lite guest
      expect(pickerRequests, isEmpty);
    });

    test('--full flag is positional-agnostic (name --full)', () async {
      joinable = [_guest('Nora Vance')];
      final h = build();
      await h.handle('/join vance --full');
      expect(joinedFull.single.name, 'Nora Vance');
      expect(joined, isEmpty);
    });

    test('/join --lite forces the lite path (default)', () async {
      joinable = [_guest('Nora')];
      final h = build();
      await h.handle('/join --lite nora');
      expect(joined.single.name, 'Nora');
      expect(joinedFull, isEmpty);
    });

    test(
      'bare /join --full opens the FULL picker (no exact name needed)',
      () async {
        joinable = [_guest('Nora'), _guest('Pax')];
        final h = build();
        await h.handle('/join --full');
        expect(
          joinedFull,
          isEmpty,
        ); // not joined yet — the picker is shown first
        expect(pickerRequests.single, ''); // browse the whole list
        expect(pickerFull.single, true); // ...as a FULL-join picker
        expect(systemMessages, isEmpty);
      },
    );

    test('/promote turns the scene into a full group', () async {
      guests = [_guest('Mara'), _guest('Pax')];
      final h = build();
      expect(await h.handle('/promote'), true);
      expect(scenePromotions, 1);
      expect(joinedFull, isEmpty);
    });

    test(
      '/join --full <ambiguous> opens the FULL picker pre-filtered',
      () async {
        joinable = [_guest('Nora'), _guest('Norbert')];
        final h = build();
        await h.handle('/join --full nor');
        expect(
          joinedFull,
          isEmpty,
        ); // not joined — picker shown to disambiguate
        expect(pickerRequests.single, 'nor'); // pre-filtered to the typed text
        expect(pickerFull.single, true);
      },
    );

    test('/join --full can target a PRESENT guest (promotion)', () async {
      // The guest is present (not in the joinable list), yet --full resolves it
      // because full's candidate pool includes present guests.
      guests = [_guest('Mara')];
      joinable = [_guest('Pax')];
      final h = build();
      expect(await h.handle('/join --full Mara'), true);
      expect(joinedFull.single.name, 'Mara');
      expect(joined, isEmpty);
    });

    test('/join (lite) cannot target a present guest', () async {
      // Lite's pool excludes present guests, so the same name finds no match
      // and falls back to the picker rather than re-adding a present guest.
      guests = [_guest('Mara')];
      joinable = [_guest('Pax')];
      final h = build();
      await h.handle('/join Mara');
      expect(joined, isEmpty);
      expect(joinedFull, isEmpty);
      expect(pickerRequests.single, 'Mara');
    });

    test('/scan outside a 1:1 chat is rejected before scanning', () async {
      final h = build(activeSet: false);
      expect(await h.handle('/scan'), true);
      expect(systemMessages.single, contains('1:1'));
      expect(castScans, 0);
    });

    test('/scan with no hit reports nothing found', () async {
      castScanFound = false;
      final h = build();
      expect(await h.handle('/scan'), true);
      expect(castScans, 1);
      expect(systemMessages.last, contains('No new recurring character'));
    });

    test('/scan with a hit stays silent (popup handles it)', () async {
      castScanFound = true;
      final h = build();
      expect(await h.handle('/scan'), true);
      expect(castScans, 1);
      // Only the "scanning…" status line; no "nothing found" follow-up.
      expect(systemMessages.length, 1);
      expect(systemMessages.single, contains('Scanning'));
    });

    test('/detect is an alias for /scan', () async {
      final h = build();
      expect(await h.handle('/detect'), true);
      expect(castScans, 1);
    });

    test('/speak with no guests surfaces a message, speaks nobody', () async {
      final h = build();
      expect(await h.handle('/speak Aria'), true);
      expect(systemMessages.single, contains('No scene guests'));
      expect(spoke, isEmpty);
    });

    test('/speak <exact name> forces that guest (case-insensitive)', () async {
      guests = [_guest('Aria'), _guest('Bram')];
      final h = build();
      expect(await h.handle('/speak bram'), true);
      expect(spoke.single.name, 'Bram');
    });

    test('/speak (no name) targets the most-recent guest', () async {
      guests = [_guest('Aria'), _guest('Bram')];
      final h = build();
      await h.handle('/speak');
      expect(spoke.single.name, 'Bram');
    });

    test('/speak <unique substring> forces the single match', () async {
      guests = [_guest('Aria the Brave'), _guest('Bram')];
      final h = build();
      await h.handle('/speak brave');
      expect(spoke.single.name, 'Aria the Brave');
    });

    test(
      '/speak <wrong name> lists the valid guests and speaks nobody',
      () async {
        guests = [_guest('Aria'), _guest('Bram')];
        final h = build();
        expect(await h.handle('/speak Zelda'), true);
        expect(spoke, isEmpty);
        expect(systemMessages.single, contains('Zelda'));
        expect(systemMessages.single, contains('Aria'));
        expect(systemMessages.single, contains('Bram'));
      },
    );

    test('/speak <ambiguous substring> lists guests, speaks nobody', () async {
      guests = [_guest('Mara'), _guest('Marcus')];
      final h = build();
      await h.handle('/speak mar');
      expect(spoke, isEmpty);
      expect(systemMessages.single, contains('more than one'));
    });

    test('/turn is an alias for /speak', () async {
      guests = [_guest('Aria')];
      final h = build();
      await h.handle('/turn Aria');
      expect(spoke.single.name, 'Aria');
    });

    // Drift guard: the "type /" helper panel advertises ChatCommandHandler
    // .commands — every one must actually be a recognized command.
    test('every advertised command in the registry is recognized', () async {
      guests = [_guest('Aria')];
      for (final c in ChatCommandHandler.commands) {
        expect(
          await build().handle('/${c.command}'),
          true,
          reason: '/${c.command} is advertised but not handled',
        );
      }
    });

    group('/afk', () {
      test('bare /afk enables with defaults + confirms', () async {
        final h = build();
        expect(await h.handle('/afk'), true);
        expect(afkCalls.single, (true, null, null));
        expect(systemMessages.single, contains('AFK on'));
      });

      test('/afk off disables', () async {
        final h = build();
        await h.handle('/afk off');
        expect(afkCalls.single, (false, null, null));
        expect(systemMessages.single.toLowerCase(), contains('off'));
      });

      test('/afk --messages 3 --time 5m parses count + minutes', () async {
        await build().handle('/afk --messages 3 --time 5m');
        expect(afkCalls.single, (true, 3, 300));
      });

      test('/afk --time 90s parses seconds', () async {
        await build().handle('/afk --time 90s');
        expect(afkCalls.single, (true, null, 90));
      });

      test('out-of-range values are clamped to the settings ranges', () async {
        await build().handle('/afk --messages 99 --time 9000s');
        expect(afkCalls.single, (true, 10, 300)); // 1–10 messages, 30–300s
      });

      test('invalid time reports an error and does not enable', () async {
        final h = build();
        await h.handle('/afk --time soon');
        expect(afkCalls, isEmpty);
        expect(systemMessages.single, startsWith('⚠'));
      });
    });

    group('/image', () {
      test('dispatches to the injected image flow with raw args', () async {
        expect(await build().handle('/image a dragon over the castle'), true);
        expect(imageCalls.single, 'a dragon over the castle');
      });

      test('bare /image dispatches with empty args', () async {
        expect(await build().handle('/image'), true);
        expect(imageCalls.single, '');
      });

      test('aliases /img, /sd, /imagine all dispatch', () async {
        await build().handle('/img me');
        await build().handle('/sd char');
        await build().handle('/imagine raw neon city');
        expect(imageCalls, ['me', 'char', 'raw neon city']);
      });
    });
  });
}
