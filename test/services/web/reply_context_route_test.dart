// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Phone Inspect prompt: /api/chat/state flags a reply that kept its prompt,
// and GET /api/chat/context-budget?index=N returns that reply's send. Real
// WebChatRoutes -> ChatFacade -> ChatService over the shared scripted model.
//
// Proven red: dropping `index:` in the route returns the last send (no
// 'reply' source); dropping 'hasContext' from state() fails the flag check.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/routes/chat_routes.dart';

import '../../helpers/reprocess_needs_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  late ChatFacade facade;
  late Router router;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
    facade = ChatFacade(h.chat, h.repo, null, null, null);
    router = Router();
    WebChatRoutes(facade, router);
  });
  tearDown(() => h.dispose());

  Future<(int, Object?)> get(String query) async {
    final res = await router.call(
      shelf.Request(
        'GET',
        Uri.parse('http://localhost/api/chat/context-budget$query'),
      ),
    );
    return (res.statusCode, jsonDecode(await res.readAsString()));
  }

  test('a reply carries its own prompt to the phone', () async {
    final i = await h.oneToOneWithStampedReply(needsCard('Mara'));

    final messages = (facade.state()['messages'] as List)
        .cast<Map<String, dynamic>>();
    expect(messages[i]['hasContext'], isTrue);
    expect(messages[i - 1]['hasContext'], isNull, reason: 'user message');

    final (code, body) = await get('?index=$i');
    expect(code, 200);
    final json = body! as Map<String, dynamic>;
    expect(json['source'], 'reply');
    expect(json['textPruned'], isFalse);
    final texts = (json['sections'] as List)
        .map((s) => (s as Map)['text'] as String)
        .join('\n');
    expect(texts, contains('Long day. How are you holding up?'));
  });

  test('a user message or a bad index has no prompt', () async {
    final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
    expect((await get('?index=${i - 1}')).$1, 404);
    expect((await get('?index=999')).$1, 404);
    expect((await get('?index=abc')).$1, 400);
    expect((await get('')).$1, 200, reason: 'the last send still works');
  });
}
