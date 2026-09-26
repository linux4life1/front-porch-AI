// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web relay of desktop chat export/import. These hit the LIVE ChatService
// package I/O through ChatPackageFacade — a 404/empty from the facade is
// exactly what the PWA would download.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_package_facade.dart';
import 'package:front_porch_ai/services/web/routes/chat_package_routes.dart';
import 'package:front_porch_ai/services/web/util/util.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_pkg_').path;
        }
        return null;
      });
}

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*A nod from the porch.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'SilentLlm';
}

class _HangingLlm extends LLMService {
  final gate = Completer<void>();

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      await gate.future;
      yield '*A nod from the porch.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'HangingLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;
  late ChatPackageFacade facade;
  late Router router;

  CharacterCard alice() => CharacterCard(
    name: 'Alice',
    description: 'Package-export test card.',
    firstMessage: 'The porch light hums.',
  )..dbId = 'char-pkg-alice';

  CharacterCard bob() => CharacterCard(
    name: 'Bob',
    description: 'Mismatch target.',
    firstMessage: 'Evening.',
  )..dbId = 'char-pkg-bob';

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
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
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = _SilentLlm();
    await storage.initialized;
    facade = ChatPackageFacade(chat);
    router = Router();
    WebChatPackageRoutes(facade, router);
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> seedTurn() async {
    await chat.setActiveCharacter(alice());
    await chat.sendMessage('hello there');
  }

  test('empty chat export is null (route 404)', () async {
    expect(facade.exportJsonl(), isNull);
    expect(await facade.exportFpchat(), isNull);
    final res = await router.call(
      shelf.Request('GET', Uri.parse('http://x/api/chat/export.jsonl')),
    );
    expect(res.statusCode, 404);
  });

  test('JSONL export is real ST JSONL after a turn', () async {
    await seedTurn();
    final text = facade.exportJsonl();
    expect(text, isNotNull);
    final lines = text!.trim().split('\n');
    expect(lines.length, greaterThanOrEqualTo(3));
    final header = jsonDecode(lines.first) as Map;
    expect(header['character_name'], 'Alice');
    expect(header.containsKey('mes'), isFalse);
    expect(text, contains('hello there'));

    final res = await router.call(
      shelf.Request('GET', Uri.parse('http://x/api/chat/export.jsonl')),
    );
    expect(res.statusCode, 200);
    expect(res.headers['content-type'], contains('ndjson'));
    expect(res.headers['content-disposition'], contains('attachment'));
    expect(await res.readAsString(), contains('hello there'));
  });

