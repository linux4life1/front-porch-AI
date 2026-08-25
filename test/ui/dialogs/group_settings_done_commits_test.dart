// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "DONE" WAS A DISCARD BUTTON WEARING THE PRIMARY-ACTION COLOUR.
//
// Every Group Settings tab except General edits the live GroupChat as the user
// types, so closing keeps those edits. General holds name / scenario / first
// message / turn rules in TextEditingControllers until applyToLiveGroup() runs
// — and that only ever ran from the footer's outlined "Save". The right-most,
// filled "Done" button did a bare Navigator.pop, so renaming a group and
// pressing the button that looks like the one you press threw the rename away
// with no warning.
//
// The sibling guard (group_general_save_test.dart) pins the Save path. This is
// the twin: the same typed edit, committed through Done.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings_dialog.dart';
import 'package:front_porch_ai/ui/widgets/group_alternate_greetings_editor.dart';

import '../../golden/support/fakes.dart';

class _ChatWithGroup extends FakeChatService {
  _ChatWithGroup(this._group);
  final GroupChat _group;

  @override
  GroupChat? get activeGroup => _group;
}

class _RecordingRepo extends FakeGroupChatRepository {
  GroupChat? saved;

  @override
  Future<void> save(GroupChat group) async {
    saved = group;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Done applies the General tab edit instead of discarding it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final group = GroupChat(id: 'g1', name: 'The Fellowship');
    final chat = _ChatWithGroup(group);
    final repo = _RecordingRepo();
    final worlds = FakeWorldRepository();
    addTearDown(chat.dispose);
    addTearDown(repo.dispose);
    addTearDown(worlds.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GroupSettingsDialog(chatService: chat, groupRepo: repo),
          ),
        ),
      ),
    );
    await tester.pump();

    final generalTab = find.text('General');
    await tester.ensureVisible(generalTab);
    await tester.tap(generalTab);
    await tester.pumpAndSettle();

    expect(find.byType(GroupGeneralTab), findsOneWidget);

    final nameField = find
        .descendant(
          of: find.byType(GroupGeneralTab),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(nameField, 'The New Fellowship');
    await tester.pump();

    // The controller holds it; nothing has reached the live group yet.
    expect(group.name, 'The Fellowship');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Done'));
    await tester.pump();

    expect(group.name, 'The New Fellowship');
    expect(repo.saved, same(group));
    expect(repo.saved!.name, 'The New Fellowship');
  });

  testWidgets(
    'applyToLiveGroup compact-pairs dirty greets so live overlay is not mis-paired',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final group = GroupChat(
        id: 'g-live-pair',
        name: 'The House',
        firstMessage: 'Come in.',
      );
      final chat = _ChatWithGroup(group);
      addTearDown(chat.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GroupGeneralTab(chatService: chat)),
        ),
      );
      await tester.pumpAndSettle();

      final editor = tester.widget<GroupAlternateGreetingsEditor>(
        find.byType(GroupAlternateGreetingsEditor),
      );
      final furious = GreetingRealismSeed(characterEmotion: 'furious');
      editor.onChanged(['', 'Get out.'], [furious]);
      await tester.pump();

      tester
          .state<GroupGeneralTabState>(find.byType(GroupGeneralTab))
          .applyToLiveGroup();

      expect(
        group.alternateGreetings,
        ['Get out.'],
        reason: 'live write must compact, not keep the blank row',
      );
      expect(
        group.greetingSeeds,
        isEmpty,
        reason: 'furious sat on the blank; live allGreetings must not see it on Get out',
      );
      expect(group.allGreetings, ['Come in.', 'Get out.']);
      expect(
        greetingOverlayAt(group.greetingSeeds, 1),
        isNull,
        reason: 'overlay index 1 is Get out — leftover furious would have landed here',
      );
    },
  );
}
