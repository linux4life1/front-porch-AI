// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The rule behind the ROCm flash attention fallback being for the first
// reply only (rocm_first_reply_only_test runs it on a real process): a
// finished reply is KoboldCpp's "CtxLimit:" line, and only a crash before
// one starts the engine again without flash attention.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

/// A finished reply, as KoboldCpp prints it.
const _replyDone =
    '[09:59:50] CtxLimit:290/16384, Init:0.15s, Processed:240 in 34.03s '
    '(7.05T/s), Generated:50/64 in 2.10s (23.81T/s), Total:36.13s';

void main() {
  test('a finished reply is KoboldCpp\'s CtxLimit line, and nothing before '
      'it', () {
    expect(koboldReplyFinishedIn(_replyDone), isTrue);
    expect(koboldReplyFinishedIn('\n$_replyDone\n'), isTrue);
    for (final line in [
      'Load Text Model OK: True',
      'Starting model warm up, please wait a moment...',
      'Please connect to custom endpoint at http://localhost:5001',
      'Processing Prompt [BATCH] (512 / 2156 tokens)',
      'Generating (50 / 64 tokens)',
    ]) {
      expect(koboldReplyFinishedIn(line), isFalse, reason: line);
    }
  });

  test('a reply\'s last line that arrives in two reads is seen whole', () {
    final lines = KoboldOutputLines();
    bool finished(String read) => lines.add(read).any(koboldReplyFinishedIn);

    expect(finished('Generating (50 / 64 tokens)\n[09:59:50] Ctx'), isFalse);
    expect(finished('Limit:290/16384, Init:0.15s'), isTrue);
    // The next print ends that line, and starts another.
    expect(lines.add('\nProcessing Prompt [BATCH] (512 / 2156 tokens)'), [
      '[09:59:50] CtxLimit:290/16384, Init:0.15s',
      'Processing Prompt [BATCH] (512 / 2156 tokens)',
    ]);
  });

  test('the line still being written is read as it stands, since KoboldCpp '
      'ends it only when it next prints', () {
    final lines = KoboldOutputLines();

    expect(lines.add('\n[09:59:50] CtxLimit:2'), ['', '[09:59:50] CtxLimit:2']);
    expect(lines.add('90/16384'), ['[09:59:50] CtxLimit:290/16384']);
    expect(lines.add('\nnext'), ['[09:59:50] CtxLimit:290/16384', 'next']);
  });

  test('only a crash before any reply finished starts again without flash '
      'attention', () {
    const died = KoboldFailure(KoboldFailureKind.diedWhileAnswering, '');
    bool retry({required bool replyFinished}) =>
        koboldRetryWithoutFlashAttention(
          failure: died,
          rocmWithFlashAttention: true,
          alreadyMarked: false,
          replyFinished: replyFinished,
        );

    expect(retry(replyFinished: false), isTrue);
    expect(retry(replyFinished: true), isFalse);
  });
}
