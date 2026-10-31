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

// The "After Dark" group and the Growth Rings row — both restored to match the
// approved Porch Life sketch (artifact 3bee9e58).
//
// The sketch is explicit that the adult group is "shown only when 18+ themes
// are enabled". We had shipped that row inside "The Engine", visible to
// everyone, so a user who had never asked for adult content still saw an 18+
// switch. Absent is the requirement here, not dimmed — the tab's gating idiom
// (dead switch + dim) is for an unmet DEPENDENCY, which is a different thing
// from content someone has not opted into.
//
// The seed is the subtle part and is tested below: adultThemesEnabled has no
// stored value until someone chooses one, and until then it tracks
// nsfwCooldownDefault. Without that, shipping this group would have hidden the
// Afterglow switch from every existing user who was already running it.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/one_shot_eval_row.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';
import 'package:front_porch_ai/ui/settings/widgets/feature_row.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// Real [RealismSettings] behind the storage fake so the seed logic under test
/// is the production one. SharedPreferences null ⇒ writes are no-ops and
/// nothing is ever "explicitly chosen" unless this test chooses it.
class _AdultStorage extends FakeStorageService {
  _AdultStorage() {
    _realism.initializeBase(null, notifyListeners);
  }

  final RealismSettings _realism = RealismSettings();

  @override
  RealismSettings get realismSettings => _realism;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_AdultStorage> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _AdultStorage();
    final chat = FakeChatService();
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: const MaterialApp(home: Scaffold(body: PorchLifeTab())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    return storage;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('with 18+ off, the adult group is absent — not merely dimmed', (
    tester,
  ) async {
    final storage = await pump(tester);
    expect(
      storage.realismSettings.adultThemesEnabled,
      isFalse,
      reason: 'nothing has opted in, and Afterglow is off, so the seed is off',
    );

    expect(
      find.text('After Dark'),
      findsNothing,
      reason:
          'the sketch says this group is shown ONLY when 18+ themes are '
          'enabled — a user who never asked for adult content should not be '
          'shown an adult switch at all',
    );
    expect(find.text('Afterglow'), findsNothing);
  });

  testWidgets('turning 18+ on reveals the group and its row', (tester) async {
    final storage = await pump(tester);
    await storage.realismSettings.setAdultThemesEnabled(true);
    await settle(tester);

    final scrollable = find.byType(Scrollable).first;
    final group = find.text('After Dark');
    await tester.scrollUntilVisible(group, 300, scrollable: scrollable);
    expect(group, findsOneWidget);

    expect(
      find.text('shown only when 18+ themes are on'),
      findsOneWidget,
      reason: 'the group subtitle should say why it is conditional',
    );
    expect(find.text('Afterglow'), findsOneWidget);
  });

  testWidgets(
    'an existing Afterglow user keeps their switch without opting in again',
    (tester) async {
      // The regression this guards: shipping the group with a plain `false`
      // default would have hidden Afterglow from everyone already running it,
      // stripping a setting they had deliberately turned on.
      final storage = await pump(tester);
      await storage.realismSettings.setNsfwCooldownDefault(true);
      await settle(tester);

      expect(
        storage.realismSettings.adultThemesEnabled,
        isTrue,
        reason:
            'with no explicit choice stored, 18+ visibility tracks whether '
            'an adult feature is actually in use',
      );
      final scrollable = find.byType(Scrollable).first;
      final row = find.text('Afterglow');
      await tester.scrollUntilVisible(row, 300, scrollable: scrollable);
      expect(row, findsOneWidget);
    },
  );

  testWidgets('an explicit choice overrides the seed', (tester) async {
    final storage = await pump(tester);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await storage.realismSettings.setAdultThemesEnabled(false);
    await settle(tester);

    expect(
      storage.realismSettings.adultThemesEnabled,
      isFalse,
      reason: 'once the user has chosen, the seed must stop speaking for them',
    );
    expect(find.text('After Dark'), findsNothing);
  });

  // 2026-10-24: the chat sidebar gear carried an old per-chat "NSFW
  // Enhancements" switch that overrode Porch Life, so Afterglow turned on
  // here did nothing for an existing chat. Porch Life is the one switch.
  // 2026-10-25: the gear itself is gone. Needs is set on the card, and
  // One-Shot Eval moved above the tool-calling pill, so Character State
  // carries no settings switch but Afterglow's own, on the line it controls.
  // The gear sat in the header code both modes share; the fake cannot build
  // group mode, so 1:1 pins it.
  testWidgets('Character State has no gear; Needs and Afterglow each have '
      'their own line', (tester) async {
    final storage = _AdultStorage();
    final chat = FakeChatService();
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });
    await storage.realismSettings.setNsfwCooldownDefault(true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  OneShotEvalRow(chat: chat),
                  CharacterStateGroup(
                    chat: chat,
                    isGroup: false,
                    initiallyExpanded: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('One-Shot Eval'), findsOneWidget, reason: 'baseline');
    expect(find.byTooltip('Simulation settings'), findsNothing);
    expect(find.text('Needs Simulation'), findsNothing);
    expect(find.textContaining('NSFW'), findsNothing);
    expect(
      find.text('Afterglow'),
      findsOneWidget,
      reason: "Porch Life allows it: this chat's own switch, on its line",
    );
    expect(
      find.byType(Switch),
      findsNWidgets(3),
      reason:
          'the Realism master switch, the Needs line and the Afterglow line',
    );
  });

