// A chat that is deleted is let go by the keeper, also when the delete comes
// while the save of its reply is still running: that save must not bring the
// chat back into the table.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';

class _Api implements KoboldSlotApi {
  final List<int> slotTokens = List.filled(5, 0);
  final List<int> saved = [];
  int live = 0;

  /// While set, a save waits for it, as a copy of a big cache would.
  Completer<void>? hold;
  final Completer<void> saveStarted = Completer<void>();

  @override
  Future<KoboldSlotCheck> check() async => KoboldSlotCheck(
    ok: true,
    slotTokens: List.of(slotTokens),
    liveTokens: live,
  );

  @override
  Future<KoboldSlotLoad> load(int slot) async {
    if (slotTokens[slot] == 0) return KoboldSlotLoad(ok: false, tokens: live);
    live = slotTokens[slot];
    return KoboldSlotLoad(ok: true, tokens: live);
  }

  @override
  Future<KoboldSlotSave> save(int slot) async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    await hold?.future;
    saved.add(slot);
    slotTokens[slot] = live;
    return KoboldSlotSave(ok: live > 0, bytes: live * 100, tokens: live);
  }

  @override
  Future<bool> clear() async => true;
}

void main() {
  test('a chat deleted while its save is running is not kept when the save '
      'ends, and its slot is the next one used', () async {
    final api = _Api()..live = 500;
    final keeper = KoboldSlotKeeper(
      api: api,
      loadGeneration: () => 1,
      plan: () async => const KoboldKeeperPlan.keep(3),
      underSwapLock: <T>(work) => work(),
      log: (_) {},
    );
    api.hold = Completer<void>();
    final saving = keeper.chatEnd('A', ok: true);
    await api.saveStarted.future;

    keeper.forget('A'); // deleted while its reply is being saved
    api.hold!.complete();
    await saving;

    expect(keeper.kept, 0, reason: 'the save brought the deleted chat back');
    api.hold = null;
    api.live = 300;
    await keeper.chatEnd('B', ok: true);
    expect(api.saved, [0, 0], reason: 'the next chat took the same slot');
    expect(keeper.kept, 1);
  });

  test('a reply that ends after its chat was deleted is not saved, so no live '
      'chat is pushed out for it', () async {
    final api = _Api();
    final keeper = KoboldSlotKeeper(
      api: api,
      loadGeneration: () => 1,
      plan: () async => const KoboldKeeperPlan.keep(2),
      underSwapLock: <T>(work) => work(),
      log: (_) {},
    );
    for (final (chat, tokens) in [('A', 500), ('B', 300)]) {
      await keeper.chatStart(chat);
      api.live = tokens;
      await keeper.chatEnd(chat, ok: true);
    }
    expect(api.saved, [0, 1]);

    await keeper.chatStart('C');
    api.live = 700;
    keeper.forget('C'); // deleted while its reply was being written
    await keeper.chatEnd('C', ok: true);

    expect(api.saved, [0, 1], reason: 'the deleted chat was saved');
    expect(keeper.kept, 2, reason: 'a live chat was pushed out for it');
  });
}
