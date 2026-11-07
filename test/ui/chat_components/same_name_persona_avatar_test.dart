// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Several personas can share a name ("Sam" the knight, "Sam" the
// stranger). A user's report: the input bar showed the persona the chat
// speaks as, but their own bubbles showed another same-named persona's
// avatar, because the bubble looked the persona up by the sender NAME and
// took whichever "Sam" came first in the list.
//
// A user line now carries the id of the persona that sent it, in a 1:1 and
// in a group alike (one send path), and the bubble resolves by that id.
// Lines saved before the stamp fall back to the chat's own persona when its
// name matches, never to the first namesake.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/persona/persona.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/bubbles/message_bubble.header.dart';

import '../../../integration_test/support/fake_backend.dart';
import '../../golden/support/fakes.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          final dir = Directory.systemTemp.createTempSync('fpai_docs_');
          addTearDown(() => dir.delete(recursive: true));
          return dir.path;
        }
        return null;
      });
}

Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

String _avatar(String who) => p.join(Directory.systemTemp.path, '$who.png');

/// Two personas named Sam, plus the seeded default.
Future<(UserPersonaService, String knight, String stranger)> _twoSams(
  AppDatabase db,
) async {
  final personas = UserPersonaService(db);
  while (personas.personas.isEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  final knight = await personas.createPersona(
    'Knight',
    'Sam',
    '',
    _avatar('sam-knight'),
  );
  final stranger = await personas.createPersona(
    'Stranger',
    'Sam',
    '',
    _avatar('sam-stranger'),
  );
  return (personas, knight, stranger);
}

String? _shownAs(UserPersonaService personas, ChatMessage msg) =>
    personaForUserMessage(
      personas: personas.personas,
      current: personas.persona,
      sender: msg.sender,
      stampedId: msg.activeMetadata?[kUserPersonaIdMeta],
    )?.id;

/// The persona service a bubble reads: a fixed list and the chat's persona.
class _Personas extends ChangeNotifier implements UserPersonaService {
  _Personas(this.personas, this.persona);

  @override
  final List<UserPersona> personas;
  @override
  final UserPersona persona;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('a sent line keeps the persona that sent it', () {
    late AppDatabase db;
    late StorageService storage;
    late FakeBackendServer backend;
    late UserPersonaService personas;
    late String knight;
    late String stranger;
    late ChatService chat;

    setUp(() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': false,
      });
      backend = await FakeBackendServer.start(
        replyPieces: const ['The porch boards creak.'],
      );
      db = AppDatabase.forTesting();
      storage = StorageService();
      (personas, knight, stranger) = await _twoSams(db);
      chat =
          ChatService(
              KoboldService(storage),
              personas,
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(CharacterRepository(db, storage))
            ..testLlmServiceOverride = OpenRouterService(
              apiUrl: '${backend.baseUrl}/v1',
              modelName: 'smoke-model',
            );
      await storage.initialized;
    });

    tearDown(() async {
      chat.dispose();
      await backend.close();
      await db.close();
    });

    // The chat speaks as the stranger, then switches to the knight. Both
    // are "Sam"; each line must still show the one that wrote it.
    Future<void> speakAsBothSams() async {
      await personas.setActivePersona(stranger);
      await chat.sendMessage('Evening.');
      await _drain();
      await personas.setActivePersona(knight);
      await chat.sendMessage('Mind if I sit?');
      await _drain();
    }

    void expectEachLineShowsItsSender() {
      final mine = chat.messages.where((m) => m.isUser).toList();
      expect(mine.map((m) => m.sender), ['Sam', 'Sam']);
      expect(mine.map((m) => _shownAs(personas, m)), [stranger, knight]);
    }

    test('in a 1:1', () async {
      final ada = CharacterCard(
        name: 'Ada',
        description: 'Keeps the porch.',
        firstMessage: 'Evening.',
        imagePath: _avatar('ada-same-name'),
      );
      await CharacterRepository(db, storage).addCharacter(ada);
      await chat.setActiveCharacter(ada);

      await speakAsBothSams();
      expectEachLineShowsItsSender();
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('in a group', () async {
      await db.insertGroup(
        GroupsCompanion.insert(id: 'grp-sams', name: 'Porch'),
      );
      for (final (id, name) in [('mem-ada', 'Ada'), ('mem-bea', 'Bea')]) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: id,
            groupId: 'grp-sams',
            name: name,
            personality: Value('$name keeps the porch.'),
            avatarFilename: Value('${name.toLowerCase()}.png'),
          ),
        );
      }
      await chat.setActiveGroup(
        GroupChat(id: 'grp-sams', name: 'Porch'),
        groupRepo: GroupChatRepository(storage, db),
      );

      await speakAsBothSams();
      expectEachLineShowsItsSender();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  testWidgets('a line saved before the stamp shows the chat\'s own Sam, '
      'not the first Sam in the list', (tester) async {
    final knight = UserPersona(
      id: 'p-knight',
      name: 'Sam',
      avatarPath: _avatar('sam-knight'),
    );
    final stranger = UserPersona(
      id: 'p-stranger',
      name: 'Sam',
      avatarPath: _avatar('sam-stranger'),
    );
    final chat = FakeChatService();
    addTearDown(chat.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<UserPersonaService>.value(
          value: _Personas([knight, stranger], stranger),
          child: MessageBubbleAvatar(
            message: ChatMessage(text: 'Evening.', sender: 'Sam', isUser: true),
            index: 0,
            characterImage: null,
            chatService: chat,
          ),
        ),
      ),
    );

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    final image = avatar.backgroundImage! as ResizeImage;
    expect((image.imageProvider as FileImage).file.path, stranger.avatarPath);
  });
}
