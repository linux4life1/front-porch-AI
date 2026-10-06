// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The slot keeper. KoboldCpp holds one chat's cache at a time, and every
// short helper prompt (a judge, a journal pass) throws it away, so the next
// reply reads the whole chat again. The keeper saves a chat's cache in one
// of KoboldCpp's memory slots when a reply ends and loads it back before the
// chat's next reply, so a helper in between costs nothing.
//
// It acts only inside the request queue, one request at a time, and steps
// aside at the first sign that its picture of the engine is wrong: leaving
// the cache alone is always safe and only costs speed.

import 'dart:async';

import 'kobold_felt_wait.dart';
import 'kobold_keeper_budget.dart';
import 'kobold_slot_api.dart';

/// Runs [work] where nothing else changes the engine's model: a swap, an
/// unload and a load back wait for it.
typedef KoboldUnderSwapLock = Future<T> Function<T>(Future<T> Function() work);

/// How long the engine would take to read [tokens] of chat from scratch,
/// measured on the model loaded now; null before it is known.
typedef KoboldReadTime = Duration? Function(int tokens);

enum _Mode { undecided, off, unprobed, on, aside }

class _Saved {
  _Saved(this.slot, this.tokens, this.used);
  final int slot;
  int tokens;
  int used;
}

/// A chat that cost more to keep than to read again. A chat grows, and
/// reading it again with it, so a save is tried again after [wait] more of
/// its replies; [wait] doubles each time it still does not pay.
class _LetGo {
  int replies = 0;
  int wait = 2;
}

class KoboldSlotKeeper {
  KoboldSlotKeeper({
    required KoboldSlotApi api,
    required int Function() loadGeneration,
    required Future<KoboldKeeperPlan> Function() plan,
    required KoboldUnderSwapLock underSwapLock,
    required void Function(String words) log,
    void Function(String why)? onFailure,
    KoboldReadTime? readTime,
  }) : _api = api,
       _loadGeneration = loadGeneration,
       _plan = plan,
       _underSwapLock = underSwapLock,
       _log = log,
       _onFailure = onFailure,
       _readTime = readTime;

  final KoboldSlotApi _api;
  final int Function() _loadGeneration;
  final Future<KoboldKeeperPlan> Function() _plan;
  final KoboldUnderSwapLock _underSwapLock;
  final void Function(String) _log;
  final KoboldReadTime? _readTime;

  /// Told when the engine could not do what the keeper asked, so a start
  /// can remember it. Not told when the keeper chooses to stay out.
  final void Function(String why)? _onFailure;

  /// The load the table belongs to. A new one means the engine's model
  /// process is new, and every slot died with the old one.
  int? _generation;
  _Mode _mode = _Mode.undecided;
  int _chats = 0;
  final Map<String, _Saved> _saved = {};

  /// Deleted chats: never saved again on this load. A save that was already
  /// running when one went must not bring it back into the table.
  final Set<String> _deleted = {};

  /// Chats that cost more to keep than to read again (see [_LetGo]).
  final Map<String, _LetGo> _letGo = {};

  /// Slots written on this load. The first save into a slot also makes its
  /// buffer, so that save says nothing about what keeping the chat costs.
  final Set<int> _written = {};

  /// What each chat's saves have cost the user in waiting.
  final KoboldFeltWait _felt = KoboldFeltWait();

  /// The chat whose cache the engine holds right now, or null when anything
  /// else may have changed it.
  String? _live;
  int _outside = 0;
  int _clock = 0;

  /// How many chats it keeps for the load it has looked at; 0 when it keeps
  /// none.
  int get chats => _mode == _Mode.on || _mode == _Mode.unprobed ? _chats : 0;

  /// Chats it holds a saved cache for.
  int get kept => _saved.length;

  /// A chat reply is about to be sent. Loads the chat's saved cache unless
  /// the engine holds it already or it was never saved.
  Future<void> chatStart(String key) => _guarded(() async {
    if (!await _ready()) return;
    if (_live == key) return;
    final saved = _saved[key];
    if (saved == null) return;
    final generation = _generation!;
    final took = Stopwatch();
    final loaded = await _call(generation, () {
      took.start();
      return _api.load(saved.slot);
    });
    if (loaded == null) return;
    if (!loaded.ok) {
      // The slot is empty: whatever was there is gone. Only this chat.
      _saved.remove(key);
      return;
    }
    if ((loaded.tokens - saved.tokens).abs() > 2) {
      return _stepAside(
        'A saved chat did not come back as it was saved, so something else '
        'is using the saved chats.',
        failure: true,
      );
    }
    saved.used = ++_clock;
    _felt.noteLoad(key, took.elapsed);
    _live = key;
  });

