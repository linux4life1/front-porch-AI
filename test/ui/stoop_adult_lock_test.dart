// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// The Stoop share wizard's 18+ lock (`stoopForcesAdult`).
//
// Two ways this rule can be got wrong, and both are silent:
//
//  1. Testing for the KEY. Every Front Porch card emits `intimate_preferences`
//     unconditionally (character_card.dart), empty lists included — so a key
//     check tags the ENTIRE catalogue 18+ and nobody can share anything as
//     all-ages again. That is the first test below.
//  2. Scanning only the card ROOT. A group's preferences live per member, never
//     at the group root, so a root-only scan is dodged by shipping the very
//     character you meant to catch inside a two-member group.
//
// The input is a stranger's upload, so the wrong-typed cases are the point
// rather than padding: one bad field must cost that field, not throw.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/repository/repository.dart';

void main() {
  CharacterCard solo({
    List<String> into = const [],
    List<String> not = const [],
  }) => CharacterCard(
    name: 'Test',
    frontPorchExtensions: FrontPorchExtensions(
      intimateInto: into,
      intimateNotInto: not,
    ),
  );

  GroupMember member(Map<String, dynamic>? prefs) => GroupMember(
    id: 'm1',
    groupId: 'g1',
    name: 'Member',
    frontPorchExtensions: {
      'realism_engine': {
        'ambitions': const ['open a bakery'],
        'intimate_preferences': ?prefs, // null = the key is absent entirely
      },
    },
  );

  group('stoopForcesAdult — solo', () {
    test('an empty intimate_preferences pair does NOT force 18+', () {
      // The catalogue-wide false positive. Every card has the key.
      expect(stoopForcesAdult(solo(), null), isFalse);
    });

    test('a card with no Front Porch extensions at all does not force', () {
      expect(stoopForcesAdult(CharacterCard(name: 'Bare'), null), isFalse);
      expect(stoopForcesAdult(null, null), isFalse);
    });

    test('one non-blank phrase in `into` forces 18+', () {
      expect(stoopForcesAdult(solo(into: ['slow mornings']), null), isTrue);
    });

    test('`not_into` alone forces 18+ just the same', () {
      expect(stoopForcesAdult(solo(not: ['being rushed']), null), isTrue);
    });

    test('whitespace-only phrases are not preferences', () {
      expect(stoopForcesAdult(solo(into: ['   ', '\n\t']), null), isFalse);
    });
  });

  group('stoopForcesAdult — group cast', () {
    test('a cast with no preferences does not force', () {
      expect(stoopForcesAdult(null, [member(null), member({})]), isFalse);
      expect(
        stoopForcesAdult(null, [
          member({'into': const [], 'not_into': const []}),
        ]),
        isFalse,
      );
    });

    test('ONE member with a preference forces the whole group 18+', () {
      // The evasion route: hide the 18+ character behind a clean first member.
      expect(
        stoopForcesAdult(null, [
          member(null),
          member({
            'into': const ['candlelight'],
          }),
        ]),
        isTrue,
      );
    });

    test('an empty cast, or one still loading, does not force', () {
      expect(stoopForcesAdult(null, const []), isFalse);
      expect(stoopForcesAdult(null, null), isFalse);
    });
  });

  group('stoopForcesAdult — hostile input', () {
    test('wrong-typed fields cost that field, not an exception', () {
      expect(
        stoopForcesAdult(null, [
          member({'into': 'a string, not a list', 'not_into': 42}),
        ]),
        isFalse,
      );
    });

    test('a wrong-typed intimate_preferences or realism_engine is skipped', () {
      expect(
        stoopForcesAdult(null, [
          GroupMember(
            id: 'm2',
            groupId: 'g1',
            name: 'Broken',
            frontPorchExtensions: const {
              'realism_engine': {'intimate_preferences': 'nope'},
            },
          ),
          GroupMember(
            id: 'm3',
            groupId: 'g1',
            name: 'Broken too',
            frontPorchExtensions: const {'realism_engine': 'nope'},
          ),
          GroupMember(id: 'm4', groupId: 'g1', name: 'No extensions'),
        ]),
        isFalse,
      );
    });

    test('non-string entries are ignored, real ones still count', () {
      expect(
        stoopForcesAdult(null, [
          member({
            'into': const [1, null, true],
          }),
        ]),
        isFalse,
      );
      expect(
        stoopForcesAdult(null, [
          member({
            'into': const [1, 'quiet evenings'],
          }),
        ]),
        isTrue,
      );
    });
  });

  // ── The rule read off the BUILT group card ────────────────────────────────
  //
  // The wizard used to publish the group's flag from a SEPARATE, un-awaited
  // read of group_members — a query that swallows its own errors and answers
  // `[]`, which is indistinguishable from a clean cast. A hiccup there shipped
  // nsfw:false attached to a card that plainly carried intimate preferences.
  // The publish path now decides from the card object it already awaited, so
  // these guard the "same bytes you publish" rule.
  group('stoopGroupCardForcesAdult — the published card decides', () {
    CharacterCard cast({List<String> into = const []}) => CharacterCard(
      name: 'Cast',
      frontPorchExtensions: FrontPorchExtensions(intimateInto: into),
    );

    test('a clean cast does not force', () {
      expect(
        stoopGroupCardForcesAdult(
          GroupCard(
            name: 'G',
            members: [cast(), cast()],
            turnOrder: 'roundRobin',
          ),
        ),
        isFalse,
      );
    });

    test('one member with a preference forces the card 18+', () {
      expect(
        stoopGroupCardForcesAdult(
          GroupCard(
            name: 'G',
            members: [
              cast(),
              cast(into: ['candlelight']),
            ],
            turnOrder: 'roundRobin',
          ),
        ),
        isTrue,
      );
    });

    test('raw_member_data alone still forces (both cast lists travel)', () {
      // The importer prefers raw_member_data, so a scan of `members` alone
      // could be dodged by a card whose two lists disagree.
      expect(
        stoopGroupCardForcesAdult(
          GroupCard(
            name: 'G',
            members: [cast()],
            rawMemberData: [
              cast(into: ['rain on the roof']).toJson(),
            ],
            turnOrder: 'roundRobin',
          ),
        ),
        isTrue,
      );
    });

    test('an empty / preference-free raw block does not force', () {
      expect(
        stoopGroupCardForcesAdult(
          GroupCard(
            name: 'G',
            members: [cast()],
            rawMemberData: [
              cast().toJson(),
              <String, dynamic>{'name': 'No extensions at all'},
              <String, dynamic>{'extensions': 'wrong type entirely'},
            ],
            turnOrder: 'roundRobin',
          ),
        ),
        isFalse,
      );
    });
  });

  _wizardTests();
}

