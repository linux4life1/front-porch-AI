// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The clock-off line (docs/design/needs-on-the-clock.md, "Clock off"): under
// every Needs switch, only while Porch Life's Passage of Time is off, so bars
// that sit still do not read as broken. The phone twin is pinned in
// web_ui/src/components/realism/NeedsClockOffNote.test.tsx.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/greeting_seed_form.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

const _line =
    'With Passage of time off, needs change only when the story says so.';

class _GroupChat extends FakeChatService {
  _GroupChat(this._group, this._chars);

  final GroupChat _group;
  final List<CharacterCard> _chars;

  @override
  GroupChat? get activeGroup => _group;

  @override
  List<CharacterCard> get groupCharacters => _chars;
}

Widget _needsForm() => NeedsFormSection(
  enabled: true,
  onEnabledChanged: (_) {},
  enjoysLowHygiene: false,
  onEnjoysLowHygieneChanged: (_) {},
  baselineHunger: 70,
  onBaselineHungerChanged: (_) {},
  baselineBladder: 55,
  onBaselineBladderChanged: (_) {},
  baselineEnergy: 80,
  onBaselineEnergyChanged: (_) {},
  baselineSocial: 45,
  onBaselineSocialChanged: (_) {},
  baselineFun: 65,
  onBaselineFunChanged: (_) {},
  baselineHygiene: 75,
  onBaselineHygieneChanged: (_) {},
  baselineComfort: 60,
  onBaselineComfortChanged: (_) {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeStorageService storage;
  late FakeChatService chat;
  _GroupChat? groupChat;

  setUp(() {
    storage = FakeStorageService();
    chat = FakeChatService();
  });

  tearDown(() {
    storage.dispose();
    chat.dispose();
    groupChat?.dispose();
    groupChat = null;
  });

  Future<void> pumpWith(
    WidgetTester tester,
    Widget body, {
    bool withStorage = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: body)),
    );
    await tester.pumpWidget(
      withStorage
          ? MultiProvider(
              providers: [
                ChangeNotifierProvider<StorageService>.value(value: storage),
                ChangeNotifierProvider<ChatService>.value(value: chat),
              ],
              child: app,
            )
          : app,
    );
    await tester.pump();
  }

  testWidgets('chat gear: under Needs Simulation only while the clock is '
      'off, and it follows the switch live', (tester) async {
    await pumpWith(tester, CharacterStateSettings(chat: chat, isGroup: false));
    expect(storage.realismSettings.passageOfTimeDefault, isTrue);
    expect(find.text(_line), findsNothing);

    await storage.realismSettings.setPassageOfTimeDefault(false);
    await tester.pump();
    expect(find.text(_line), findsOneWidget);
    final y = tester.getTopLeft(find.text(_line)).dy;
    expect(y, greaterThan(tester.getTopLeft(find.text('Needs Simulation')).dy));
    expect(y, lessThan(tester.getTopLeft(find.text('One-Shot Eval')).dy));

    await storage.realismSettings.setPassageOfTimeDefault(true);
    await tester.pump();
    expect(find.text(_line), findsNothing);
  });

  testWidgets('Porch Life: switching Passage of Time off shows the line on '
      'the Needs row, whether or not Needs is on', (tester) async {
    await storage.realismSettings.setRealismDefault(true);
    // Tall enough that the Needs row and the clock row are both on screen, so
    // tapping the clock never scrolls the Needs row out of the tree.
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

    final needsRow = find.ancestor(
      of: find.text('Needs'),
      matching: find.byType(FeatureRow),
    );
    expect(needsRow, findsOneWidget);
    expect(find.text(_line), findsNothing);

    Future<void> tapClock() async {
      final clockRow = find.ancestor(
        of: find.text('Passage of Time'),
        matching: find.byType(FeatureRow),
      );
      await tester.tap(
        find.descendant(of: clockRow, matching: find.byType(Switch)),
      );
      await tester.pump();
    }

    await tapClock();
    expect(storage.realismSettings.passageOfTimeDefault, isFalse);
    expect(
      find.descendant(of: needsRow, matching: find.text(_line)),
      findsOneWidget,
    );

    await storage.realismSettings.setNeedsSimDefault(false);
    await tester.pump();
    expect(
      find.descendant(of: needsRow, matching: find.text(_line)),
      findsOneWidget,
    );

    await tapClock();
    expect(storage.realismSettings.passageOfTimeDefault, isTrue);
    expect(find.text(_line), findsNothing);
  });

  group('every other Needs switch reads the live clock', () {
    final sites = <String, Widget Function()>{
      'card Needs form (editor and creators)': _needsForm,
      'greeting seed Needs block': () => GreetingSeedForm(
        seed: const GreetingRealismSeed(),
        onChanged: (_) {},
      ),
      'group Needs tab': () => GroupNeedsTab(
        chatService: groupChat = _GroupChat(
          GroupChat(id: 'g1', name: 'The Stoop'),
          [CharacterCard(name: 'Aerin')],
        ),
      ),
    };

    sites.forEach((site, build) {
      testWidgets('$site: shown with the clock off, hidden with it on', (
        tester,
      ) async {
        await storage.realismSettings.setPassageOfTimeDefault(false);
        await pumpWith(tester, build());
        expect(find.text(_line), findsOneWidget);

        await storage.realismSettings.setPassageOfTimeDefault(true);
        await tester.pump();
        expect(find.text(_line), findsNothing);
      });

      testWidgets('$site: pumped without storage, the clock reads as on', (
        tester,
      ) async {
        await pumpWith(tester, build(), withStorage: false);
        expect(find.text(_line), findsNothing);
      });
    });
  });
}
