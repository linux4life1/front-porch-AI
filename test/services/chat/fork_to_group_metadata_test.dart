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

// CONVERTING A 1:1 INTO A GROUP MUST NOT THROW THE TRANSCRIPT'S METADATA AWAY.
//
// `/join --full <name>` (and the sidebar's "promote scene") duplicates every
// message row into the new group session by hand. That copy listed eight
// columns and left `metadata` / `swipeMetadata` out, so they inserted NULL —
// and because setActiveGroup immediately re-hydrates `_messages` from exactly
// those rows, the in-memory copies were dropped too.
//
// Metadata is not bookkeeping here. A generated image is an EMPTY-text message
// whose only content is `metadata['image_path']`, so the whole history's
// pictures rendered as blank bubbles; `realism_state` / `needs_pre_turn_vector`
// / `pockets_before` are the baseline every later regen, swipe and delete
// rewinds to, so the converted chat also lost its time machine.
//
// Proven to fail: drop the two columns from the companion in
// chat_service_group_membership.dart and both expectations go red (image_path
// null, realism_state null).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_forkmeta_').path;
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
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  CharacterCard card(String name, String id) => CharacterCard(
    name: name,
    description: 'Exists only inside the fork-metadata test.',
    firstMessage: 'The screen door bangs shut behind you.',
  )..dbId = id;

  test('forking a 1:1 into a group carries every message stamp with it', () async {
    await chat.setActiveCharacter(card('Nia', 'char-fork-host'));

    // A generated image: empty text, all of its content in metadata. If the
    // copy drops metadata this message becomes a blank bubble forever.
    await chat.addGeneratedImageMessage(
      '/pictures/porch-dusk.png',
      'a porch at dusk',
    );
    // And a stamp of the kind every rewind reads back.
    final stamped = chat.messages.last;
    stamped.metadata!['realism_state'] = {'affection': 42};

    final group = await chat.forkToGroupChat([
      card('Marisol', 'char-fork-arrival'),
    ], GroupChatRepository(storage, db));

    expect(group, isNotNull, reason: 'the conversion itself must succeed');

    final carried = chat.messages.where(
      (m) => m.metadata?['is_generated_image'] == true,
    );
    expect(
      carried,
      hasLength(1),
      reason:
          'THE BUG: the hand-written row copy omitted the metadata column, and '
          'setActiveGroup re-hydrates the list from those very rows — so the '
          'image message survived as an empty bubble with nothing in it.',
    );
    expect(carried.single.metadata!['image_path'], '/pictures/porch-dusk.png');
    expect(
      carried.single.metadata!['realism_state'],
      {'affection': 42},
      reason:
          'the snapshot regen/swipe/delete rewind to must cross the conversion '
          'too, or the whole pre-fork history becomes un-rewindable',
    );
  });
}
