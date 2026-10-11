// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Phone "Other words": /api/chat/state flags a reply that kept its unsure
// words, GET /api/chat/token-alts lists them, and POST .../pick rewrites the
// last reply from a word. Real WebTokenAltsRoutes -> ChatFacade ->
// ChatService over the shared scripted model, which here also answers as
// KoboldCpp's transport does (text, then word odds).
//
// Proven red: dropping 'hasTokenAlts' from state() fails the flag check;
// dropping the rewrite call in pickTokenAlternative leaves one swipe.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/routes/token_alts_routes.dart';

import '../../helpers/reprocess_needs_harness.dart';

class _OddsLlm extends RecordingLlm {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final sink = params.onLogprobs;
    if (sink == null) {
      yield* super.generateStream(params);
      return;
    }
    if (params.chatMessages?.last['role'] == 'assistant') {
      yield ' by the gate.';
      return;
    }
    yield 'She sat on the porch.';
    sink([
      {'token': 'She sat on the', 'logprob': math.log(0.9), 'top_logprobs': []},
      {
        'token': ' porch',
        'logprob': math.log(0.3),
        'top_logprobs': [
          {'token': ' porch', 'logprob': math.log(0.3)},
          {'token': ' steps', 'logprob': math.log(0.3)},
        ],
      },
      {'token': '.', 'logprob': math.log(0.9), 'top_logprobs': []},
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  late ChatFacade facade;
  late Router router;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
    h.chat
      ..testLlmServiceOverride = _OddsLlm()
      ..testIsLocalOverride = true;
    facade = ChatFacade(h.chat, h.repo, null, null, null);
    router = Router();
    WebTokenAltsRoutes(facade, router);
  });
  tearDown(() => h.dispose());

  Future<(int, Object?)> call(
    String method,
    String path, [
    Object? body,
  ]) async {
    final res = await router.call(
      shelf.Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {'content-type': 'application/json'},
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return (res.statusCode, jsonDecode(await res.readAsString()));
  }

  test('list the words, then pick one to rewrite the reply', () async {
    final i = await h.oneToOneWithStampedReply(needsCard('Mara'));

    final row = (facade.state()['messages'] as List)[i] as Map;
    expect(row['hasTokenAlts'], isTrue);

    final (code, body) = await call('GET', '/api/chat/token-alts?index=$i');
    expect(code, 200);
    final json = body! as Map;
    expect(json['canPick'], isTrue);
    final place = (json['places'] as List).single as Map;
    expect(place['token'], ' porch');
    expect(place['leadIn'], 'She sat on the');
    expect((place['alts'] as List).single, {'token': ' steps', 'p': 0.3});

    final refused = await call('POST', '/api/chat/token-alts/pick', {
      'index': i,
      'place': 0,
      'word': ' gazebo',
    });
    expect(refused.$1, 409, reason: 'a word that was not offered');

    final picked = await call('POST', '/api/chat/token-alts/pick', {
      'index': i,
      'place': 0,
      'word': ' steps',
    });
    expect(picked.$1, 200);
    await h.settleTurn();
    bool landed() =>
        h.chat.messages.length > i && h.chat.messages[i].swipes.length > 1;
    for (var n = 0; n < 2000 && !landed(); n++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await h.settleTurn();
    expect(h.chat.messages[i].text, 'She sat on the steps by the gate.');
  });

  test('an earlier reply lists its words but cannot be picked', () async {
    final first = await h.oneToOneWithStampedReply(needsCard('Mara'));
    await h.chat.sendMessage('And then?');
    await h.settleTurn();

    final (_, body) = await call('GET', '/api/chat/token-alts?index=$first');
    expect((body! as Map)['canPick'], isFalse);
    expect((await call('GET', '/api/chat/token-alts')).$1, 400);
  });
}
