// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group Settings → Needs must author Pace and per-need on/off the same way
// 1:1 editors do. Reset already clears needsPace / needsOff on the card ext;
// without these controls the user cannot set them on this surface.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _NeedsChat extends FakeChatService {
  _NeedsChat(this._group, this._chars);

  final GroupChat _group;
  final List<CharacterCard> _chars;

  @override
  GroupChat? get activeGroup => _group;

  @override
  List<CharacterCard> get groupCharacters => _chars;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Group Needs tab sets Pace and per-need on/off on the member card',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final member = CharacterCard(
        name: 'Aerin',
        frontPorchExtensions: FrontPorchExtensions(
          needsPace: 'normal',
          needsOff: const [],
        ),
      );
      final chat = _NeedsChat(GroupChat(id: 'g1', name: 'The Stoop'), [member]);
      addTearDown(chat.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GroupNeedsTab(chatService: chat)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Baselines & Decay'), findsNothing);
      expect(find.textContaining('per-turn decay'), findsNothing);
      expect(find.textContaining('tick rate'), findsNothing);

      final pace = find.byType(SegmentedButton<String>);
      expect(pace, findsOneWidget);
      expect(
        tester.widget<SegmentedButton<String>>(pace).onSelectionChanged,
        isNotNull,
        reason: 'Pace must be live — Reset already writes needsPace',
      );

      await tester.ensureVisible(find.text('Fast'));
      await tester.tap(find.text('Fast'));
      await tester.pumpAndSettle();

      expect(member.frontPorchExtensions!.needsPace, 'fast');
      expect(tester.widget<SegmentedButton<String>>(pace).selected, {'fast'});

      final bladderSwitch = find.descendant(
        of: find.widgetWithText(Column, 'Bladder').first,
        matching: find.byType(Switch),
      );
      expect(bladderSwitch, findsOneWidget);
      expect(
        tester.widget<Switch>(bladderSwitch).onChanged,
        isNotNull,
        reason: 'Per-need on/off must be live — Reset already writes needsOff',
      );

      await tester.ensureVisible(bladderSwitch);
      await tester.tap(bladderSwitch);
      await tester.pumpAndSettle();

      expect(member.frontPorchExtensions!.needsOff, contains('bladder'));
    },
  );

  // The SOW decision: Needs greys out with "Off in Porch Life", as the 1:1
  // Needs line and the phone do. This group chat's switch stayed live.
  testWidgets("the group chat's Needs switch greys at the chat's own choice "
      "while Porch Life's Needs is off", (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final chat = _NeedsChat(GroupChat(id: 'g1', name: 'The Stoop'), const []);
    final storage = FakeStorageService();
    addTearDown(chat.dispose);
    addTearDown(storage.dispose);
    await storage.realismSettings.setNeedsSimDefault(false);

    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(body: GroupNeedsTab(chatService: chat)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final needs = tester.widget<Switch>(
      find
          .descendant(
            of: find.widgetWithText(Row, 'Needs Simulation'),
            matching: find.byType(Switch),
          )
          .first,
    );
    expect(needs.value, chat.needsSimEnabled, reason: "the chat's own choice");
    expect(needs.onChanged, isNull);
    expect(
      find.text(
        "Off in Porch Life, so no chat runs Needs. This chat's choice is kept.",
      ),
      findsOneWidget,
    );
  });
}
