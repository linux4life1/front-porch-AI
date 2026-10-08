// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Write it for me" on the phone's Image Studio uses the same prompt writer
// as the /image command, for the chat that is open: the subject the person
// picked decides whose look it is asked to describe, and what they typed is
// handed to the writer to work from. The model here is a scripted one; what
// is checked is what the writer was asked, not what it answered.

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';
import 'dart:convert';

import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/facade/image_facade.dart';
import 'package:front_porch_ai/services/web/routes/image_desk_routes.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

import '../../helpers/reprocess_needs_harness.dart';

/// Notes the prompt of every request the prompt writer makes.
class _WriterLlm extends RecordingLlm {
  final List<String> asked = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    asked.add('${params.systemPrompt ?? ''}\n${params.prompt}');
    yield 'a woman on a porch at dusk';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  late _WriterLlm llm;
  late Router router;

  Future<void> boot({bool withChat = true}) async {
    h = ReprocessHarness();
    await h.boot();
    addTearDown(h.dispose);
    final card = needsCard('Mara')
      ..description = 'Mara has silver hair and wears a green wool coat.';
    await h.oneToOneWithStampedReply(card);
    llm = _WriterLlm();
    h.chat.testLlmServiceOverride = llm;
    final image = ImageGenService(h.storage);
    h.chat.setImageGenService(image);
    router = Router();
    ImageDeskRoutes(
      router,
      deps: WebServerDeps(
        storage: h.storage,
        db: h.db,
        auth: AuthService(h.db),
        chatFacade: withChat
            ? ChatFacade(h.chat, h.repo, null, null, null)
            : null,
      ),
      image: ImageFacade(image, h.storage),
    );
  }

  Future<(int, Map<String, dynamic>)> write(Map<String, dynamic> body) async {
    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/image/studio/write-prompt'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    return (
      res.statusCode,
      jsonDecode(await res.readAsString()) as Map<String, dynamic>,
    );
  }

  test('for the character on screen asks about that character', () async {
    await boot();

    final (status, body) = await write({'subject': 'char'});

    expect(status, 200);
    expect(body['prompt'], startsWith('a woman on a porch at dusk'));
    expect(llm.asked, hasLength(1));
    expect(llm.asked.single, contains('silver hair'));
    expect(llm.asked.single, isNot(contains('Portrait of the user character')));
  });

  test('for the persona asks for the persona\'s portrait', () async {
    await boot();

    final (status, _) = await write({'subject': 'persona'});

    expect(status, 200);
    expect(llm.asked, hasLength(1));
    expect(llm.asked.single, contains('Portrait of the user character'));
  });

  test('freeform hands what was typed to the writer', () async {
    await boot();

    final (status, _) = await write({
      'subject': 'free',
      'instruction': 'a lighthouse in a storm, oil painting',
    });

    expect(status, 200);
    expect(llm.asked.single, contains('a lighthouse in a storm'));
  });

  test('the character with something typed passes that on too', () async {
    await boot();

    await write({'subject': 'char', 'instruction': 'wearing a red scarf'});

    expect(llm.asked.single, contains('silver hair'));
    expect(llm.asked.single, contains('wearing a red scarf'));
  });

  test('freeform with nothing typed writes about the scene', () async {
    await boot();

    final (status, _) = await write({'subject': 'free'});

    expect(status, 200);
    expect(llm.asked.single, contains('Long day'));
  });

  test('a subject that is not on the desk is refused', () async {
    await boot();

    final (status, body) = await write({'subject': 'everyone'});

    expect(status, 400);
    expect(body['code'], 'bad_request');
    expect(llm.asked, isEmpty);
  });

  test('an instruction that is too long is refused', () async {
    await boot();

    final (status, body) = await write({
      'subject': 'free',
      'instruction': 'x' * (ImageDeskRoutes.maxInstruction + 1),
    });

    expect(status, 413);
    expect(body['code'], 'too_large');
    expect(llm.asked, isEmpty);
  });

  test('with no chat open it says so', () async {
    await boot(withChat: false);

    final (status, body) = await write({'subject': 'char'});

    expect(status, 409);
    expect(body['code'], 'no_chat');
  });
}
