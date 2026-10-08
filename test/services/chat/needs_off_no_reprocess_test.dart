// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Reprocess Needs and its revert are Needs runs: a judge call and a rewrite
// of the live bars. With the Realism engine off, or the global Needs switch
// off, the chip offers neither and the service refuses both; desktop and
// the PWA read the same rule (reprocessNeedsTargetFor, needsRevertable).
// The chat keeps its chips and the stash of an earlier correction: Needs
// hide, they do not erase, and the correction waits for Needs to come back.

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/reprocess_needs_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
  });
  tearDown(() => h.dispose());

  test(
    'Realism off: the reply keeps its chip, but it cannot be reprocessed',
    () async {
      final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
      expect(h.chat.reprocessNeedsTargetFor(i), isNotNull);

      await h.chat.setRealismEnabled(false);
      expect(h.chat.needsSimEnabled, isTrue, reason: 'the chat switch stays');
      expect(h.chat.reprocessNeedsTargetFor(i), isNull);
      expect(await h.chat.manualReprocessNeeds(i, 'she had eaten'), isFalse);
      expect(h.llm.reprocessPrompts, isEmpty, reason: 'no judge ran');

      await h.chat.setRealismEnabled(true);
      expect(
        h.chat.reprocessNeedsTargetFor(i),
        isNotNull,
        reason: 'the engine back on, the chip offers it again',
      );
    },
  );

  test('the global Needs switch off: no reprocess, and no revert of an '
      'earlier one until it is back on', () async {
    final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
    expect(await h.chat.manualReprocessNeeds(i, 'she had eaten'), isTrue);
    final corrected = Map<String, int>.from(h.chat.needsSimulation.vector);

    await h.storage.realismSettings.setNeedsSimDefault(false);
    expect(h.chat.reprocessNeedsTargetFor(i), isNull);
    expect(await h.chat.revertNeedsReprocess(i), isFalse);
    expect(h.chat.needsSimulation.vector, corrected, reason: 'nothing moved');
    expect(
      h.chat.messages[i].activeMetadata?['needs_deltas_pre_reprocess'],
      isA<Map>(),
      reason: 'the stash is kept, not erased',
    );

    await h.storage.realismSettings.setNeedsSimDefault(true);
    expect(await h.chat.revertNeedsReprocess(i), isTrue);
    expect(h.chat.needsSimulation.vector, isNot(corrected));
  });
}
