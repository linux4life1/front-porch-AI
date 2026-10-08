// A save that never answers lets every chat go for the load: what its slot
// holds is not known, and an engine that cannot save in time is short of
// something. Not a failure of the keeper, so nothing is remembered. (How
// long a save that does answer takes decides nothing: the open chat is
// always kept, chat_keeper_always_saves_test.)

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import '../../helpers/kobold_engine_harness.dart';

void main() {
  late KoboldEngineHarness h;

  setUp(() async {
    h = await KoboldEngineHarness.start();
    addTearDown(h.dispose);
  });

  test('a save that does not answer in time lets every chat go for the load, '
      'since what its slot holds is not known; it is not a failure', () async {
    final failures = <String>[];
    final logs = <String>[];
    final keeper = KoboldSlotKeeper(
      api: KoboldHttpSlotApi(
        () => h.engine.baseUrl,
        timeout: const Duration(milliseconds: 300),
      ),
      loadGeneration: () => 1,
      plan: () async => const KoboldKeeperPlan.keep(3),
      underSwapLock: <T>(work) => work(),
      log: logs.add,
      onFailure: failures.add,
    );
    final held = Completer<void>();
    addTearDown(() {
      if (!held.isCompleted) held.complete();
    });
    h.engine.beforeAdmin = (r) => r.kind == 'save' && !held.isCompleted
        ? held.future
        : Future<void>.value();
    h.engine.live = ['a', 'long', 'chat'];

    await keeper.chatStart('A');
    await keeper.chatEnd('A', ok: true);

    expect(failures, isEmpty, reason: 'remembered as a failure');
    expect(keeper.kept, 0);
    expect(keeper.chats, 0, reason: 'still keeping the other chats');
    expect(logs.last, contains('did not finish saving a chat in time'));

    // The engine finishes the save it was asked for in the end; nothing more
    // is asked of it for this load.
    held.complete();
    for (var i = 0; i < 200 && h.engine.of('save').first.endedAt == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    h.engine.forgetLog();
    await keeper.chatStart('B');
    h.engine.live = ['a', 'short', 'one'];
    await keeper.chatEnd('B', ok: true);
    expect(h.engine.arrived, isEmpty);
    expect(failures, isEmpty);
  });
}
