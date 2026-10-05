// Whether a chat is worth keeping: what keeping it costs (the save after each
// reply, which holds the line, and the load before the next one) against what
// it spares (reading the whole chat again), at the speed the engine itself
// reads. The same slow save keeps a long chat and lets a short one go; a first
// save into a slot never used, which also makes that slot's buffer, decides
// nothing; a chat let go is tried again as it grows.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';

class _Api implements KoboldSlotApi {
  final List<int> slotTokens = List.filled(5, 0);
  final List<int> saved = [];
  final List<int> loaded = [];
  int live = 0;

  /// How long a save and a load take, as the copy of a cache would.
  Duration saveTakes = Duration.zero;
  Duration loadTakes = Duration.zero;

  @override
  Future<KoboldSlotCheck> check() async => KoboldSlotCheck(
    ok: true,
    slotTokens: List.of(slotTokens),
    liveTokens: live,
  );

  @override
  Future<KoboldSlotLoad> load(int slot) async {
    await Future<void>.delayed(loadTakes);
    if (slotTokens[slot] == 0) return KoboldSlotLoad(ok: false, tokens: live);
    loaded.add(slot);
    live = slotTokens[slot];
    return KoboldSlotLoad(ok: true, tokens: live);
  }

  @override
  Future<KoboldSlotSave> save(int slot) async {
    await Future<void>.delayed(saveTakes);
    saved.add(slot);
    slotTokens[slot] = live;
    return KoboldSlotSave(ok: live > 0, bytes: live * 100, tokens: live);
  }

  @override
  Future<bool> clear() async => true;
}

void main() {
  late _Api api;
  late List<String> log;
  late List<String> failures;

  /// How long the engine takes to read a chat again: 1,000 tokens a second.
  late Duration? Function(int tokens) reading;

  KoboldSlotKeeper keeper({int chats = 3}) => KoboldSlotKeeper(
    api: api,
    loadGeneration: () => 1,
    plan: () async => KoboldKeeperPlan.keep(chats),
    underSwapLock: <T>(work) => work(),
    log: log.add,
    onFailure: failures.add,
    readTime: (tokens) => reading(tokens),
  );

  setUp(() {
    api = _Api();
    log = [];
    failures = [];
    reading = (tokens) => Duration(milliseconds: tokens);
  });

  /// A judge, then a reply of [chat] that leaves [tokens] in the cache.
  Future<void> reply(KoboldSlotKeeper k, String chat, int tokens) async {
    k.helperStart();
    await k.chatStart(chat);
    api.live = tokens;
    await k.chatEnd(chat, ok: true);
  }

  List<String> letGo() => [
    for (final l in log)
      if (l.contains('to read it again')) l,
  ];

  test(
    'the same slow save lets a short chat go and keeps a long one',
    () async {
      api
        ..saveTakes = const Duration(milliseconds: 300)
        ..loadTakes = const Duration(milliseconds: 100);
      final k = keeper();
      // The first saves only make the slots; the second ones decide.
      await reply(k, 'short', 200);
      await reply(k, 'long', 5000);
      await reply(k, 'short', 240); // 0.3 s and 0.1 s against 0.24 s
      await reply(k, 'long', 5040); // the same against 5 s

      expect(k.kept, 1);
      expect(letGo(), hasLength(1));
      expect(failures, isEmpty, reason: 'letting a chat go is not a failure');
      api.loaded.clear();
      await reply(k, 'long', 5080);
      await reply(k, 'short', 280);
      expect(api.loaded, [
        1,
      ], reason: 'the long chat loads, the short does not');
    },
  );

  test('the load before the next reply counts with the save', () async {
    api
      ..saveTakes = const Duration(milliseconds: 150)
      ..loadTakes = const Duration(milliseconds: 150);
    final k = keeper();
    await reply(k, 'A', 250);
    await reply(k, 'A', 250); // 0.15 s and 0.15 s against 0.25 s

    expect(k.kept, 0, reason: 'only the save was counted');
    expect(letGo(), hasLength(1));
  });

  test('a first save into a slot never used decides nothing: a slow first '
      'save and a quick second one keep the chat', () async {
    api.saveTakes = const Duration(milliseconds: 800);
    final k = keeper();
    await reply(k, 'A', 500); // 0.8 s, and a load as long, against 0.5 s
    expect(k.kept, 1, reason: 'the first save into a new slot decided');

    api.saveTakes = const Duration(milliseconds: 20);
    await reply(k, 'A', 540);
    expect(k.kept, 1);
    expect(letGo(), isEmpty);
  });

  test('before the engine has read anything big enough to time, a chat is '
      'kept however slow its save', () async {
    reading = (_) => null;
    api.saveTakes = const Duration(milliseconds: 300);
    final k = keeper();
    await reply(k, 'A', 100);
    await reply(k, 'A', 120);
    expect(k.kept, 1);
    expect(letGo(), isEmpty);
  });

  test('a chat let go is tried again as it grows, after 2 and then 4 more '
      'replies, and kept once reading it again costs more', () async {
    api
      ..saveTakes = const Duration(milliseconds: 300)
      ..loadTakes = const Duration(milliseconds: 100);
    final k = keeper();
    await reply(k, 'A', 200);
    await reply(k, 'A', 250); // let go
    expect(k.kept, 0);

    api.saved.clear();
    await reply(k, 'A', 300);
    expect(api.saved, isEmpty, reason: 'saved again at once');
    await reply(k, 'A', 350); // tried: still 0.6 s against 0.35 s
    expect(api.saved, hasLength(1));
    expect(k.kept, 0);
    for (final tokens in [400, 450, 500]) {
      await reply(k, 'A', tokens);
    }
    expect(api.saved, hasLength(1), reason: 'tried before 4 more replies');
    await reply(k, 'A', 2000); // grown: 0.6 s against 2 s
    expect(api.saved, hasLength(2));
    expect(k.kept, 1);
    expect(letGo(), hasLength(1), reason: 'said once, not at every try');
  });

  test('every slot in use: a chat let go after its save took the oldest '
      'chat\'s slot leaves with that chat; the others stay', () async {
    api
      ..saveTakes = const Duration(milliseconds: 300)
      ..loadTakes = const Duration(milliseconds: 100);
    final k = keeper(chats: 2);
    await reply(k, 'A', 5000);
    await reply(k, 'B', 5000);
    await reply(k, 'C', 200); // into A's slot, written before: it decides

    expect(api.saved.last, 0, reason: 'C did not take A\'s slot');
    expect(k.kept, 1, reason: 'A is still counted, but C wrote over it');
    expect(letGo(), hasLength(1));
    api.loaded.clear();
    await reply(k, 'B', 5040);
    expect(api.loaded, [1]);
  });
}
