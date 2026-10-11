// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Navigate-first: home pushes ChatPage the instant it calls
// setActiveCharacter / setActiveGroup, without awaiting. That first frame
// must already see isLoadingSession, or it paints the chat being left.
//
// Proven red: moving beginSessionLoad() after the first await
// (_cancelAndWaitForGeneration) in either entry point fails its test.

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
          return Directory.systemTemp.createTempSync('fpai_overlay_1st_').path;
        }
        return null;
      });
}

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'OverlayFirst';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late ChatService chat;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    repo = CharacterRepository(db, storage);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = _SilentLlm();
    await storage.initialized;
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<CharacterCard> addCard(String name) async {
    final card = CharacterCard(
      name: name,
      firstMessage: 'Hello from $name.',
      imagePath: '/tmp/$name-overlay-first.png',
    );
    await repo.addCharacter(card);
    return card;
  }

  /// Leaves [chat] open on Ada's transcript, overlay down.
  Future<void> openAda() async {
    await chat.setActiveCharacter(await addCard('Ada'));
    expect(chat.isLoadingSession, isFalse);
    expect(chat.messages.single.text, 'Hello from Ada.');
  }

  /// Every notification during the switch, as (overlay, first line).
  List<(bool, String?)> recordFrames() {
    final frames = <(bool, String?)>[];
    chat.addListener(
      () => frames.add((
        chat.isLoadingSession,
        chat.messages.isEmpty ? null : chat.messages.first.text,
      )),
    );
    return frames;
  }

  void expectNoUncoveredStaleFrame(List<(bool, String?)> frames) {
    expect(frames, isNotEmpty);
    expect(frames.first.$1, isTrue, reason: 'first rebuild must be covered');
    for (final (covered, first) in frames) {
      if (!covered) {
        expect(first, isNot('Hello from Ada.'), reason: 'stale transcript');
      }
    }
  }

  test(
    'setActiveCharacter raises the overlay before its first await',
    () async {
      await openAda();
      final bea = await addCard('Bea');
      final frames = recordFrames();

      final switching = chat.setActiveCharacter(bea);
      expect(
        chat.isLoadingSession,
        isTrue,
        reason: 'the pushed ChatPage paints synchronously after this call',
      );
      expect(chat.messages.single.text, 'Hello from Ada.');
      await switching;

      expect(chat.isLoadingSession, isFalse);
      expect(chat.messages.single.text, 'Hello from Bea.');
      expectNoUncoveredStaleFrame(frames);
    },
  );

  test('setActiveGroup raises the overlay before its first await', () async {
    await openAda();
    await db.insertGroup(GroupsCompanion.insert(id: 'grp-ov', name: 'Porch'));
    final frames = recordFrames();

    final switching = chat.setActiveGroup(
      GroupChat(id: 'grp-ov', name: 'Porch'),
      groupRepo: GroupChatRepository(storage, db),
    );
    expect(
      chat.isLoadingSession,
      isTrue,
      reason: 'the pushed ChatPage paints synchronously after this call',
    );
    expect(chat.messages.single.text, 'Hello from Ada.');
    await switching;

    expect(chat.isLoadingSession, isFalse);
    expect(chat.activeGroup?.id, 'grp-ov');
    expectNoUncoveredStaleFrame(frames);
  });
}
