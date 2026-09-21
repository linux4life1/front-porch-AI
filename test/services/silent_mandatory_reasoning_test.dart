// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SILENT MANDATORY-REASONING STARVE (chargen).
//
// Some models accept reasoning:{enabled:false} with HTTP 200, then think
// anyway with exclude:true. No reasoning/content deltas arrive; the stream
// ends finish_reason:length when hidden think exhausts a small max_tokens
// (chargen steps are 350–4096). No 400 → the old kMandatoryReasoningModels
// learn path never ran, and character_gen_llm retried the same starved
// budget. GLM 5.3 Flash / Qwen 3.8 2.4T A95B on OpenRouter; Grok 4.6 did
// not. This suite pins the 200+length+empty detector and the chargen
// headroom retry (exclude stays on). Chat/Continue do not enlarge the cap.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';

const _model = 'z-ai/glm-5.3-flash';
const _chargenCap = 350;

class _SseReply {
  const _SseReply({
    this.finishReason,
    this.content,
    this.writeDone = true,
    this.status = 200,
  });

  final String? finishReason;
  final String? content;
  final bool writeDone;
  final int status;
}

class _SeenPost {
  _SeenPost({required this.maxTokens, required this.reasoning});
  final int? maxTokens;
  final Map<String, dynamic> reasoning;
}

Future<HttpServer> _startProvider(
  List<_SseReply> replies,
  List<_SeenPost> seen,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var i = 0;
  server.listen((HttpRequest req) async {
    if (i >= replies.length) {
      req.response
        ..statusCode = 500
        ..write('too many posts — retry loop');
      await req.response.close();
      return;
    }
    final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
    seen.add(
      _SeenPost(
        maxTokens: body['max_tokens'] as int?,
        reasoning: ((body['reasoning'] as Map?) ?? {}).cast<String, dynamic>(),
      ),
    );
    final reply = replies[i++];
    if (reply.status != 200) {
      req.response
        ..statusCode = reply.status
        ..write('{"error":{"message":"nope"}}');
      await req.response.close();
      return;
    }
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType('text', 'event-stream');
    req.response.write(
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {if (reply.content != null) 'content': reply.content},
            if (reply.finishReason != null) 'finish_reason': reply.finishReason,
          },
        ],
      })}\n\n',
    );
    if (reply.writeDone) req.response.write('data: [DONE]\n\n');
    await req.response.close();
  });
  return server;
}

OpenRouterService _svc(int port) => OpenRouterService(
  apiUrl: 'http://127.0.0.1:$port',
  apiKey: 'test-key',
  modelName: _model,
);

GenerationParams _chargenParams() => const GenerationParams(
  prompt: 'Write the character name as JSON.',
  maxLength: _chargenCap,
  reasoningEnabled: false,
  reasoningMaxTokens: 0,
  mandatoryReasoningHeadroom: true,
);

GenerationParams _chatParams() => const GenerationParams(
  prompt: 'Say hello.',
  maxLength: _chargenCap,
  reasoningEnabled: false,
  reasoningMaxTokens: 0,
);

const _starve = _SseReply(finishReason: 'length');
const _ok = _SseReply(finishReason: 'stop', content: '{"name":"Mara"}');

Future<String> _collect(OpenRouterService svc, GenerationParams params) async {
  final out = StringBuffer();
  await for (final chunk in svc.generateStream(params)) {
    out.write(chunk);
  }
  return out.toString();
}

