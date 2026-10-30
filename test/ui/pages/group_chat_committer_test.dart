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

// The new-group wizard's Voice pick reaches the group. The committer wrote
// each member's row with the library card's own voice, then put the pick on
// the LIBRARY card in memory, so the group never had it and the character's
// 1:1 chats spoke in the picked voice until the app restarted.
//
// Red proof: put the row's voice back to `source.ttsVoice`, or restore the
// loop that set `card.ttsVoice` after the save.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/create_group_chat_page/create_group_chat_page.dart';

final Directory _root = Directory.systemTemp.createTempSync('fpai_committer_');

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return _root.path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('the Voice pick goes on the member, never the library card', () async {
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    final storage = StorageService();
    await storage.initialized;
    final db = AppDatabase.forTesting(sameIsolate: true);
    addTearDown(db.close);
    final repo = CharacterRepository(db, storage);
    final groupRepo = GroupChatRepository(storage, db);
    addTearDown(repo.dispose);
    addTearDown(groupRepo.dispose);

    // Two library characters, one with a voice of her own.
    final dir = Directory.systemTemp.createTempSync('committer_cards_');
    addTearDown(() => dir.deleteSync(recursive: true));
    Future<CharacterCard> library(String name, {String? voice}) async {
      final card = CharacterCard(name: name, description: 'In the library.')
        ..ttsVoice = voice;
      final png = p.join(dir.path, '${name}_1700000000.png');
      await V2CardService().saveCardAsPng(card, png, null);
      card.imagePath = png;
      await repo.addCharacter(card);
      return card;
    }

    final mara = await library('Mara', voice: 'af_sky');
    final rue = await library('Rue');

    final draft = GroupWizardDraft();
    addTearDown(draft.dispose);
    draft
      ..addMember(mara)
      ..addMember(rue)
      ..setVoice(draft.stableId(mara), 'am_adam');

    final group = await GroupChatCommitter(
      repo: repo,
      groupRepo: groupRepo,
      storage: storage,
      database: db,
    ).commit(draft, 'Pair');

    final rows = await db.getGroupMembers(group.id);
    final voices = {for (final r in rows) r.name: r.ttsVoice};
    expect(
      voices,
      {'Mara': 'am_adam', 'Rue': null},
      reason: 'THE BUG: the row kept the card\'s voice; the pick was lost',
    );
    expect(
      mara.ttsVoice,
      'af_sky',
      reason: 'the pick was put on the library card in memory, so her 1:1 '
          'chats spoke in it',
    );
  });
}
