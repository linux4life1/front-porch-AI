// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The wait keeping a chat costs the user (maintainer ruling, 2026-10-05,
// "count only the wait felt"). A save runs right after the reply appears,
// while the user reads and types: done before the next turn starts, it cost
// nothing; still running then, what is left of it held the turn up, whichever
// request of the turn came first. The turn before's passes that wait behind
// the save are not the user's wait. The load before a reply always is.

/// The running save, and when a turn first started during it.
class _Running {
  _Running(this.chat);
  final String chat;

  /// The first into its slot on this load of the model, which also makes
  /// the slot's buffer: its wait says nothing.
  bool first = false;
  Duration? turn;
}

class KoboldFeltWait {
  KoboldFeltWait({Duration Function()? now}) : _now = now ?? _sinceStart;

  static final Stopwatch _clock = Stopwatch()..start();
  static Duration _sinceStart() => _clock.elapsed;

  final Duration Function() _now;
  _Running? _running;

  /// Each chat's last three saves' waits, newest last.
  final Map<String, List<Duration>> _waits = {};

  /// Each chat's last load back.
  final Map<String, Duration> _loads = {};

  /// A reply of [chat] ended: the line is held from now until its save is
  /// done, so a turn that starts meanwhile waits for it.
  void saveStarts(String chat) => _running = _Running(chat);

  /// The running save goes into a slot not written on this load.
  void firstIntoSlot() => _running?.first = true;

  /// The save is done. [made]: false when nothing was saved after all (the
  /// keeper stayed out), which costs nothing to remember. Only the first
  /// call for a save counts.
  void saveEnds({required bool made}) {
    final save = _running;
    _running = null;
    if (save == null || !made || save.first) return;
    final turn = save.turn;
    final waits = _waits.putIfAbsent(save.chat, () => [])
      ..add(turn == null ? Duration.zero : _now() - turn);
    if (waits.length > 3) waits.removeAt(0);
  }

  /// The user started a turn: a message, a regenerate, a Continue, the
  /// next speaker of a group. Only the first start during a save counts.
  void turnStarts() => _running?.turn ??= _now();

  /// Loading [chat] back before its reply took [took].
  void noteLoad(String chat, Duration took) => _loads[chat] = took;

  /// What keeping [chat] has lately cost the user in waiting: what its last
  /// three saves held a turn up, on average, and its last load back. Null
  /// while no save's wait is known.
  Duration? of(String chat) {
    final waits = _waits[chat];
    if (waits == null || waits.isEmpty) return null;
    final saves = waits.reduce((a, b) => a + b) ~/ waits.length;
    return saves + (_loads[chat] ?? Duration.zero);
  }

  /// [chat] was deleted.
  void forget(String chat) {
    _waits.remove(chat);
    _loads.remove(chat);
  }

  /// A new load of the model: nothing measured before says anything now.
  void clear() {
    _running = null;
    _waits.clear();
    _loads.clear();
  }
}
