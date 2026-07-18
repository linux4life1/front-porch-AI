// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for fireVisionEval — the one-shot multimodal eval used by Vision QC
// and describePortrait. Driven through a minimal fake LLMService so the
// drain/strip/param-carrying behavior is proven without any transport.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/vision_eval.dart';

class FakeLlm extends LLMService {
  FakeLlm({this.chunks = const [], this.throws = false});

  final List<String> chunks;
  final bool throws;
  GenerationParams? lastParams;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    lastParams = params;
    if (throws) throw Exception('backend fell over');
    for (final chunk in chunks) {
      yield chunk;
    }
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'Fake';
}

void main() {
  test('drains the stream and strips think blocks', () async {
    final llm = FakeLlm(
      chunks: ['<think>let me pon', 'der</think>', '{"same_person": true}'],
    );
    final result = await fireVisionEval(
      llm: llm,
      prompt: 'compare',
      imagesB64: const ['QUFB'],
    );
    expect(result, '{"same_person": true}');
  });

  test('empty and think-only replies return null', () async {
    expect(
      await fireVisionEval(
        llm: FakeLlm(chunks: ['   ']),
        prompt: 'compare',
        imagesB64: const ['QUFB'],
      ),
      isNull,
    );
    expect(
      await fireVisionEval(
        llm: FakeLlm(chunks: ['<think>all thought, no answer']),
        prompt: 'compare',
        imagesB64: const ['QUFB'],
      ),
      isNull,
    );
  });

  test('a throwing stream returns null instead of surfacing', () async {
    expect(
      await fireVisionEval(
        llm: FakeLlm(throws: true),
        prompt: 'compare',
        imagesB64: const ['QUFB'],
      ),
      isNull,
    );
  });

  test('params carry the images and the eval posture', () async {
    final llm = FakeLlm(chunks: ['ok']);
    await fireVisionEval(
      llm: llm,
      prompt: 'compare these',
      imagesB64: const ['QUFB', 'QkJC'],
    );

    final p = llm.lastParams!;
    expect(p.prompt, 'compare these');
    expect(p.images, ['QUFB', 'QkJC']);
    expect(p.maxLength, 1000); // contract default
    expect(p.temperature, 0.1);
    expect(p.repeatPenalty, 1.15);
    expect(p.topP, 0.5);
    expect(p.xtcProbability, 0.0);
    expect(p.reasoningEnabled, isFalse);
    expect(p.reasoningMaxTokens, 0); // the "thinking off" knob for remotes
    expect(p.stopSequences, isEmpty);
  });

  test('maxLength override is honored', () async {
    final llm = FakeLlm(chunks: ['ok']);
    await fireVisionEval(
      llm: llm,
      prompt: 'describe',
      imagesB64: const ['QUFB'],
      maxLength: 400,
    );
    expect(llm.lastParams!.maxLength, 400);
  });
}
