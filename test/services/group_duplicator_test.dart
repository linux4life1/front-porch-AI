// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Duplicate Group copies the group's whole definition under fresh ids and
// shares no file with the original; the menu action makes exactly one copy
// however fast it is tapped.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_card_menu_actions.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_chat_opener.dart';

import '../helpers/double_tap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase db;
  late StorageService storage;

  Future<void> seed() async {
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'group_orig',
        name: 'Porch Night',
        characterIds: const Value('["m-ada","m-bea"]'),
        turnOrder: const Value('random'),
        autoAdvance: const Value(true),
        directorMode: const Value(true),
        firstMessage: const Value('Evening, all.'),
        scenario: const Value('A long porch night.'),
        systemPrompt: const Value('Keep it warm.'),
        personality: const Value('Chatty.'),
        postHistoryInstructions: const Value('Stay in scene.'),
        mesExample: const Value('{{char}}: hi'),
        tags: const Value('["cozy"]'),
        storyStartDate: const Value('2031-05-04'),
        storyStartTime: const Value('19:30'),
        chaosModeEnabled: const Value(true),
        chaosNsfwEnabled: const Value(true),
        groupLorebook: const Value('{"entries":[{"key":"porch"}]}'),
        worldIds: const Value('["world_a"]'),
        loreWorldIds: const Value('["world_b"]'),
        inheritCharacterLorebooks: const Value(true),
        realismVerificationEnabled: const Value(true),
        realismVerificationStrictness: const Value(5),
        realismVerificationMaxReprocesses: const Value(3),
        needsDirectorAuthority: const Value(true),
        defaultMemberRealismState: const Value(
          '{"m-ada":{"relationships":{"m-bea":120}}}',
        ),
        baselineRealismState: const Value('{"m-bea":{"trust":80}}'),
        characterSystemPrompts: const Value('{"m-ada":"Be brief."}'),
        characterAuthorNotes: const Value(
          '{"m-bea":{"note":"Hums.","strength":4}}',
        ),
        stableId: const Value('stable-orig'),
        folderId: const Value('folder-1'),
      ),
    );
    final avatars = Directory(
      p.join(storage.groupsDir.path, 'group_orig', 'avatars'),
    )..createSync(recursive: true);
    for (final (id, name) in [('m-ada', 'ada'), ('m-bea', 'bea')]) {
      File(
        p.join(avatars.path, '$name.png'),
      ).writeAsBytesSync([1, 2, 3, name.length]);
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'group_orig',
          name: name,
          personality: Value('$name is kind.'),
          avatarFilename: Value('$name.png'),
          frontPorchExtensions: Value('{"realism_engine":{"likes":["$id"]}}'),
          memberState: Value('{"originStableId":"${name}_lib"}'),
        ),
      );
    }
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai_dup_group_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null,
        );
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storage = StorageService();
    await storage.initialized;
    await seed();
  });

  tearDown(() async {
    storage.dispose();
    await db.close();
    root.deleteSync(recursive: true);
  });

  test('the copy has every field, fresh ids, and shares no file', () async {
    final newId = await GroupDuplicator(
      db: db,
      groupsDir: storage.groupsDir,
    ).duplicate('group_orig');
    expect(newId, isNotNull);
    expect(newId, isNot('group_orig'));

    final a = (await db.getGroupById('group_orig'))!.toJson();
    final b = (await db.getGroupById(newId!))!.toJson();
    // Every column but the identity ones is equal, and that covers columns
    // added later: a new column that is not copied fails here.
    const own = {'id', 'name', 'stableId', 'updatedAt'};
    for (final k in a.keys.where((k) => !own.contains(k))) {
      if (k == 'defaultMemberRealismState' ||
          k == 'baselineRealismState' ||
          k == 'characterSystemPrompts' ||
          k == 'characterAuthorNotes') {
        continue; // keyed by member id: checked below under the new ids
      }
      expect(b[k], a[k], reason: 'column $k was not copied');
    }
    expect(b['name'], 'Porch Night (copy)');
    expect(
      b['stableId'],
      isNull,
      reason: 'the copy is its own shareable group',
    );

    final origMembers = await db.getGroupMembers('group_orig');
    final copyMembers = await db.getGroupMembers(newId);
    expect(copyMembers.map((m) => m.name).toSet(), {'ada', 'bea'});
    final oldIds = origMembers.map((m) => m.id).toSet();
    expect(copyMembers.map((m) => m.id).toSet().intersection(oldIds), isEmpty);
    final newIdOf = {for (final m in copyMembers) m.name: m.id};
    expect(b['characterSystemPrompts'], '{"${newIdOf['ada']}":"Be brief."}');
    expect(
      b['characterAuthorNotes'],
      '{"${newIdOf['bea']}":{"note":"Hums.","strength":4}}',
    );
    expect(
      b['defaultMemberRealismState'],
      '{"${newIdOf['ada']}":{"relationships":{"${newIdOf['bea']}":120}}}',
    );
    for (final m in copyMembers) {
      final o = origMembers.firstWhere((x) => x.name == m.name).toJson();
      final c = m.toJson();
      for (final k in o.keys.where(
        (k) => !{
          'id',
          'groupId',
          'updatedAt',
          'createdAt',
          'frontPorchExtensions',
        }.contains(k),
      )) {
        expect(c[k], o[k], reason: 'member column $k was not copied');
      }
      expect(m.frontPorchExtensions, contains(m.id));
      expect(m.frontPorchExtensions, isNot(contains(o['id'] as String)));
    }

    // Files: copied under the new group, never shared.
    for (final m in copyMembers) {
      final from = File(
        p.join(
          storage.groupsDir.path,
          'group_orig',
          'avatars',
          m.avatarFilename!,
        ),
      );
      final to = File(
        p.join(storage.groupsDir.path, newId, 'avatars', m.avatarFilename!),
      );
      expect(to.existsSync(), isTrue);
      expect(to.path, isNot(from.path));
      expect(to.readAsBytesSync(), from.readAsBytesSync());
      to.writeAsBytesSync([9]);
      expect(from.readAsBytesSync(), isNot([9]));
    }
    expect(
      Directory(
        p.join(storage.groupsDir.path, newId),
      ).listSync().map((e) => p.basename(e.path)),
      ['avatars'],
      reason: 'only the avatars come over: no removed members, no chats',
    );
    // The original is untouched.
    expect((await db.getGroupById('group_orig'))!.toJson(), a);
  });

  test('a group that is gone cannot be copied', () async {
    final dup = GroupDuplicator(db: db, groupsDir: storage.groupsDir);
    expect(await dup.duplicate('nope'), isNull);
  });

  testWidgets('tapping Duplicate Group twice fast makes exactly one copy', (
    tester,
  ) async {
    Provider.debugCheckInvalidValueType = null;
    addTearDown(() => Provider.debugCheckInvalidValueType = null);
    late GroupChatRepository groups;
    late FolderService folders;
    await tester.runAsync(() async {
      groups = GroupChatRepository(storage, db);
      await groups.reload();
      folders = FolderService(db);
      await folders.reload();
    });
    final group = groups.getById('group_orig')!;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<StorageService>.value(value: storage),
          ChangeNotifierProvider<GroupChatRepository>.value(value: groups),
          ChangeNotifierProvider<FolderService>.value(value: folders),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => runHomeGroupMenuAction(
                  context,
                  'duplicate',
                  group,
                  chats: HomeChatOpener(
                    context: context,
                    isMounted: () => true,
                    onChatClosed: () {},
                  ),
                  activeFolderId: null,
                ),
                child: const Text('Duplicate Group'),
              ),
            ),
          ),
        ),
      ),
    );
    await doubleTapNoFrame(tester, find.text('Duplicate Group'));
    // The copy runs on real I/O: give it real time, then let the fake
    // clock's microtasks catch up, until the snackbar says it finished.
    for (var i = 0; i < 40 && find.byType(SnackBar).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    final all = await tester.runAsync(db.getAllGroups);
    expect(all!.where((g) => g.name == 'Porch Night (copy)'), hasLength(1));
    expect(find.text('Group duplicated successfully.'), findsOneWidget);
  });
}
