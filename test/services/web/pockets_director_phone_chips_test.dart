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

// Phone twin of the desktop bubble's Pockets & Wardrobe receipt chips and
// Director verifier chip (message_bubble.realism_chips.dart). The chat
// facade's state feed is what the PWA renders, so both must ride it, and a
// malformed value from an older or newer writer must not break the feed.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show RealismVerification;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';

import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_pocket_chip_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  CharacterRepository? repo;
  ChatService? chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'needs_sim_default': false,
      'pockets_enabled': true,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    repo = CharacterRepository(db!, storage!);
    chat =
        ChatService(
            KoboldService(storage!),
            UserPersonaService(db!),
            storage!,
            WorldRepository(storage!, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo!);
    await storage!.initialized;
    final card = CharacterCard(
      name: 'Wardrobe Tester',
      firstMessage: 'She hangs her coat by the door.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    );
    await repo!.addCharacter(card);
    await chat!.setActiveCharacter(card);
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  /// Stamps [extra] onto the map the desktop bubble reads, then returns the
  /// chips the phone gets for that message.
  Map<String, dynamic> phoneChipsWith(Map<String, dynamic> extra) {
    final msg = chat!.messages.last;
    expect(msg.isUser, isFalse, reason: 'the greeting is the AI reply');
    msg.activeMetadata = {...?msg.activeMetadata, ...extra};
    final facade = ChatFacade(chat!, repo!, null, null, null);
    final msgs = (facade.state()['messages'] as List)
        .cast<Map<String, dynamic>>();
    return Map<String, dynamic>.from((msgs.last['chips'] as Map?) ?? const {});
  }

  test('receipts alone reach the phone, trimmed, with no realism chips', () {
    final chips = phoneChipsWith({
      'pocket_changes': [' picked up: car keys ', '', 7, 'put on: barn coat'],
    });
    expect(chips['pocketChanges'], [
      'picked up: car keys',
      'put on: barn coat',
    ]);
    expect(
      chips.containsKey('bondDelta'),
      isFalse,
      reason: 'Pockets runs with Realism off; a receipt is not a scored reply',
    );
    expect(chips.containsKey('directorStatus'), isFalse);
  });

  test('the Director verdict reaches the phone with its passes and reason', () {
    final chips = phoneChipsWith({
      RealismVerification.kMetaKey: {
        'status': 'corrected',
        'passes': 2,
        'reason': ' Trust moved too far for a greeting. ',
      },
    });
    expect(chips['directorStatus'], 'corrected');
    expect(chips['directorPasses'], 2);
    expect(chips['directorReason'], 'Trust moved too far for a greeting.');
    // Same as the desktop bubble: a verified reply is a scored reply.
    expect(chips['bondDelta'], 0);
    expect(chips['trustDelta'], 0);
  });

  test(
    'an accepted verdict with no reason or passes still sends the status',
    () {
      final chips = phoneChipsWith({
        RealismVerification.kMetaKey: {'status': 'accepted'},
      });
      expect(chips['directorStatus'], 'accepted');
      expect(chips['directorPasses'], 0);
      expect(chips.containsKey('directorReason'), isFalse);
    },
  );

  test('malformed values are skipped, not thrown', () {
    final chips = phoneChipsWith({
      RealismVerification.kMetaKey: {'status': 3, 'passes': 'two'},
      'pocket_changes': 'picked up: car keys',
    });
    expect(chips.containsKey('directorStatus'), isFalse);
    expect(chips.containsKey('pocketChanges'), isFalse);
  });
}
