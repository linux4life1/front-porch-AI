// The slot keeper's rules, against a stand-in for KoboldCpp's four calls that
// keeps slots the way the engine does: a save copies the cache it holds, a
// load brings it back, an empty slot cannot be loaded.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';

class _Api implements KoboldSlotApi {
  _Api({int slots = 5}) : slotTokens = List.filled(slots, 0);

  final List<String> calls = [];

  /// Tokens saved in each slot, and in the cache now.
  final List<int> slotTokens;
  int live = 0;

  bool checkOk = true;
  bool saveOk = true;
  bool clearOk = true;
  Object? failNext;
  Object? failLoadsWith;

  void _maybeFail() {
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
  }

  @override
  Future<KoboldSlotCheck> check() async {
    calls.add('check');
    _maybeFail();
    return KoboldSlotCheck(
      ok: checkOk,
      slotTokens: checkOk ? List.of(slotTokens) : const [],
      liveTokens: live,
    );
  }

  @override
  Future<KoboldSlotLoad> load(int slot) async {
    calls.add('load:$slot');
    _maybeFail();
    final error = failLoadsWith;
    if (error != null) throw error;
    if (slotTokens[slot] == 0) return KoboldSlotLoad(ok: false, tokens: live);
    live = slotTokens[slot];
    return KoboldSlotLoad(ok: true, tokens: live);
  }

  @override
  Future<KoboldSlotSave> save(int slot) async {
    calls.add('save:$slot');
    _maybeFail();
    if (!saveOk) return KoboldSlotSave(ok: false, tokens: live);
    slotTokens[slot] = live;
    return KoboldSlotSave(ok: live > 0, bytes: live * 100, tokens: live);
  }

  @override
  Future<bool> clear() async {
    calls.add('clear');
    _maybeFail();
    if (clearOk) slotTokens.fillRange(0, slotTokens.length, 0);
    return clearOk;
  }
}

