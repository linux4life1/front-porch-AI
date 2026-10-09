// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Two guards on Manual Reprocess → Feelings, over a real ChatService and the
// scripted model the reprocess suites share:
//  * a re-score that throws partway (here: the reply's stored state turns
//    unreadable while the judge is answering) leaves bond, trust and the
//    reply exactly as they were, and the chat is not left busy;
//  * while a re-score is running, Feelings is not on offer again — not from
//    the resolver, not in the phone's chips, not as a second pass.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart'
    show kFeelingsUnscoredMeta;
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';

import '../../helpers/reprocess_needs_harness.dart';

const _prose = 'She seems happier now, I think. Hard to say how much.';

/// The shared scripted model, with a hook on the bond/trust judge: answer
/// with prose, run [onJudge] first, or hold until [gate] completes.
class _JudgeHookLlm extends RecordingLlm {
  String? judgeAnswer;
  void Function()? onJudge;
  Completer<void>? gate;
  final judgeReached = Completer<void>();

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.prompt.contains('relationship_delta') &&
        !isReprocessPrompt(params.prompt)) {
      if (!judgeReached.isCompleted) judgeReached.complete();
      onJudge?.call();
      final g = gate;
      if (g != null) await g.future;
      final answer = judgeAnswer;
      if (answer != null) {
        yield answer;
        return;
      }
    }
    yield* super.generateStream(params);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  late _JudgeHookLlm llm;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
    llm = _JudgeHookLlm();
    h.chat.testLlmServiceOverride = llm;
  });
  tearDown(() => h.dispose());

  Map<String, dynamic> chipsOf(int index) {
    final facade = ChatFacade(h.chat, h.repo, null, null, null);
    final msgs = (facade.state()['messages'] as List)
        .cast<Map<String, dynamic>>();
    return Map<String, dynamic>.from(
      (msgs.firstWhere((m) => m['index'] == index)['chips'] as Map?) ??
          const {},
    );
  }

  test('a re-score that throws partway puts bond, trust and the reply back '
      'as they were', () async {
    llm.judgeAnswer = _prose;
    final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
    final meta = h.chat.messages[i].activeMetadata!;
    expect(meta[kFeelingsUnscoredMeta], isTrue, reason: 'baseline');
    final bond0 = h.chat.relationshipService.affectionScore;
    final trust0 = h.chat.relationshipService.trustLevel;

    // The judge answers (+1 trust), but by then the reply's stored state is
    // unreadable, so the pass throws after the new score reached the bars.
    llm.judgeAnswer = null;
    llm.onJudge = () => meta['realism_state'] = 'unreadable';
    final result = await h.chat.reprocessFeelings(i);
    await drainMicrotasks();

    expect(result, FeelingsRescore.unreadable);
    expect(h.chat.relationshipService.trustLevel, trust0);
    expect(h.chat.relationshipService.affectionScore, bond0);
    expect(meta[kFeelingsUnscoredMeta], isTrue, reason: 'chips unchanged');
    expect(meta.containsKey('trust_delta'), isFalse);
    expect(chipsOf(i)['feelingsUnscored'], isTrue);
    expect(h.chat.isSettlingTurn, isFalse, reason: 'input is not wedged');
    expect(h.chat.isEvaluatingRealism, isFalse);
  });

  test('while a re-score runs, Feelings is not on offer again', () async {
    final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
    expect(h.chat.reprocessFeelingsTargetFor(i), 'Mara', reason: 'baseline');
    expect(chipsOf(i)['feelingsReprocessable'], isTrue);

    llm.gate = Completer<void>();
    final running = h.chat.reprocessFeelings(i);
    await llm.judgeReached.future.timeout(const Duration(seconds: 30));

    expect(h.chat.reprocessFeelingsTargetFor(i), isNull);
    expect(chipsOf(i)['feelingsReprocessable'], isNull);
    expect(await h.chat.reprocessFeelings(i), FeelingsRescore.refused);

    llm.gate!.complete();
    expect(await running, FeelingsRescore.scored);
    await h.settleTurn();
    expect(h.chat.reprocessFeelingsTargetFor(i), 'Mara', reason: 'back after');
  });
}