  /// A request that is not a chat reply is about to be sent: it changes the
  /// engine's cache.
  void helperStart() => _live = null;

  /// The user started a turn ([KoboldFeltWait.turnStarts]): a save still
  /// running now holds it up, and that wait is what keeping the chat costs.
  void turnStarts() => _felt.turnStarts();

  /// The chat reply ended. [ok] is false when the engine's cache cannot be
  /// trusted (the request failed); a reply the reader stopped is fine. Saves
  /// the chat's cache; the caller keeps the line until this completes.
  Future<void> chatEnd(String key, {required bool ok}) {
    _live = null;
    if (!ok) return Future<void>.value();
    // From the reply's end the line is held for the save: a turn that
    // starts from now waits for it.
    _felt.saveStarts(key);
    return _guarded(() async {
      if (!await _ready()) return;
      // Deleted while its reply was written: no slot, so no live chat is
      // pushed out for it.
      if (_deleted.contains(key)) return;
      // Let go: tried again only once it has had time to grow.
      final letGo = _letGo[key];
      if (letGo != null && ++letGo.replies < letGo.wait) return;
      final generation = _generation!;
      final slot = _slotFor(key);
      if (slot == null) return;
      if (!_written.contains(slot)) _felt.firstIntoSlot();
      final KoboldSlotSave? saved;
      try {
        saved = await _call(generation, () => _api.save(slot));
      } on KoboldSlotException catch (e) {
        if (!e.timedOut) rethrow;
        // Never answered: what that slot holds is not known, and an engine
        // that cannot save in time is short of something, so every chat is
        // let go for this load. It did not refuse: not a failure either.
        return _stepAside('KoboldCpp did not finish saving a chat in time.');
      }
      _felt.saveEnds(made: saved?.ok == true);
      if (saved == null) return;
      if (!saved.ok) {
        // An empty cache has nothing to keep; anything else not saving is
        // the engine running out of memory.
        if (saved.tokens > 0) {
          await _giveBackMemory(generation);
          _stepAside(
            'KoboldCpp could not save a chat, probably for lack of memory.',
            failure: true,
          );
        }
        return;
      }
      _written.add(slot);
      if (_deleted.contains(key)) {
        _felt.forget(key);
        return;
      }
      // What keeping costs the user in waiting ([KoboldFeltWait.of]) against
      // what it spares: reading the chat again. Nothing known yet keeps it.
      final cost = _felt.of(key);
      final reread = cost == null ? null : _readTime?.call(saved.tokens);
      if (cost != null && reread != null && cost >= reread) {
        return _letGoOf(key, cost, reread);
      }
      _letGo.remove(key);
      (_saved[key] ??= _Saved(slot, saved.tokens, 0))
        ..tokens = saved.tokens
        ..used = ++_clock;
      _live = key;
    }).whenComplete(() => _felt.saveEnds(made: false));
  }

  /// Keeping [key] costs more than reading it again: it is not kept, so its
  /// replies are neither held up by a load nor followed by a save, and it is
  /// tried again as it grows ([_LetGo]). The other chats still are, but for
  /// the oldest one when every slot was in use: this save wrote over its
  /// cache. Said once in the engine log; not a failure to remember.
  void _letGoOf(String key, Duration cost, Duration reread) {
    _saved.remove(key);
    final again = _letGo[key];
    if (again != null) {
      again
        ..replies = 0
        ..wait *= 2;
      return;
    }
    _letGo[key] = _LetGo();
    String s(Duration d) =>
        (d.inMilliseconds / 1000).toStringAsFixed(d.inSeconds < 1 ? 2 : 1);
    _log(
      'A chat is not kept ready: waiting for its save and loading it back '
      'costs about ${s(cost)} s, more than the ${s(reread)} s KoboldCpp needs '
      'to read it again. It is tried again as it grows.',
    );
  }

  /// Something that is not the app asks the engine (a coding session): its
  /// requests change the cache unseen, so the keeper waits until it is done.
  void outsideStart() {
    _outside++;
    _live = null;
  }

  void outsideEnd() {
    if (_outside > 0) _outside--;
    _live = null;
  }

