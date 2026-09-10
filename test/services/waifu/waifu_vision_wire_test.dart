// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Waifu Coder drops a PNG on the composer. Custom chatMessages used to
// throw the pixels away (text-only last user). These pin the wire JSON
// and the harness loop so the photo stays on every generate of the send.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/openai_chat_stream.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:image/image.dart' as img;

void main() {
  setUpAll(() => HttpOverrides.global = null);

  late HttpServer server;
  Map<String, dynamic>? lastRequest;

  setUp(() async {
    lastRequest = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      lastRequest =
          jsonDecode(await utf8.decoder.bind(req).join())
              as Map<String, dynamic>;
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType('text', 'event-stream');
      req.response.write('data: [DONE]\n');
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  const twoImages = ['QUFB', 'QkJC'];
  const photoParts = [
    {'type': 'text', 'text': '(photo)'},
    {
      'type': 'image_url',
      'image_url': {'url': 'data:image/png;base64,QUFB'},
    },
    {
      'type': 'image_url',
      'image_url': {'url': 'data:image/png;base64,QkJC'},
    },
  ];

  test(
    'local chatMessages + images puts the PNG on the last user row',
    () async {
      final params = GenerationParams(
        prompt: 'ignored',
        systemPrompt: 'be brief',
        chatMessages: const [
          {'role': 'user', 'content': 'loop prefix'},
          {'role': 'user', 'content': '(photo)'},
          {'role': 'assistant', 'content': ''},
        ],
        images: twoImages,
      );
      await streamOpenAiChat(
        'http://127.0.0.1:${server.port}',
        params,
      ).drain<void>();

      final messages = lastRequest!['messages'] as List;
      expect(messages[0], {'role': 'system', 'content': 'be brief'});
      expect((messages[1] as Map)['content'], 'loop prefix');
      expect((messages[2] as Map)['role'], 'user');
      expect((messages[2] as Map)['content'], photoParts);
      expect((messages[3] as Map)['role'], 'assistant');
    },
  );

  test(
    'remote chatMessages + images puts the PNG on the last user row',
    () async {
      final remote = OpenRouterService(
        apiUrl: 'http://127.0.0.1:${server.port}/v1',
        modelName: 'test-model',
      );
      await remote.generateWithTools(
        const GenerationParams(
          prompt: 'ignored',
          systemPrompt: 'be brief',
          chatMessages: [
            {'role': 'user', 'content': 'loop prefix'},
            {'role': 'user', 'content': '(photo)'},
          ],
          images: twoImages,
        ),
        const [
          {
            'type': 'function',
            'function': {'name': 'noop'},
          },
        ],
      );

      final messages = lastRequest!['messages'] as List;
      expect(messages[0], {'role': 'system', 'content': 'be brief'});
      expect((messages[1] as Map)['content'], 'loop prefix');
      expect((messages[2] as Map)['content'], photoParts);
    },
  );

  test('harness keeps the photo on every generate of the turn', () async {
    final root = await Directory.systemTemp.createTemp('waifu_img_loop_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final png = img.encodePng(img.Image(width: 8, height: 8));
    final path = await waifuSaveInboxPhoto(root.path, png);
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'glob', arguments: {'pattern': '*.png'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Hmph. I see the screenshot.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    await WaifuHarness(
      session: session,
      llm: llm,
    ).send('what is this', imagePng: png, imagePath: path);
    expect(llm.calls.length, greaterThanOrEqualTo(2));
    expect(llm.calls[0].images, isNotEmpty);
    expect(llm.calls[1].images, isNotEmpty);
  });
}
