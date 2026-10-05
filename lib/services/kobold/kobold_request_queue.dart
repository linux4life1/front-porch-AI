// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The line to KoboldCpp. Its cache holds one conversation at a time, and any
// request can change it, so the requests that touch it go out one by one, in
// the order they were asked for.

import 'dart:async';

/// A place in the line. [turn] completes when everyone before it has let go.
class KoboldQueueTicket {
  KoboldQueueTicket._(this.turn, this._behind);

  final Future<void> turn;
  final Completer<void> _behind;
  bool _released = false;

  /// Lets the next request go. Safe to call twice. Safe before [turn] has
  /// come: whoever is behind still waits for this place to be reached, so a
  /// request that gave up waiting never lets the others pass.
  void release() {
    if (_released) return;
    _released = true;
    unawaited(turn.whenComplete(_behind.complete));
  }
}

class KoboldRequestQueue {
  Future<void> _last = Future<void>.value();

  /// Takes the next place. The caller owns it until [KoboldQueueTicket.release],
  /// so it belongs in a `finally`.
  KoboldQueueTicket enter() {
    final behind = Completer<void>();
    final ticket = KoboldQueueTicket._(_last, behind);
    _last = behind.future;
    return ticket;
  }

  /// Runs [body] when its turn comes, and gives the place back however it
  /// ends.
  Future<T> run<T>(Future<T> Function() body) async {
    final ticket = enter();
    try {
      await ticket.turn;
      return await body();
    } finally {
      ticket.release();
    }
  }

  /// Completes when everything in line now has finished. Later arrivals do
  /// not count.
  Future<void> waitForIdle() => _last;
}