  /// The chat was deleted: its slot is the first free one for the next chat.
  /// KoboldCpp cannot empty one slot (clearing is all of them, which would
  /// lose the other chats), so what the engine holds there stays until that
  /// next save writes over it.
  void forget(String key) {
    _saved.remove(key);
    _letGo.remove(key);
    _felt.forget(key);
    _deleted.add(key);
    if (_live == key) _live = null;
  }

  /// The first thing every call does: a new load empties the table, and the
  /// engine is looked at once before anything is saved. True when saved
  /// chats can be used right now.
  Future<bool> _ready() async {
    final generation = _loadGeneration();
    if (_generation != generation) {
      final plan = await _plan();
      if (plan.undecided || generation != _loadGeneration()) return false;
      _generation = generation;
      _saved.clear();
      _deleted.clear();
      _letGo.clear();
      _written.clear();
      _felt.clear();
      _live = null;
      if (plan.keeps) {
        _mode = _Mode.unprobed;
        _chats = plan.chats;
      } else {
        _mode = _Mode.off;
        _chats = 0;
        final why = plan.why;
        if (why != null) _log(why);
      }
    }
    if (_outside > 0) return false;
    return switch (_mode) {
      _Mode.unprobed => await _probe(),
      _Mode.on => true,
      _ => false,
    };
  }

  /// Asks the engine once whether it can keep chats, and whether anything
  /// else already does.
  Future<bool> _probe() async {
    final check = await _call(_generation!, _api.check);
    if (check == null) return false;
    if (!check.ok || check.slotTokens.isEmpty) {
      // Not a failure to remember: the engine may still be starting, or an
      // admin call blipped, and the next load looks again.
      _stepAside(
        'KoboldCpp does not keep saved chats here (it needs admin mode and a '
        'model loaded).',
      );
      return false;
    }
    if (check.slotTokens.any((t) => t > 0)) {
      _stepAside(
        'KoboldCpp already holds saved chats that are not from this session, '
        'so they are left alone.',
      );
      return false;
    }
    if (check.slotTokens.length < _chats) _chats = check.slotTokens.length;
    _mode = _Mode.on;
    _log(
      'Keeping up to $_chats ${_chats == 1 ? 'chat' : 'chats'} ready in '
      'memory, so coming back to one does not read it all again.',
    );
    return true;
  }

  /// The slot [key] is saved in, else a free one, else the least recently
  /// used chat's (that chat is dropped). Null when nothing may be kept.
  int? _slotFor(String key) {
    final own = _saved[key];
    if (own != null) return own.slot;
    if (_chats <= 0) return null;
    final taken = {for (final s in _saved.values) s.slot};
    for (var slot = 0; slot < _chats; slot++) {
      if (!taken.contains(slot)) return slot;
    }
    final oldest = _saved.entries.reduce(
      (a, b) => a.value.used <= b.value.used ? a : b,
    );
    _saved.remove(oldest.key);
    return oldest.value.slot;
  }

  /// One call, inside the swap lock, skipped (null) when the engine's model
  /// changed since [generation].
  Future<T?> _call<T>(int generation, Future<T> Function() call) =>
      _underSwapLock<T?>(() async {
        if (_loadGeneration() != generation) return null;
        return call();
      });

  Future<void> _giveBackMemory(int generation) async {
    try {
      await _call(generation, _api.clear);
    } on KoboldSlotException catch (e) {
      _log('The saved chats could not be cleared: ${e.message}');
    }
  }

  /// A keeper that goes wrong must never take a reply down with it: any
  /// failure is a step aside, and a busy engine is only skipped. It is a
  /// failure to remember only once the engine has shown it can keep chats:
  /// before that, an error is as likely to be an engine that is not ready.
  Future<void> _guarded(Future<void> Function() body) async {
    try {
      await body();
    } on KoboldSlotException catch (e) {
      if (!e.busy) _stepAside(e.message, failure: _mode == _Mode.on);
    } on Object catch (e) {
      _stepAside(
        'Something unexpected happened ($e).',
        failure: _mode == _Mode.on,
      );
    }
  }

  void _stepAside(String why, {bool failure = false}) {
    _mode = _Mode.aside;
    _chats = 0;
    _live = null;
    _saved.clear();
    _log('Chats are no longer kept ready: $why');
    if (failure) _onFailure?.call(why);
  }
}
