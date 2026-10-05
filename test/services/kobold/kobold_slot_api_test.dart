// The four calls over real HTTP, against the engine stand-in on a loopback
// socket: what KoboldCpp answers is read the way the keeper needs it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';

import '../../helpers/fake_kobold_engine.dart';

void main() {
  late FakeKoboldEngine engine;
  late KoboldHttpSlotApi api;

  setUp(() async {
    HttpOverrides.global = null;
    engine = await FakeKoboldEngine.start();
    api = KoboldHttpSlotApi(() => engine.baseUrl);
  });

  tearDown(() => engine.close());

  test('check counts the slots and what is in each', () async {
    engine.live = ['a', 'b', 'c'];
    await api.save(2);

    final check = await api.check();

    expect(check.ok, isTrue);
    expect(check.slotTokens, [0, 0, 3, 0, 0]);
    expect(check.liveTokens, 3);
  });

  test('a save copies the cache and a load brings it back', () async {
    engine.live = List.filled(40, 'w');
    final saved = await api.save(1);
    expect(saved.ok, isTrue);
    expect(saved.tokens, 40);
    expect(saved.bytes, 40 * engine.bytesPerToken);

    engine.live = ['x'];
    final loaded = await api.load(1);
    expect(loaded.ok, isTrue);
    expect(loaded.tokens, 40);
    expect(engine.live, hasLength(40));
  });

  test('an empty slot cannot be loaded, and says so without failing', () async {
    final loaded = await api.load(3);

    expect(loaded.ok, isFalse);
  });

  test(
    'a save that runs out of memory answers not ok, with the cache size',
    () async {
      engine.live = ['a', 'b'];
      engine.failSaves = true;

      final saved = await api.save(0);

      expect(saved.ok, isFalse);
      expect(saved.tokens, 2);
    },
  );

  test('clear frees every slot', () async {
    engine.live = ['a'];
    await api.save(0);
    await api.save(4);

    expect(await api.clear(), isTrue);

    expect((await api.check()).slotTokens, [0, 0, 0, 0, 0]);
  });

  test('an engine without admin answers not ok, with no slots', () async {
    engine.adminOn = false;

    final check = await api.check();

    expect(check.ok, isFalse);
    expect(check.slotTokens, isEmpty);
    expect((await api.save(0)).ok, isFalse);
    expect((await api.load(0)).ok, isFalse);
    expect(await api.clear(), isFalse);
  });

  test('a busy engine is told apart from one that failed', () async {
    engine.loadStatus = 503;
    await expectLater(
      api.load(0),
      throwsA(isA<KoboldSlotException>().having((e) => e.busy, 'busy', isTrue)),
    );

    engine.loadStatus = 500;
    await expectLater(
      api.load(0),
      throwsA(
        isA<KoboldSlotException>().having((e) => e.busy, 'busy', isFalse),
      ),
    );
  });

  test('an engine that is gone is a failure, not a hang', () async {
    await engine.close();

    await expectLater(api.check(), throwsA(isA<KoboldSlotException>()));
  });

  test('a call that is not answered in time is a failure', () async {
    final slow = KoboldHttpSlotApi(
      () => engine.baseUrl,
      timeout: const Duration(milliseconds: 100),
    );
    engine.beforeReply = (_) =>
        Future<void>.delayed(const Duration(seconds: 1));
    // A chat holds the engine's lock; the call waits behind it, as it would
    // in KoboldCpp.
    final holding = HttpClient()
        .postUrl(Uri.parse('${engine.baseUrl}/v1/chat/completions'))
        .then((r) {
          r.write(
            '{"stream":false,"messages":[{"role":"user","content":"x"}]}',
          );
          return r.close();
        });
    while (engine.arrived.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    await expectLater(slow.check(), throwsA(isA<KoboldSlotException>()));
    await holding;
  });
}