  test('fpchat export is a zip with the attachment header', () async {
    await seedTurn();
    final res = await router.call(
      shelf.Request('GET', Uri.parse('http://x/api/chat/export.fpchat')),
    );
    expect(res.statusCode, 200);
    expect(res.headers['content-type'], contains('zip'));
    final bytes = (await res.read().toList()).expand((c) => c).toList();
    expect(bytes.length, greaterThan(4));
    // ZIP local-file magic.
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4b);
    expect(res.headers['content-disposition'], contains('attachment'));
  });

  test('import JSONL creates a new session with the transcript', () async {
    await seedTurn();
    final jsonl = facade.exportJsonl()!;
    final beforeId = chat.currentSessionId;

    await chat.startNewChat();
    expect(chat.currentSessionId, isNot(beforeId));

    final outcome = await facade.importBytes(
      Uint8List.fromList(utf8.encode(jsonl)),
    );
    expect(outcome.fullRestore, isFalse);
    expect(chat.messages.map((m) => m.text).join(' '), contains('hello there'));
    expect(chat.currentSessionId, isNot(beforeId));
  });

  test('1:1 card clash without a choice throws mismatch (route 409)', () async {
    await seedTurn();
    final bytes = await facade.exportFpchat();
    expect(bytes, isNotNull);

    await chat.setActiveCharacter(bob());

    await expectLater(
      facade.importBytes(bytes!),
      throwsA(isA<ChatPackageMismatch>()),
    );

    final res = await router.call(
      shelf.Request('POST', Uri.parse('http://x/api/chat/import'), body: bytes),
    );
    expect(res.statusCode, 409);
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['error'], 'character_mismatch');
    expect(body['packageName'], 'Alice');
    expect(body['activeName'], 'Bob');
  });

  test('import while a reply is streaming is refused', () async {
    await chat.setActiveCharacter(alice());
    final hang = _HangingLlm();
    chat.testLlmServiceOverride = hang;
    final send = chat.sendMessage('hold this');
    // Readiness wait REWORKED 2026-08-13 (wait primitive only — the
    // assertion below is untouched): 400 zero-delay yields burn out in
    // under a millisecond, and on a loaded 4-way concurrent run a
    // CPU-heavy sibling suite (the auth lockout hashing loop) can starve
    // sendMessage's own awaits past that window — red with no product
    // bug (reproduced ~1 in 3 full-tree runs locally). Real-time bound
    // instead; the settle path stays identical once isGenerating flips.
    final genDeadline = DateTime.now().add(const Duration(seconds: 10));
    while (!chat.isGenerating && DateTime.now().isBefore(genDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(chat.isGenerating, isTrue);

    await expectLater(
      facade.importBytes(utf8.encode('{"messages":[]}')),
      throwsA(isA<ChatImportBusy>()),
    );

    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://x/api/chat/import'),
        body: utf8.encode('{"messages":[]}'),
      ),
    );
    expect(res.statusCode, 409);
    expect(await res.readAsString(), contains('Wait until the current reply'));

    hang.gate.complete();
    await send;
  });

  test('empty upload is 400', () async {
    final res = await router.call(
      shelf.Request('POST', Uri.parse('http://x/api/chat/import'), body: ''),
    );
    expect(res.statusCode, 400);
  });

  test('declared oversize upload is 413 with the 256 MB limit named', () async {
    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://x/api/chat/import'),
        headers: {'content-length': '${RequestBody.packageMaxBytes + 1}'},
        body: Stream<List<int>>.empty(),
      ),
    );
    expect(res.statusCode, 413);
    expect(await res.readAsString(), contains('256 MB'));
  });

  test('garbage mismatch query is 400 not a 409 loop', () async {
    await seedTurn();
    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://x/api/chat/import?mismatch=banana'),
        body: utf8.encode('{"messages":[]}'),
      ),
    );
    expect(res.statusCode, 400);
    expect(await res.readAsString(), contains('full or dialogue'));
  });

  test('mismatch=dialogue imports transcript onto the open card', () async {
    await seedTurn();
    final bytes = await facade.exportFpchat();
    await chat.setActiveCharacter(bob());

    final outcome = await facade.importBytes(bytes!, mismatch: 'dialogue');
    expect(outcome.fullRestore, isFalse);
    expect(chat.messages.map((m) => m.text).join(' '), contains('hello there'));
    expect(chat.activeCharacter?.name, 'Bob');
  });

  test('garbage bytes are a friendly 400 not ArchiveException', () async {
    await chat.setActiveCharacter(alice());
    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://x/api/chat/import'),
        body: [0x89, 0x50, 0x4E, 0x47],
      ),
    );
    expect(res.statusCode, 400);
    final body = await res.readAsString();
    expect(body, contains('not a Front Porch or SillyTavern'));
    expect(body, isNot(contains('ArchiveException')));
  });

  test('send during import is refused', () async {
    await seedTurn();
    final bytes = await facade.exportFpchat();
    expect(bytes, isNotNull);

    chat.testImportHold = Completer<void>();
    final import = facade.importBytes(bytes!);
    // Same load-robust readiness wait as the streaming test above
    // (2026-08-13) — the zero-delay spin is the flaky primitive.
    final impDeadline = DateTime.now().add(const Duration(seconds: 10));
    while (!chat.isImporting && DateTime.now().isBefore(impDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(chat.isImporting, isTrue);

    await chat.sendMessage('sneak');
    expect(
      chat.messages.map((m) => m.text).join(' '),
      isNot(contains('sneak')),
    );

    chat.testImportHold!.complete();
    await import;
    expect(
      chat.messages.map((m) => m.text).join(' '),
      isNot(contains('sneak')),
    );
  });

  test('mismatch=full restores package stamps onto the open card', () async {
    await seedTurn();
    final bytes = await facade.exportFpchat();
    expect(bytes, isNotNull);
    await chat.setActiveCharacter(bob());

    final outcome = await facade.importBytes(bytes!, mismatch: 'full');
    expect(outcome.fullRestore, isTrue);
    expect(chat.messages.map((m) => m.text).join(' '), contains('hello there'));
  });
}