void main() {
  late _Api api;
  late int generation;
  late KoboldKeeperPlan plan;
  late int plansAsked;
  late int locked;
  late List<String> log;
  late List<String> failures;
  late KoboldSlotKeeper keeper;

  KoboldSlotKeeper build() => KoboldSlotKeeper(
    api: api,
    loadGeneration: () => generation,
    plan: () async {
      plansAsked++;
      return plan;
    },
    underSwapLock: <T>(work) {
      locked++;
      return work();
    },
    log: log.add,
    onFailure: failures.add,
  );

  setUp(() {
    api = _Api();
    generation = 1;
    plan = const KoboldKeeperPlan.keep(3);
    plansAsked = 0;
    locked = 0;
    log = [];
    failures = [];
    keeper = build();
  });

  /// One reply of [chat] that leaves [tokens] in the engine's cache.
  Future<void> reply(String chat, int tokens, {bool ok = true}) async {
    await keeper.chatStart(chat);
    api.live = tokens;
    await keeper.chatEnd(chat, ok: ok);
  }

  test(
    'the first reply looks at the engine once, then keeps its chat',
    () async {
      await reply('A', 500);

      expect(api.calls, ['check', 'save:0']);
      expect(api.slotTokens[0], 500);
      expect(log, hasLength(1));
      expect(log.single, contains('Keeping up to 3 chats'));
    },
  );

  test('a chat that is still in the engine is not loaded again', () async {
    await reply('A', 500);
    api.calls.clear();

    await keeper.chatStart('A');

    expect(api.calls, isEmpty);
  });

  test('a helper in between makes the next reply load the chat back', () async {
    await reply('A', 500);
    api.calls.clear();

    keeper.helperStart();
    api.live = 80; // what the helper left in the cache
    await keeper.chatStart('A');

    expect(api.calls, ['load:0']);
    expect(api.live, 500);
  });

  test('a chat that was never saved loads nothing', () async {
    await reply('A', 500);
    api.calls.clear();

    keeper.helperStart();
    await keeper.chatStart('B');

    expect(api.calls, isEmpty);
  });

  test(
    'three chats in two slots: the one used longest ago makes room',
    () async {
      plan = const KoboldKeeperPlan.keep(2);
      await reply('A', 100);
      await reply('B', 200);
      keeper.helperStart();
      await reply('A', 150); // A is newer than B now
      api.calls.clear();

      await reply('C', 300);

      expect(api.calls, ['save:1'], reason: 'B had the slot used longest ago');
      expect(api.slotTokens.take(2), [150, 300]);
      keeper.helperStart();
      api.calls.clear();
      await keeper.chatStart('B');
      expect(api.calls, isEmpty, reason: 'B is gone');
      await keeper.chatStart('A');
      expect(api.calls, ['load:0']);
    },
  );

  test("the chats kept never exceed the engine's slots", () async {
    api = _Api(slots: 2);
    plan = const KoboldKeeperPlan.keep(5);
    keeper = build();

    await reply('A', 100);
    await reply('B', 100);
    await reply('C', 100);

    expect(log.first, contains('Keeping up to 2 chats'));
    expect(api.calls.where((c) => c.startsWith('save')), [
      'save:0',
      'save:1',
      'save:0',
    ]);
  });

  test('a slot that came back empty drops only that chat', () async {
    await reply('A', 100);
    await reply('B', 200);
    keeper.helperStart();
    api.slotTokens[0] = 0; // A's slot was lost
    api.calls.clear();

    await keeper.chatStart('A');
    keeper.helperStart();
    await keeper.chatStart('B');

    expect(api.calls, ['load:0', 'load:1']);
    expect(api.live, 200, reason: 'B still comes back');
    keeper.helperStart();
    api.calls.clear();
    await keeper.chatStart('A');
    expect(api.calls, isEmpty, reason: 'A is no longer tried');
  });

  test('a save that fails steps aside and gives the memory back', () async {
    await reply('A', 100);
    api.saveOk = false;
    await reply('B', 200);

    expect(api.calls.last, 'clear');
    expect(log.last, contains('no longer kept'));
    expect(failures, hasLength(1));
    api.calls.clear();
    await reply('A', 300);
    expect(api.calls, isEmpty, reason: 'nothing more is asked of the engine');
  });

  test('a save of an empty cache is not a failure', () async {
    await keeper.chatStart('A');
    api.live = 0;
    api.saveOk = false;
    await keeper.chatEnd('A', ok: true);

    expect(failures, isEmpty);
    expect(api.calls, ['check', 'save:0']);
  });

  test('a chat that comes back with another size steps aside', () async {
    await reply('A', 500);
    keeper.helperStart();
    api.slotTokens[0] = 900; // someone else saved over it

    await keeper.chatStart('A');

    expect(log.last, contains('no longer kept'));
    expect(failures, hasLength(1));
  });

  test('a chat that comes back one or two tokens off is accepted', () async {
    await reply('A', 500);
    keeper.helperStart();
    api.slotTokens[0] = 502;

    await keeper.chatStart('A');

    expect(failures, isEmpty);
    expect(api.calls.last, 'load:0');
  });

  test(
    'an engine that fails a call steps aside; one that is busy does not',
    () async {
      await reply('A', 500);
      keeper.helperStart();

      api.failNext = const KoboldSlotException('busy', busy: true);
      await keeper.chatStart('A');
      expect(failures, isEmpty, reason: 'busy is only skipped this time');

      await keeper.chatStart('A');
      expect(api.calls.last, 'load:0', reason: 'the chat is still kept');

      keeper.helperStart();
      api.failNext = const KoboldSlotException('connection lost');
      await keeper.chatStart('A');
      expect(failures, ['connection lost']);
    },
  );

  test('a new load empties the table without asking the engine', () async {
    await reply('A', 500);
    api.calls.clear();

    generation = 2;
    api.slotTokens.fillRange(0, api.slotTokens.length, 0); // a new engine
    keeper.helperStart();
    await keeper.chatStart('A');

    expect(api.calls, ['check'], reason: 'only the look at the new engine');
    expect(plansAsked, 2);
    api.calls.clear();
    await keeper.chatEnd('A', ok: true);
    expect(api.calls, ['save:0']);
  });

  test('the plan is asked once for each load', () async {
    await reply('A', 100);
    await reply('B', 100);
    await reply('A', 100);

    expect(plansAsked, 1);
  });

  test(
    'a plan that keeps nothing means no calls, and one line saying why',
    () async {
      plan = const KoboldKeeperPlan.off('Not for this model.');

      await reply('A', 500);
      await reply('A', 500);

      expect(api.calls, isEmpty);
      expect(log, ['Not for this model.']);
      expect(failures, isEmpty);
    },
  );

  test('a plan that is not known yet is asked again next time', () async {
    plan = const KoboldKeeperPlan.later();
    await reply('A', 100);
    expect(api.calls, isEmpty);

    plan = const KoboldKeeperPlan.keep(2);
    await reply('A', 100);

    expect(api.calls, ['check', 'save:0']);
  });

  test('an engine that already holds chats of its own is left alone', () async {
    api.slotTokens[3] = 4000;

    await reply('A', 500);

    expect(api.calls, ['check']);
    expect(log.single, contains('left alone'));
    expect(failures, isEmpty, reason: 'not the engine failing');
  });

  test('an engine that will not keep chats steps aside and says so', () async {
    api.checkOk = false;

    await reply('A', 500);

    expect(api.calls, ['check']);
    expect(failures, hasLength(1));
  });

  test(
    'an outside client makes the keeper wait, and it picks up after',
    () async {
      await reply('A', 500);
      api.calls.clear();

      keeper.outsideStart();
      await keeper.chatStart('A');
      await keeper.chatEnd('A', ok: true);
      expect(api.calls, isEmpty);

      keeper.outsideEnd();
      api.live = 90;
      await keeper.chatStart('A');
      expect(api.calls, ['load:0'], reason: 'the saved chat is still there');
    },
  );

  test('a reply that failed is not saved, and the next one loads', () async {
    await reply('A', 500);
    keeper.helperStart();
    await keeper.chatStart('A');
    api.calls.clear();
    api.live = 40;

    await keeper.chatEnd('A', ok: false);
    await keeper.chatStart('A');

    expect(api.calls, ['load:0'], reason: 'no save, so the old one is loaded');
    expect(api.slotTokens[0], 500);
  });

  test('a chat that was forgotten is not loaded', () async {
    await reply('A', 500);
    keeper.helperStart();

    keeper.forget('A');
    api.calls.clear();
    await keeper.chatStart('A');

    expect(api.calls, isEmpty);
  });

  test(
    'every call runs in the swap lock, and not once the model has changed',
    () async {
      await reply('A', 500);
      expect(locked, 2, reason: 'the look and the save');

      api.calls.clear();
      final changing = KoboldSlotKeeper(
        api: api,
        loadGeneration: () => generation,
        plan: () async => plan,
        underSwapLock: <T>(work) async {
          generation++; // a swap got in first
          return work();
        },
        log: log.add,
      );
      await changing.chatStart('A');

      expect(api.calls, isEmpty, reason: 'the engine changed before the call');
    },
  );

  test(
    'something unexpected inside the keeper never reaches the reply',
    () async {
      api.failNext = StateError('a bug');

      await reply('A', 500);

      expect(failures, hasLength(1));
      expect(log.last, contains('no longer kept'));
    },
  );
}