  testWidgets('Growth Rings is a row on the tab, per the sketch', (
    tester,
  ) async {
    await pump(tester);
    final scrollable = find.byType(Scrollable).first;
    final row = find.text('Growth Rings');
    await tester.scrollUntilVisible(row, 300, scrollable: scrollable);
    expect(
      row,
      findsOneWidget,
      reason:
          'the sketch lists Growth Rings under Memory & Heart; it was '
          'missing because its global (characterEvolutionEnabled) already '
          'existed but had never been surfaced here',
    );
    expect(
      find.textContaining('rings, not rewrites'),
      findsOneWidget,
      reason: "the sketch's own copy for this row",
    );
  });

  group("Character State's Afterglow line", () {
    Future<_SwitchChat> mount(
      WidgetTester tester, {
      required bool allowed,
      required bool on,
    }) async {
      final storage = _AdultStorage();
      final chat = _SwitchChat();
      addTearDown(() {
        storage.dispose();
        chat.dispose();
      });
      await storage.realismSettings.setNsfwCooldownDefault(allowed);
      chat.nsfwService.seedFromV2OrExt(nsfwCooldownEnabled: on);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<ChatService>.value(value: chat),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CharacterStateGroup(
                  chat: chat,
                  isGroup: false,
                  initiallyExpanded: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return chat;
    }

    Finder afterglowSwitch() => find.descendant(
      of: find
          .ancestor(of: find.text('Afterglow'), matching: find.byType(Row))
          .first,
      matching: find.byType(Switch),
    );

    testWidgets('Porch Life Afterglow off: no line and no switch', (
      tester,
    ) async {
      await mount(tester, allowed: false, on: true);
      expect(find.text('Afterglow'), findsNothing);
      expect(
        find.byType(Switch),
        findsNWidgets(2),
        reason: 'the Realism master switch and the Needs line',
      );
    });

    testWidgets("the switch shows this chat's own choice, and flipping it "
        'asks the chat', (tester) async {
      final chat = await mount(tester, allowed: true, on: false);
      expect(tester.widget<Switch>(afterglowSwitch()).value, isFalse);
      expect(
        find.textContaining('Lust:'),
        findsNothing,
        reason: 'off: no Lust',
      );

      await tester.tap(afterglowSwitch());
      await tester.pump();
      expect(chat.asked, [true]);
    });
  });
  testWidgets('turning Porch Life Afterglow on asks about the chats that '
      'have it off, and Done with its switch on turns it on in them', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = AppDatabase.forTesting(sameIsolate: true);
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(
      () => db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 'one-off',
              characterId: const Value('char-a'),
              nsfwCooldownEnabled: const Value(false),
            ),
          ),
    );
    final storage = _AdultStorage();
    // The open chat has its switch off too (this fake's stored flag).
    final chat = _SwitchChat();
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });
    await storage.realismSettings.setAdultThemesEnabled(true);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: const MaterialApp(home: Scaffold(body: PorchLifeTab())),
      ),
    );
    await settle(tester);

    // The count and the switch-on run against the database: real I/O the
    // test clock does not drive. A read issued after the switch-on lands only
    // once it has.
    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 300 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    await tester.scrollUntilVisible(
      find.text('Afterglow'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // As its switch does (the row is greyed while this fake's engine is off).
    tester
        .widget<FeatureRow>(find.widgetWithText(FeatureRow, 'Afterglow'))
        .onChanged(true);
    final question = find.text('Turn it on in those 2 chats too');
    await until(() => question.evaluate().isNotEmpty);
    expect(question, findsOneWidget);
    expect(find.text('Afterglow is on'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Turn it on in those 2 chats too'),
    );
    await tester.pump();
    await tester.tap(find.text('Done'));
    bool? stored;
    for (var i = 0; i < 100 && stored != true; i++) {
      bool? read;
      db
          .customSelect(
            "SELECT nsfw_cooldown_enabled AS n FROM sessions WHERE id = 'one-off'",
          )
          .getSingle()
          .then((r) => read = r.read<bool>('n'));
      await until(() => read != null);
      stored = read;
    }
    expect(stored, isTrue, reason: 'the chat that had it off has it on');
    expect(chat.asked, [true], reason: 'the open chat is switched live');
  });
  group("Character State's Needs line", () {
    Future<_NeedsChat> mount(
      WidgetTester tester, {
      required bool allowed,
    }) async {
      final storage = _AdultStorage();
      final chat = _NeedsChat();
      addTearDown(() {
        storage.dispose();
        chat.dispose();
      });
      await storage.realismSettings.setNeedsSimDefault(allowed);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<ChatService>.value(value: chat),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CharacterStateGroup(
                  chat: chat,
                  isGroup: false,
                  initiallyExpanded: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return chat;
    }

    Switch needsSwitch(WidgetTester tester) => tester.widget<Switch>(
      find.descendant(
        of: find.byType(NeedsLine),
        matching: find.byType(Switch),
      ),
    );

    testWidgets("its switch shows this chat's own choice, and flipping it asks "
        'the chat', (tester) async {
      final chat = await mount(tester, allowed: true);
      expect(needsSwitch(tester).value, isTrue, reason: "the chat's own");
      expect(needsSwitch(tester).onChanged, isNotNull);
      needsSwitch(tester).onChanged!(false);
      expect(chat.asked, [false]);
    });

    testWidgets('Porch Life Needs off: it greys out and says where to look, '
        "keeping the chat's choice", (tester) async {
      await mount(tester, allowed: false);
      expect(
        find.byType(NeedsLine),
        findsOneWidget,
        reason: 'greyed, not hidden',
      );
      expect(needsSwitch(tester).onChanged, isNull);
      expect(needsSwitch(tester).value, isTrue, reason: "the chat's choice");
      expect(
        find.text(
          "Off in Porch Life, so no chat runs Needs. This chat's choice is kept.",
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('turning Porch Life Needs on asks about the chats that have it '
      'off, and Done with its switch on turns it on in them', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = AppDatabase.forTesting(sameIsolate: true);
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(
      () => db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 'lived-in',
              characterId: const Value('char-a'),
              needsSimEnabled: const Value(false),
              needsVector: const Value('{"hunger":70}'),
            ),
          ),
    );
    final storage = _AdultStorage();
    final chat = FakeChatService();
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });
    await storage.realismSettings.setNeedsSimDefault(false);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: const MaterialApp(home: Scaffold(body: PorchLifeTab())),
      ),
    );
    await settle(tester);
    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 300 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    // As its switch does (the row is greyed while this fake's engine is off).
    tester
        .widget<FeatureRow>(find.widgetWithText(FeatureRow, 'Needs'))
        .onChanged(true);
    final question = find.text('Turn it on in that chat too');
    await until(() => question.evaluate().isNotEmpty);
    expect(find.text('Needs is on'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Turn it on in that chat too'),
    );
    await tester.pump();
    await tester.tap(find.text('Done'));
    bool? stored;
    for (var i = 0; i < 100 && stored != true; i++) {
      bool? read;
      db
          .customSelect(
            "SELECT needs_sim_enabled AS n FROM sessions WHERE id = 'lived-in'",
          )
          .getSingle()
          .then((r) => read = r.read<bool>('n'));
      await until(() => read != null);
      stored = read;
    }
    expect(stored, isTrue, reason: 'the chat that had it off has it on');
  });
}

/// Records what the Afterglow line asks of the chat.
class _SwitchChat extends FakeChatService {
  final asked = <bool>[];

  @override
  Future<void> setAfterglowEnabled(bool enabled) async => asked.add(enabled);
}

class _NeedsChat extends FakeChatService {
  final asked = <bool>[];

  @override
  Future<void> setNeedsSimEnabled(bool enabled) async => asked.add(enabled);
}
