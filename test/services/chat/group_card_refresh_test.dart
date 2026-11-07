// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Saving a group member from the chat editor writes the card back onto the
// live roster. That roster is exposed as an unmodifiable list, so the write
// used to throw "Cannot modify an unmodifiable list" and the Save button
// reported failure (the hygiene toggle on a member of an open group).

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/avatar_image.dart' as model;
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_grp_save_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    db = AppDatabase.forTesting();
    final storage = StorageService();
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
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-save', name: 'Sophia & Iris'),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-sophia',
        groupId: 'grp-save',
        name: 'Sophia',
        firstMessage: const Value(''),
      ),
    );
    await chat.setActiveGroup(
      GroupChat(id: 'grp-save', name: 'Sophia & Iris'),
      groupRepo: GroupChatRepository(storage, db),
    );
    for (var i = 0; i < 40 && chat.groupCharacters.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('saving the open member does not throw on the frozen roster', () {
    final sophia = chat.groupCharacters.firstWhere((c) => c.name == 'Sophia');
    final base = sophia.frontPorchExtensions ?? FrontPorchExtensions();
    sophia.frontPorchExtensions = base.copyWith(enjoysLowHygiene: true);

    expect(() => chat.refreshActiveCharacterCard(sophia), returnsNormally);

    final live = chat.groupCharacters.firstWhere((c) => c.name == 'Sophia');
    expect(live.frontPorchExtensions?.enjoysLowHygiene, isTrue);
  });

  test('a replaced member copy lands on the live roster', () {
    final sophia = chat.groupCharacters.firstWhere((c) => c.name == 'Sophia');
    final copy = CharacterCard(
      name: 'Sophia',
      description: 'Updated in the editor.',
    );
    if (sophia.dbId != null) copy.dbId = sophia.dbId;

    if (sophia.dbId == null) {
      // Identity is the only key when the member row has no library id.
      // The editor mutates that same instance; covered above.
      return;
    }

    chat.refreshActiveCharacterCard(copy);
    final live = chat.groupCharacters.firstWhere((c) => c.name == 'Sophia');
    expect(live.description, 'Updated in the editor.');
  });

  test('a member copy from outside the chat keeps the expression images the '
      'chat\'s own copy holds', () {
    // Edit group builds its copy with GroupMember.toCharacterCard, which has
    // no expression images; the chat inherits those from the library when it
    // loads the roster. Red proof: drop the carry-over in
    // _refreshActiveCharacterCardImpl.
    final sophia = chat.groupCharacters.firstWhere((c) => c.name == 'Sophia');
    expect(sophia.dbId, isNotNull, reason: 'members load with their row id');
    sophia
      ..avatarImages = [
        model.AvatarImage(
          id: 'a-joy',
          characterId: 'sophia-library',
          filename: 'joy.png',
          label: 'joy',
          displayOrder: 0,
          createdAt: DateTime(2026),
        ),
      ]
      ..primeAvatarIndex = 2;
    final fromEditGroup = CharacterCard(
      name: 'Sophia',
      description: 'Fixed a typo in Edit group.',
    )..dbId = sophia.dbId;

    chat.refreshActiveCharacterCard(fromEditGroup);

    final live = chat.groupCharacters.firstWhere((c) => c.name == 'Sophia');
    expect(live.description, 'Fixed a typo in Edit group.');
    expect(live.avatarImages?.map((a) => a.id), [
      'a-joy',
    ], reason: 'the refresh dropped her expression images');
    expect(live.primeAvatarIndex, 2);
  });

  test('saving a member with no row id between turns makes nobody active', () {
    // A group has no active character between turns; null == null matched a
    // member with no row id and made them the active character.
    final sophia = chat.groupCharacters.firstWhere((c) => c.name == 'Sophia');
    sophia.dbId = null;
    expect(chat.activeCharacter, isNull);

    chat.refreshActiveCharacterCard(sophia);

    expect(chat.activeCharacter, isNull);
  });

  test("a member wears her library card's prime expression when no label "
      'matches, as she does in 1:1', () async {
    // A member row has one avatar and prime 1; the group inherits the
    // library card's expression images. The prime index stayed 1, so the
    // fallback face was the first image, not the one starred in the
    // gallery. Red proof: drop the primeAvatarIndex copy in
    // _inheritGroupExpressionAvatars.
    final storage = StorageService();
    await storage.initialized;
    await db.insertCharacter(
      CharactersCompanion.insert(
        id: 'lib-iris',
        name: 'Iris',
        imagePath: const Value('iris.png'),
        primeAvatarIndex: const Value(2),
      ),
    );
    for (final (order, label) in const [(0, 'joy'), (1, 'calm')]) {
      await db.insertAvatar(
        AvatarImagesCompanion.insert(
          id: 'iris-$label',
          characterId: 'lib-iris',
          filename: '$label.png',
          label: Value(label),
          displayOrder: Value(order),
        ),
      );
    }
    final repo = CharacterRepository(db, storage);
    chat.setCharacterRepository(repo);
    await repo.loadCharacters();
    final library = repo.characters.firstWhere((c) => c.dbId == 'lib-iris');
    expect(library.primeAvatarIndex, 2);
    expect(library.avatarImages?.length, 2);

    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-iris', name: 'Iris & Sophia'),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-iris',
        groupId: 'grp-iris',
        name: 'Iris',
        firstMessage: const Value(''),
        memberState: Value(
          GroupMember.encodeProvenance(
            originStableId: 'iris',
            originLibraryDbId: 'lib-iris',
          ),
        ),
      ),
    );
    await chat.setActiveGroup(
      GroupChat(id: 'grp-iris', name: 'Iris & Sophia'),
      groupRepo: GroupChatRepository(storage, db),
    );
    CharacterCard? iris() =>
        chat.groupCharacters.where((c) => c.name == 'Iris').firstOrNull;
    for (var i = 0; i < 40 && iris() == null; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final member = iris()!;
    expect(member.avatarImages?.map((a) => a.id), ['iris-joy', 'iris-calm']);

    expect(
      chat.resolveExpressionAvatar(member)?.id,
      'iris-calm',
      reason: 'the starred face, not the first image',
    );
    expect(member.primeAvatarIndex, library.primeAvatarIndex);
  });
}
