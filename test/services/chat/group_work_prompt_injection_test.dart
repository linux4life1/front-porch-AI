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

// GROUP TURNS MUST READ THE PINNED SPEAKER'S JOB, NOT `_activeCharacter`.
//
// setActiveGroup nulls `_activeCharacter`. Prompt compose still built
// occupation / hours / occupationBrief from that field, so group chats
// got an empty job, empty hours (fail-closed to not-at-work), and no
// brief — while the skip banner already used `_workFieldsFor` on the
// real speaker card. The leaf test "group at-work prompt injects the
// same brief" stubbed getOccupationBrief on a bare BehavioralInjection
// and never went through this wiring.
//
// Proven red: debugBuildPositionInjection() after setActiveGroup + pin
// returned '' (no "At work as a …", no brief).

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/ui_settings/ui_settings.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_grpwork_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late GroupRealismBlobs blobs;

  const brief = 'Keeps the diner grill and the late-night register';

  setUp(() async {
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    db = AppDatabase.forTesting();
    storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage));
    await storage.initialized;

    blobs = buildGroupRealismBlobs(
      seeds: {
        'mem-ana': defaultGroupMemberRealismSeed(),
        'mem-bea': defaultGroupMemberRealismSeed(),
      },
      needsEnabled: false,
      timeOfDay: 'afternoon',
      dayCount: 1,
    );
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-work',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-ana',
        groupId: 'grp-work',
        name: 'Ana',
        firstMessage: const Value('Evening.'),
        avatarFilename: const Value('mem-ana.png'),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-bea',
        groupId: 'grp-work',
        name: 'Bea',
        firstMessage: const Value('The grill is already hot.'),
        avatarFilename: const Value('mem-bea.png'),
        frontPorchExtensions: Value(
          jsonEncode(
            FrontPorchExtensions(
              realismEnabled: true,
              occupation: 'clerk',
              hours: '9-5',
              occupationBrief: brief,
            ).toJson(),
          ),
        ),
      ),
    );
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('group at-work prompt injects the pinned speaker brief', () async {
    await chat.setActiveGroup(
      GroupChat(
        id: 'grp-work',
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage, db),
    );

    expect(
      chat.activeCharacter,
      isNull,
      reason: 'setActiveGroup nulls the 1:1 host; that is the bug surface',
    );
    expect(chat.realismEnabled, isTrue);
    expect(chat.groupCharacters, hasLength(2));

    final bea = chat.groupCharacters.firstWhere((c) => c.name == 'Bea');
    chat.debugPinTurnSpeakerForRealism(bea.stableGroupId);
    await chat.timeService.setClockDirect(DateTime.utc(2026, 1, 1, 14, 30));

    final txt = chat.debugBuildPositionInjection();
    expect(
      txt,
      contains('At work as a clerk'),
      reason:
          'THE BUG: occupation/hours/brief still read `_activeCharacter`, '
          'which is null in group, so the live injection is empty even '
          'though the skip banner already uses the speaker card.',
    );
    expect(txt, contains(brief));
    expect(txt, contains('Write from there.'));
  });

  // A member card is named after its group_members row, so only the row's
  // provenance links it to the library card it was copied from. The card,
  // the prompt and the web cast all found that card by NAME: after the
  // library Bea was renamed Beatrice and a new Bea imported, the old Bea's
  // copy (blank work fields, so the library's job fills in) read the new
  // Bea's empty job everywhere, and both same-named members looked alike.
  testWidgets('a member copied from a renamed library card keeps its job on '
      'the card, in the prompt and on the web, and a same-named member keeps '
      'its own', (tester) async {
    const gid = 'grp-bea';
    late CharacterRepository repo;
    await tester.runAsync(() async {
      for (final c in const [
        ('lib-bea', 'Beatrice', 'bea.png'),
        ('lib-bea-new', 'Bea', 'bea_new.png'),
      ]) {
        await db.insertCharacter(
          CharactersCompanion.insert(
            id: c.$1,
            name: c.$2,
            imagePath: Value(c.$3),
          ),
        );
      }
      repo = CharacterRepository(db, storage);
      chat.setCharacterRepository(repo);
      await repo.loadCharacters();
      // The library's job lives in its PNG; set it on the loaded card.
      repo.characters
          .firstWhere((c) => c.dbId == 'lib-bea')
          .frontPorchExtensions = FrontPorchExtensions(
        occupation: 'clerk',
        hours: '9-5',
      );

      await db.insertGroup(
        GroupsCompanion.insert(
          id: gid,
          name: 'Two Beas',
          defaultMemberRealismState: Value(blobs.defaultMemberJson),
          baselineRealismState: Value(blobs.baselineJson),
        ),
      );
      for (final m in const [
        ('mem-old', 'lib-bea', 'bea'),
        ('mem-new', 'lib-bea-new', 'bea_new'),
      ]) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: m.$1,
            groupId: gid,
            name: 'Bea',
            firstMessage: const Value('Evening.'),
            avatarFilename: Value('${m.$1}.png'),
            memberState: Value(
              GroupMember.encodeProvenance(
                originStableId: m.$3,
                originLibraryDbId: m.$2,
              ),
            ),
          ),
        );
      }
      await chat.setActiveGroup(
        GroupChat(
          id: gid,
          name: 'Two Beas',
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
        groupRepo: GroupChatRepository(storage, db),
      );
      await chat.timeService.setClockDirect(DateTime.utc(2026, 1, 1, 14, 30));
    });

    CharacterCard member(String id) =>
        chat.groupCharacters.firstWhere((c) => c.dbId == id);

    Future<String> cardWord(String id) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<CharacterRepository>.value(
          value: repo,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                child: GroupMemberCard(
                  character: member(id),
                  chatService: chat,
                  avatarColor: AppColors.formMasterAccent,
                  isNextSpeaker: false,
                  isExpanded: false,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return find.text('At work').evaluate().isNotEmpty ? 'At work' : 'other';
    }

    expect(
      chat.originLibraryCardFor(member('mem-old'))?.dbId,
      'lib-bea',
      reason: 'expressions, Pockets and the avatar follow the same origin',
    );
    expect(chat.originLibraryCardFor(member('mem-new'))?.dbId, 'lib-bea-new');

    expect(await cardWord('mem-old'), 'At work', reason: 'member card');
    expect(chat.groupMemberPresence('mem-old'), PresenceWhere.atWork);
    chat.debugPinTurnSpeakerForRealism('mem-old');
    expect(chat.debugBuildPositionInjection(), contains('At work as a clerk'));

    expect(
      await cardWord('mem-new'),
      'other',
      reason: 'the new Bea has no job',
    );
    expect(chat.groupMemberPresence('mem-new'), PresenceWhere.withYou);
    chat.debugPinTurnSpeakerForRealism('mem-new');
    expect(chat.debugBuildPositionInjection(), isNot(contains('At work')));

    // Saving the member's chat colours (UI Settings) or an Edit group copy
    // swaps a fresh card into the roster. Without the row's provenance on it
    // the old Bea matched the new Bea by name until the group reloaded.
    final recoloured = cloneCharacterWithExtensions(
      member('mem-old'),
      FrontPorchExtensions(),
    );
    expect(recoloured.originLibraryDbId, 'lib-bea', reason: 'colour copy');
    expect(recoloured.originStableId, 'bea', reason: 'colour copy');
    final bare = CharacterCard(
      name: 'Bea',
      imagePath: member('mem-old').imagePath,
    )..dbId = 'mem-old';
    await tester.runAsync(() async => chat.refreshActiveCharacterCard(bare));
    expect(identical(member('mem-old'), bare), isTrue);
    expect(
      chat.originLibraryCardFor(member('mem-old'))?.dbId,
      'lib-bea',
      reason: 'a copy with no provenance keeps the roster card\'s',
    );
    expect(await cardWord('mem-old'), 'At work', reason: 'after the swap');
  });
}
