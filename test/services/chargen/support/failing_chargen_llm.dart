// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The marker model with a backend that fails on one step: any prompt
// containing [failOn] throws, the way a dead connection does, so the real
// retry loop runs and gives up.

import 'package:front_porch_ai/services/llm_service.dart';

import 'marker_chargen_llm.dart';

class FailingChargenLlm extends MarkerChargenLlm {
  FailingChargenLlm({required this.failOn, this.error = 'connection refused'});

  /// Prompts containing this throw once the flag [failing] is on.
  final String failOn;
  final String error;

  /// Off while a test builds its paused run; on for the step under test.
  bool failing = false;
  int failures = 0;

  @override
  Stream<String> generateStream(GenerationParams params) {
    if (failing && params.prompt.contains(failOn)) {
      prompts.add(params.prompt);
      onPrompt?.call(params.prompt);
      failures++;
      return Stream.error(Exception(error));
    }
    return super.generateStream(params);
  }
}
