// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// POST /api/chat/reprocess-feelings tells the phone WHY a re-score did not
// land: a refusal (not on offer right now) reads neutrally, and only an
// answer the model got wrong blames the model. Real WebChatRoutes ->
// ChatFacade -> ChatService over the shared scripted model.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/routes/chat_routes.dart';

import '../../helpers/reprocess_needs_harness.dart';

const _refused = "This reply can't be scored again right now.";
const _unreadable =
    "The model's answer couldn't be read, so this reply keeps the feelings "
    'it had. You can try again.';

/// The shared scripted model, answering the bond/trust judge with prose
/// while [prose] is on.
class _ProseJudgeLlm extends RecordingLlm {
  bool prose = false;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (prose && params.prompt.contains('relationship_delta')) {
      yield 'She seems happier now, I think.';
      return;
    }
    yield* super.generateStream(params);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  late _ProseJudgeLlm llm;
  late Router router;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
    llm = _ProseJudgeLlm();
    h.chat.testLlmServiceOverride = llm;
    router = Router();
    WebChatRoutes(ChatFacade(h.chat, h.repo, null, null, null), router);
  });
  tearDown(() => h.dispose());

  Future<(int, Object?)> post(int index) async {
    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/chat/reprocess-feelings'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'index': index}),
      ),
    );
    return (res.statusCode, jsonDecode(await res.readAsString()));
  }

  test('scored: 200', () async {
    final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
    expect((await post(i)).$1, 200);
  });

  test('not the last reply: 409 with the neutral refusal', () async {
    final first = await h.oneToOneWithStampedReply(needsCard('Mara'));
    await h.chat.sendMessage('And tomorrow?');
    await h.settleTurn();
    final (code, body) = await post(first);
    expect(code, 409);
    expect(body, {'error': _refused});
  });

  test('Realism off: 409 with the neutral refusal', () async {
    final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
    await h.chat.setRealismEnabled(false);
    final (code, body) = await post(i);
    expect(code, 409);
    expect(body, {'error': _refused});
  });

  test('the judge answered with prose: 409 that says so', () async {
    final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
    llm.prose = true;
    final (code, body) = await post(i);
    expect(code, 409);
    expect(body, {'error': _unreadable});
  });
}