// ───────────────────────────────────────────────────────────────────────────
// The wizard's own wiring, driven through the real widget.
//
// The rule getter above can be perfectly correct while the PAGE still
// publishes the wrong flag, and that is exactly what happened: `_nsfw` was set
// to true by a forced pick and never reset, so pick-dirty → Back →
// pick-clean published a spotless card as 18+ (hidden from everyone who has
// not opted in). A unit test of the rule cannot see that. These tap the real
// tiles and the real Back/Next buttons.
// ───────────────────────────────────────────────────────────────────────────

/// A 1×1 PNG. The pick grid renders `Image.file`, so the avatars must be real
/// files on disk or the widget tree throws while painting.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class _FakeCharacterRepository extends ChangeNotifier
    implements CharacterRepository {
  _FakeCharacterRepository(this._characters);
  final List<CharacterCard> _characters;

  @override
  List<CharacterCard> get characters => List.unmodifiable(_characters);
  @override
  bool get isLoading => false;
  @override
  int get coverEpoch => 0;
  @override
  Future<void> loadCharacters() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFolderService extends ChangeNotifier implements FolderService {
  @override
  List<CharacterFolder> get folders => const [];
  @override
  List<CharacterFolder> getSubfolders(String? parentId) => const [];
  @override
  CharacterFolder? getFolderForCharacter(String filename) => null;
  @override
  CharacterFolder? getFolderForGroup(String groupId) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGroupChatRepository extends ChangeNotifier
    implements GroupChatRepository {
  _FakeGroupChatRepository([this._groups = const []]);
  final List<GroupChat> _groups;

  /// Held open so a test can inspect the wizard WHILE the cast is unknown —
  /// the window in which the switch used to claim "unlocked, all-ages".
  final membersReady = Completer<List<GroupMember>>();

  @override
  List<GroupChat> get groups => List.unmodifiable(_groups);
  @override
  Future<List<GroupMember>> getMembersForGroup(String groupId) =>
      membersReady.future;
  @override
  Future<List<File>> getMemberAvatarFiles(String groupId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWorldRepository extends ChangeNotifier implements WorldRepository {
  _FakeWorldRepository([this._worlds = const []]);
  final List<World> _worlds;

  @override
  List<World> get worlds => List.unmodifiable(_worlds);
  @override
  List<World> get placeWorlds => List.unmodifiable(_worlds);
  @override
  bool get isLoading => false;
  @override
  Map<String, dynamic> fpWorldJson(World world) => {
    'name': world.name,
    'description': world.description,
    'biome': const <String, dynamic>{},
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _wizardTests() {
  late Directory tmp;
  late CharacterCard dirty;
  late CharacterCard clean;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('stoop_adult_lock');
    File('${tmp.path}/dana.png').writeAsBytesSync(_pngBytes);
    File('${tmp.path}/clive.png').writeAsBytesSync(_pngBytes);
    dirty = CharacterCard(
      name: 'Dirty Dana',
      description: 'She keeps the porch light on.',
      imagePath: '${tmp.path}/dana.png',
      frontPorchExtensions: FrontPorchExtensions(
        intimateInto: const ['candlelight'],
      ),
    );
    clean = CharacterCard(
      name: 'Clean Clive',
      description: 'He mows the lawn at dawn.',
      imagePath: '${tmp.path}/clive.png',
      frontPorchExtensions: FrontPorchExtensions(),
    );
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpWizard(
    WidgetTester tester, {
    List<CharacterCard> cards = const [],
    _FakeGroupChatRepository? groups,
    List<World> worlds = const [],
  }) async {
    // A desktop-sized surface. The Content step's completeness panel is taller
    // than the default 800×600 test window, which would leave the switch itself
    // unbuilt below the fold and every assertion below unable to find it.
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthState>(create: (_) => AuthState()),
          ChangeNotifierProvider<CharacterRepository>(
            create: (_) => _FakeCharacterRepository(cards),
          ),
          ChangeNotifierProvider<GroupChatRepository>(
            create: (_) => groups ?? _FakeGroupChatRepository(),
          ),
          ChangeNotifierProvider<FolderService>(
            create: (_) => _FakeFolderService(),
          ),
          ChangeNotifierProvider<WorldRepository>(
            create: (_) => _FakeWorldRepository(worlds),
          ),
        ],
        child: const MaterialApp(home: StoopUploadPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// Pick → Details → Content, landing on the step that carries the switch.
  Future<void> toContent(WidgetTester tester, String pick) async {
    await tapText(tester, pick);
    await tapText(tester, 'Next');
    await tapText(tester, 'Next');
  }

  Future<void> backToPick(WidgetTester tester) async {
    await tapText(tester, 'Back');
    await tapText(tester, 'Back');
  }

  Finder adultSwitchFinder() => find.descendant(
    of: find.byType(StoopAdultSwitch),
    matching: find.byType(SwitchListTile),
  );

  SwitchListTile adultSwitch(WidgetTester tester) =>
      tester.widget<SwitchListTile>(adultSwitchFinder());

  group('the share wizard\'s 18+ flag', () {
    testWidgets('a forced tick is WITHDRAWN when a clean card is picked next', (
      tester,
    ) async {
      await pumpWizard(tester, cards: [dirty, clean]);

      await toContent(tester, 'Dirty Dana');
      expect(
        adultSwitch(tester).value,
        isTrue,
        reason: 'forced on by the rule',
      );
      expect(adultSwitch(tester).onChanged, isNull, reason: 'locked');
      expect(find.byType(StoopAdultLockBanner), findsOneWidget);

      await backToPick(tester);
      await toContent(tester, 'Clean Clive');

      // The bug: the banner and the lock went away but the `true` stayed,
      // publishing a card with zero intimate preferences as 18+.
      expect(find.byType(StoopAdultLockBanner), findsNothing);
      expect(
        adultSwitch(tester).onChanged,
        isNotNull,
        reason: 'unlocked again',
      );
      expect(adultSwitch(tester).value, isFalse);
    });

    testWidgets('the author\'s own tick SURVIVES a force that comes and goes', (
      tester,
    ) async {
      await pumpWizard(tester, cards: [dirty, clean]);

      // Deliberately marked 18+ by hand on a card the rule says nothing about.
      await toContent(tester, 'Clean Clive');
      await tester.tap(adultSwitchFinder());
      await tester.pumpAndSettle();
      expect(adultSwitch(tester).value, isTrue);

      // A forced pick and back again must not consume the author's decision.
      await backToPick(tester);
      await toContent(tester, 'Dirty Dana');
      expect(adultSwitch(tester).value, isTrue);
      await backToPick(tester);
      await toContent(tester, 'Clean Clive');

      expect(
        adultSwitch(tester).value,
        isTrue,
        reason: 'withdrawing the rule must not undo a human tick',
      );
      expect(adultSwitch(tester).onChanged, isNotNull);
    });

    testWidgets('a PLACE picked after a forced card is not published 18+', (
      tester,
    ) async {
      // A place has no cast at all, so nothing can force it — but the world
      // applier used to leave the previous pick's forced `true` in place.
      final place = World(
        name: 'Wisteria Landing',
        description: 'A jetty, a heron, and the smell of creosote.',
        lorebook: Lorebook(entries: const []),
        coverImage: 'data:image/png;base64,${base64Encode(_pngBytes)}',
      );
      await pumpWizard(tester, cards: [dirty], worlds: [place]);

      await toContent(tester, 'Dirty Dana');
      expect(adultSwitch(tester).value, isTrue);

      await backToPick(tester);
      await toContent(tester, 'Wisteria Landing');

      expect(find.byType(StoopAdultLockBanner), findsNothing);
      expect(adultSwitch(tester).value, isFalse);
      expect(adultSwitch(tester).onChanged, isNotNull);
    });

    testWidgets('a group whose cast is still loading says so instead of "off"', (
      tester,
    ) async {
      final repo = _FakeGroupChatRepository([
        GroupChat(
          id: 'g1',
          name: 'The Tuesday Club',
          scenario: 'They meet on the porch every Tuesday.',
        ),
      ]);
      await pumpWizard(tester, cards: [clean], groups: repo);

      await toContent(tester, 'The Tuesday Club');
      // Before the fix these first frames rendered an unlocked, OFF switch —
      // confidently the opposite of the truth — and then snapped.
      expect(
        adultSwitch(tester).onChanged,
        isNull,
        reason: 'held while unknown',
      );
      expect(
        find.textContaining('Checking who’s in this group'),
        findsOneWidget,
      );

      repo.membersReady.complete([
        GroupMember(
          id: 'm1',
          groupId: 'g1',
          name: 'Rosalie',
          frontPorchExtensions: const {
            'realism_engine': {
              'intimate_preferences': {
                'into': ['being read to'],
              },
            },
          },
        ),
      ]);
      await tester.pumpAndSettle();

      expect(adultSwitch(tester).value, isTrue);
      expect(adultSwitch(tester).onChanged, isNull, reason: 'now locked on');
      expect(find.byType(StoopAdultLockBanner), findsOneWidget);

      // And the group's force is withdrawn like any other when the pick moves.
      await backToPick(tester);
      await toContent(tester, 'Clean Clive');
      expect(adultSwitch(tester).value, isFalse);
    });
  });
}
