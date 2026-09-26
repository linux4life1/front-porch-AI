// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// POST /api/chat/reprocess-needs passes keys through; the service
// intersection drops off keys (/workspace/sow/rn-spec.md item 6 + AMENDMENT
// 1). Real WebChatRoutes -> ChatFacade -> ChatService (pattern:
// test/services/web/chat_fork_test.dart). A refused (off-only) POST keeps
// today's 409 (AMENDMENT 2 item 6).

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
  late Router router;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
    router = Router();
    WebChatRoutes(ChatFacade(h.chat, h.repo, null, null, null), router);
  });
  tearDown(() => h.dispose());

  Future<shelf.Response> post(int index, List<String> needs) async =>
      await router.call(
        shelf.Request(
          'POST',
          Uri.parse('http://localhost/api/chat/reprocess-needs'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'index': index,
            'critique': 'She washed up; hygiene should rise.',
            'needs': needs,
          }),
        ),
      );

  test('an off key alone: 409, no LLM call, no write', () async {
    final i = await h.oneToOneWithStampedReply(
      needsCard('Mara', needsOff: ['hygiene', 'fun']),
    );
    final before = h.storedNeedsFingerprint(i);
    final res = await post(i, ['hygiene']);
    expect(h.llm.reprocessPrompts, isEmpty);
    expect(res.statusCode, 409);
    expect(jsonDecode(await res.readAsString()), {
      'error': 'Message cannot be reprocessed',
    });
    expect(h.storedNeedsFingerprint(i), before);
  });

  test('off + on keys: only the on key is asked', () async {
    final i = await h.oneToOneWithStampedReply(
      needsCard('Mara', needsOff: ['hygiene', 'fun']),
    );
    final res = await post(i, ['hygiene', 'energy']);
    expect(res.statusCode, 200);
    expect(askedDeltaKeys(h.llm.reprocessPrompts.single), {'energy'});
  });
}
