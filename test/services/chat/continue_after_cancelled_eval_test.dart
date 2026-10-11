// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Continue extends the bubble on screen and does not re-eval, so it must
// not stamp whatever sits in the pending realism map: post-gen scratch
// from the reply it extends, or a cancelled regen's leftovers (1:1 regen
// judges, group regen dance).
//
// Proven red: merging _pendingRealismMetadata onto the Continue target in
// chat_service_generation_stream.dart fails the plain-Continue test alone.
// The cancel tests fail only when that merge AND both pending clears on
// the cancel path (cancelRealismEval's, plus the 1:1 regen or group dance
// cancel point's) are removed together: each clear alone is redundant.

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/reprocess_needs_harness.dart';

class _CancellingLlm extends RecordingLlm {
  Future<void> Function()? cancel;
  bool cancelAtEmotion = false;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (cancelAtEmotion && params.prompt.contains('emotion_intensity')) {
      cancelAtEmotion = false;
      // The other judges of the batch land first, as a user's late tap.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await cancel?.call();
      return;
    }
    yield* super.generateStream(params);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  late _CancellingLlm llm;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
    llm = _CancellingLlm()..cancel = () => h.chat.cancelRealismEval();
    h
      ..llm = llm
      ..chat.testLlmServiceOverride = llm;
  });
  tearDown(() => h.dispose());

  Map<String, dynamic> metaOf(int i) =>
      Map<String, dynamic>.from(h.chat.messages[i].activeMetadata ?? {});

  /// Continue on the tip, then: no key the accepted bubble lacked, and every
  /// accepted key as it was. needs_deltas is Continue's own score of the new
  /// text, so it may move.
  Future<void> continueKeeps(Map<String, dynamic> accepted) async {
    final tip = h.chat.messages.length - 1;
    await h.chat.continueGeneration();
    await h.settleTurn();
    expect(h.chat.messages.length - 1, tip);
    final after = metaOf(tip);
    expect(
      after.keys.where((k) => !accepted.containsKey(k)),
      isEmpty,
      reason: 'Continue stamped pending realism keys onto the bubble',
    );
    for (final k in accepted.keys.where((k) => k != 'needs_deltas')) {
      expect('${after[k]}', '${accepted[k]}', reason: k);
    }
  }

  test('Continue straight after a reply stamps no pending scratch', () async {
    final tip = await h.oneToOneWithStampedReply(needsCard('Nia'));
    await continueKeeps(metaOf(tip));
  });

  test('1:1 regen cancelled in the judges, then Continue', () async {
    final tip = await h.oneToOneWithStampedReply(needsCard('Nia'));
    final accepted = metaOf(tip);
    final text = h.chat.messages[tip].text;

    llm
      ..cancelAtEmotion = true
      ..liveNeedsReply = '{"hunger_delta": -30, "reason": "cancelled run"}';
    await h.chat.regenerateLastMessage();
    await h.settleTurn();
    expect(h.chat.messages.length - 1, tip);
    expect(h.chat.messages[tip].text, text, reason: 'the reply is put back');

    await continueKeeps(accepted);
  });

  test('group regen dance cancelled, then Continue', () async {
    final (_, bIndex) = await h.groupWithTwoReplies(aOff: const []);
    expect(bIndex, h.chat.messages.length - 1);
    final accepted = metaOf(bIndex);

    llm
      ..cancelAtEmotion = true
      ..liveNeedsReply = '{"hunger_delta": -30, "reason": "cancelled run"}';
    await h.chat.regenerateLastMessage();
    await h.settleTurn();
    expect(h.chat.messages.length - 1, bIndex);
    expect(h.chat.messages.last.sender, 'Bram');

    await continueKeeps(accepted);
  });
}
