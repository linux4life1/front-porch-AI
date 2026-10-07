// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The judges' answers for the refractory suites. It only answers questions
// (how many story minutes passed, did the speaker climax and for how many
// turns); every refractory number those suites assert is the product's.

import 'dart:convert';

import 'package:front_porch_ai/services/services.dart';

class RefractoryJudges extends LLMService {
  /// Story minutes the scene-time judge reports; 0 is the same moment.
  int minutes = 5;
  bool climax = false;
  int refractoryTurns = 5;

  /// Every reply prompt (system + body) and every judge prompt, in order.
  final replyPrompts = <String>[];
  final judgePrompts = <String>[];

  bool get lastReplyWasOpening =>
      replyPrompts.isNotEmpty &&
      replyPrompts.last.contains('just climaxed — still trembling');

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (params.systemPrompt != null) {
      replyPrompts.add('${params.systemPrompt}\n$p');
      // Never names a time, so the clock moves only by [minutes] or a skip.
      yield '*She settles against the porch rail, unhurried.*';
      return;
    }
    judgePrompts.add(p);
    if (p.contains('"is_climax"')) {
      yield jsonEncode({
        'is_climax': climax,
        'refractory_turns': climax ? refractoryTurns : 0,
        'posture': 'none',
      });
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield jsonEncode({
        'minutes_elapsed': minutes,
        'continuous_instant': minutes == 0,
        'new_day': false,
      });
      return;
    }
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"steady"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"content","emotion_intensity":"mild",'
          '"arousal_delta":0}';
      return;
    }
    if (p.contains('fixation_topic')) {
      yield '{"fixation_topic":"none","proposed_objective":"none"}';
      return;
    }
    if (p.contains('"with_user"')) {
      yield '{"with_user":true}';
      return;
    }
    if (p.contains('current physical position and stance')) {
      yield '{"posture":"none"}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'RefractoryJudges';
}
