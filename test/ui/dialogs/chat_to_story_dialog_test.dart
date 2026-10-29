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

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide StoryProject;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/chat_to_story_dialog.dart';

import '../../helpers/chat_db_teardown.dart';
import '../../helpers/double_tap.dart';

/// Records every save instead of writing it, so the test counts writes.
class _CountingStories extends StoryRepository {
  _CountingStories(super.db);

  final saved = <StoryProject>[];

  @override
  Future<void> saveProject(StoryProject project) async {
    project.dbId ??= 'story-${saved.length + 1}';
    saved.add(project);
  }
}

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_chat_story_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  // Turn Into a Story… on a group chat (docs/design/stories-from-group-chats.md
  // §1, §5): the Lead row lists every member and the persona, the pick is
  // the one Protagonist, and a double tap on Create saves once.
  testWidgets(
    'a group chat story is led by the member picked on the Lead row',
    (tester) async {
      late AppDatabase db;
      late ChatService chat;
      late _CountingStories stories;
      late UserPersonaService personas;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({'update_auto_check': false});
        db = AppDatabase.forTesting(sameIsolate: true);
        final storage = StorageService();
        await storage.initialized;
        personas = UserPersonaService(db);
        chat =
            ChatService(
                KoboldService(storage),
                personas,
                storage,
                WorldRepository(storage, db),
              )
              ..setDatabase(db)
              ..setCharacterRepository(CharacterRepository(db, storage));
        stories = _CountingStories(db);
        await db.insertGroup(
          GroupsCompanion.insert(id: 'grp-duet', name: 'Porch Duet'),
        );
        for (final m in [('mem-ada', 'Ada'), ('mem-bea', 'Bea')]) {
          await db.insertGroupMember(
            GroupMembersCompanion.insert(
              id: m.$1,
              groupId: 'grp-duet',
              name: m.$2,
              firstMessage: const Value('Evening.'),
            ),
          );
        }
        await db.insertSession(
          SessionsCompanion.insert(
            id: 'sess-duet',
            groupId: const Value('grp-duet'),
          ),
        );
        await chat.setActiveGroup(
          GroupChat(id: 'grp-duet', name: 'Porch Duet'),
          groupRepo: GroupChatRepository(storage, db),
        );
      });
      addTearDown(
        () => tester.runAsync(() => disposeChatThenCloseDb(chat, db)),
      );
      expect(chat.isGroupMode, isTrue);
      expect(chat.currentSessionId, isNotNull);

      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final opened = <StoryProject>[];
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StoryRepository>.value(value: stories),
            ChangeNotifierProvider<UserPersonaService>.value(value: personas),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ChatToStoryDialog(
                      chatService: chat,
                      openProject: (_, p) => opened.add(p),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Lead'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Ada'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Bea'), findsOneWidget);
      expect(
        find.widgetWithText(ChoiceChip, 'You (${personas.persona.name})'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Bea'));
      await tester.pump();
      await doubleTapNoFrame(
        tester,
        find.widgetWithText(FilledButton, 'Create story project'),
      );
      await tester.pumpAndSettle();

      expect(stories.saved, hasLength(1));
      final project = stories.saved.single;
      expect(project.chatGroupId, 'grp-duet');
      expect(project.chatHistorySessionIds, [chat.currentSessionId]);
      expect(
        project.characterCardSnapshots.map((s) => [s['name'], s['role']]),
        [
          ['Ada', 'Supporting'],
          ['Bea', 'Protagonist'],
        ],
      );
      expect(opened, [same(project)]);
      expect(find.byType(ChatToStoryDialog), findsNothing);
    },
  );
}