void main() {
  setUp(() {
    HttpOverrides.global = null;
    clearReasoningEffortCatalog();
  });
  tearDown(clearReasoningEffortCatalog);

  test('predicate is the strict conjunction only', () {
    expect(
      isSilentMandatoryReasoningStarve(
        finishReasonLength: true,
        emittedContent: false,
        askedToDisableThinking: true,
      ),
      isTrue,
    );
    expect(
      isSilentMandatoryReasoningStarve(
        finishReasonLength: true,
        emittedContent: true,
        askedToDisableThinking: true,
      ),
      isFalse,
      reason: 'length + any content must not learn',
    );
    expect(
      isSilentMandatoryReasoningStarve(
        finishReasonLength: false,
        emittedContent: false,
        askedToDisableThinking: true,
      ),
      isFalse,
      reason: 'no finish_reason:length must not learn',
    );
    expect(
      isSilentMandatoryReasoningStarve(
        finishReasonLength: true,
        emittedContent: false,
        askedToDisableThinking: false,
      ),
      isFalse,
      reason: 'thinking requested on is not this signal',
    );
  });

  test(
    'headroom-opted caller learns, retries with larger max_tokens, succeeds',
    () async {
      final seen = <_SeenPost>[];
      final server = await _startProvider([_starve, _ok], seen);
      addTearDown(() => server.close(force: true));

      final out = await _collect(_svc(server.port), _chargenParams());

      expect(out, contains('Mara'));
      expect(seen.length, 2, reason: 'exactly one post-learn retry');
      expect(seen.first.maxTokens, _chargenCap);
      expect(
        seen.last.maxTokens,
        _chargenCap + kMandatoryReasoningThinkHeadroomTokens,
      );
      expect(seen.first.reasoning['exclude'], true);
      expect(seen.last.reasoning['exclude'], true);
      expect(kMandatoryReasoningModels.contains(_model), isTrue);
    },
  );

  test(
    'plain-chat caller may learn but keeps its own cap and stays empty',
    () async {
      final seen = <_SeenPost>[];
      final server = await _startProvider([_starve, _ok], seen);
      addTearDown(() => server.close(force: true));

      final out = await _collect(_svc(server.port), _chatParams());

      expect(out, isEmpty);
      expect(seen.length, 1, reason: 'chat does not retry with headroom');
      expect(seen.single.maxTokens, _chargenCap);
      expect(kMandatoryReasoningModels.contains(_model), isTrue);
    },
  );

  test('normal model within budget is never flagged', () async {
    final seen = <_SeenPost>[];
    final server = await _startProvider([_ok], seen);
    addTearDown(() => server.close(force: true));

    final out = await _collect(_svc(server.port), _chargenParams());
    expect(out, contains('Mara'));
    expect(seen.length, 1);
    expect(kMandatoryReasoningModels.contains(_model), isFalse);
  });

  test(
    'length + whitespace-only content learns and retries with headroom',
    () async {
      expect(contentDeltaCountsAsEmitted('\n'), isFalse);
      expect(contentDeltaCountsAsEmitted('   '), isFalse);
      expect(contentDeltaCountsAsEmitted('\n  \t'), isFalse);
      expect(contentDeltaCountsAsEmitted('Mar'), isTrue);

      final seen = <_SeenPost>[];
      final server = await _startProvider([
        const _SseReply(finishReason: 'length', content: '\n'),
        _ok,
      ], seen);
      addTearDown(() => server.close(force: true));

      final out = await _collect(_svc(server.port), _chargenParams());
      expect(out, contains('Mara'));
      expect(seen.length, 2);
      expect(seen.first.maxTokens, _chargenCap);
      expect(
        seen.last.maxTokens,
        _chargenCap + kMandatoryReasoningThinkHeadroomTokens,
      );
      expect(seen.last.reasoning['exclude'], true);
      expect(kMandatoryReasoningModels.contains(_model), isTrue);
    },
  );

  test('length + spaces-only content is the same silent starve', () async {
    final seen = <_SeenPost>[];
    final server = await _startProvider([
      const _SseReply(finishReason: 'length', content: '  \t  '),
      _ok,
    ], seen);
    addTearDown(() => server.close(force: true));

    final out = await _collect(_svc(server.port), _chargenParams());
    expect(out, contains('Mara'));
    expect(seen.length, 2);
    expect(seen.last.reasoning['exclude'], true);
    expect(kMandatoryReasoningModels.contains(_model), isTrue);
  });

  test(
    'guided-helper-shaped caller (name roll) learns, retries, exclude stays',
    () async {
      final seen = <_SeenPost>[];
      final server = await _startProvider([_starve, _ok], seen);
      addTearDown(() => server.close(force: true));

      const guided = GenerationParams(
        prompt: 'Generate ONE unique name as JSON.',
        maxLength: 128,
        reasoningEnabled: false,
        reasoningMaxTokens: 0,
        mandatoryReasoningHeadroom: true,
      );
      final out = await _collect(_svc(server.port), guided);
      expect(out, contains('Mara'));
      expect(seen.length, 2);
      expect(seen.first.maxTokens, 128);
      expect(seen.last.maxTokens, 128 + kMandatoryReasoningThinkHeadroomTokens);
      expect(seen.last.reasoning['exclude'], true);
    },
  );

  test('length + partial content does not learn', () async {
    final seen = <_SeenPost>[];
    final server = await _startProvider([
      const _SseReply(finishReason: 'length', content: 'Mar'),
    ], seen);
    addTearDown(() => server.close(force: true));

    final out = await _collect(_svc(server.port), _chargenParams());
    expect(out, contains('Mar'));
    expect(seen.length, 1);
    expect(kMandatoryReasoningModels.contains(_model), isFalse);
  });

  test('stop + empty does not learn', () async {
    final seen = <_SeenPost>[];
    final server = await _startProvider([
      const _SseReply(finishReason: 'stop'),
    ], seen);
    addTearDown(() => server.close(force: true));

    final out = await _collect(_svc(server.port), _chargenParams());
    expect(out, isEmpty);
    expect(seen.length, 1);
    expect(kMandatoryReasoningModels.contains(_model), isFalse);
  });

  test(
    'connection-close without finish_reason:length + empty does not learn',
    () async {
      final seen = <_SeenPost>[];
      final server = await _startProvider([
        const _SseReply(writeDone: false),
      ], seen);
      addTearDown(() => server.close(force: true));

      final out = await _collect(_svc(server.port), _chargenParams());
      expect(out, isEmpty);
      expect(seen.length, 1);
      expect(kMandatoryReasoningModels.contains(_model), isFalse);
    },
  );

  test('transport error does not learn', () async {
    final seen = <_SeenPost>[];
    final server = await _startProvider([const _SseReply(status: 500)], seen);
    addTearDown(() => server.close(force: true));

    await expectLater(
      _collect(_svc(server.port), _chargenParams()),
      throwsA(isA<Exception>()),
    );
    expect(kMandatoryReasoningModels.contains(_model), isFalse);
  });

  test('already mandatory: one retry max, then fail closed', () async {
    rememberMandatoryReasoning(_model);
    final seen = <_SeenPost>[];
    final server = await _startProvider([_starve, _starve, _starve], seen);
    addTearDown(() => server.close(force: true));

    await expectLater(
      _collect(_svc(server.port), _chargenParams()),
      throwsA(isA<SilentMandatoryReasoningStarveException>()),
    );
    expect(seen.length, 2, reason: 'one retry, not a learn↔retry loop');
    expect(
      seen.first.maxTokens,
      _chargenCap + kMandatoryReasoningThinkHeadroomTokens,
    );
    expect(seen.last.maxTokens, seen.first.maxTokens);
    expect(seen.last.reasoning['exclude'], true);
  });

  test('headroom retry that still starves fails closed once', () async {
    final seen = <_SeenPost>[];
    final server = await _startProvider([_starve, _starve, _starve], seen);
    addTearDown(() => server.close(force: true));

    await expectLater(
      _collect(_svc(server.port), _chargenParams()),
      throwsA(isA<SilentMandatoryReasoningStarveException>()),
    );
    expect(seen.length, 2);
    expect(seen.first.maxTokens, _chargenCap);
    expect(
      seen.last.maxTokens,
      _chargenCap + kMandatoryReasoningThinkHeadroomTokens,
    );
    expect(seen.last.reasoning['exclude'], true);
    expect(kMandatoryReasoningModels.contains(_model), isTrue);
  });
}
