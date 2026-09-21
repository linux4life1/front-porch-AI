// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';

void main() {
  test('version-only HTTP 200 is not generation-ready', () {
    expect(
      koboldCompletionIsGenerationReady(
        200,
        '{"result":"KoboldCpp","version":"1.90"}',
      ),
      isFalse,
      reason: '/api/extra/version 200 must not unlock evals or speech',
    );
  });

  test('empty completion is not generation-ready', () {
    expect(
      koboldCompletionIsGenerationReady(
        200,
        '{"choices":[{"message":{"content":""},"finish_reason":"stop"}],'
        '"usage":{"completion_tokens":0}}',
      ),
      isFalse,
    );
    expect(
      koboldCompletionIsGenerationReady(200, '{"choices":[{"text":"\\n"}]}'),
      isFalse,
      reason: 'newline-only is the live len=1 empty stream',
    );
    expect(koboldCompletionIsGenerationReady(200, ''), isFalse);
  });

  test('tiny completion with assistant content is generation-ready', () {
    expect(
      koboldCompletionIsGenerationReady(
        200,
        '{"choices":[{"message":{"content":"ok"}}],'
        '"usage":{"completion_tokens":1}}',
      ),
      isTrue,
    );
    expect(
      koboldCompletionIsGenerationReady(200, '{"results":[{"text":"Hi"}]}'),
      isTrue,
    );
  });

  test('non-2xx completion is not generation-ready', () {
    expect(
      koboldCompletionIsGenerationReady(503, '{"choices":[{"text":"ok"}]}'),
      isFalse,
    );
  });
}
