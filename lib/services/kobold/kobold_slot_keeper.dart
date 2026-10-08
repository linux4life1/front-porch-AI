// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The slot keeper. KoboldCpp holds one chat's cache at a time, and every
// short helper prompt (a judge, a journal pass) throws it away, so the next
// reply reads the whole chat again. The keeper saves a chat's cache in one
// of KoboldCpp's memory slots when a reply ends and loads it back before the
// chat's next reply, so a helper in between costs nothing.
//
// It keeps the chat the user has open, always: every reply is saved and
// loaded back, and nothing weighs whether that is worth it. It keeps as many
// of the chats used before it as Settings asks for (none by default) as far
// as memory has room. A chat left behind beyond those is let go, and once
// none is kept the slots are emptied so their memory goes back to the
// system.
//
// It acts only inside the request queue, one request at a time, and steps
// aside at the first sign that its picture of the engine is wrong: leaving
// the cache alone is always safe and only costs speed.

import 'dart:async';

import 'kobold_keeper_budget.dart';
import 'kobold_slot_api.dart';

/// Runs [work] where nothing else changes the engine's model: a swap, an
/// unload and a load back wait for it.
typedef KoboldUnderSwapLock = Future<T> Function<T>(Future<T> Function() work);

enum _Mode { undecided, off, unprobed, on, aside }

class _Saved {
  _Saved(this.slot, this.tokens, this.used);
  final int slot;
  int tokens;
  int used;
}

class KoboldSlotKeeper {
  KoboldSlotKeeper({
    required KoboldSlotApi api,
    required int Function() loadGeneration,
    required Future<KoboldKeeperPlan> Function() plan,
    required KoboldUnderSwapLock underSwapLock,
    required void Function(String words) log,
    void Function(String why)? onFailure,
    int Function()? recent,
  }) : _api = api,
       _loadGeneration = loadGeneration,
       _plan = plan,
       _underSwapLock = underSwapLock,
       _log = log,
       _onFailure = onFailure,
       _recent = recent;

  final KoboldSlotApi _api;
  final int Function() _loadGeneration;
  final Future<KoboldKeeperPlan> Function() _plan;
  final KoboldUnderSwapLock _underSwapLock;
  final void Function(String) _log;

  /// How many chats besides the open one to keep ("Keep recent chats ready"
  /// in Settings), read at each use; null keeps as many as there is room
  /// for.
  final int Function()? _recent;

  /// Told when the engine could not do what the keeper asked, so a start
  /// can remember it. Not told when the keeper chooses to stay out.
  final void Function(String why)? _onFailure;

  /// The load the table belongs to. A new one means the engine's model
  /// process is new, and every slot died with the old one.
  int? _generation;
  _Mode _mode = _Mode.undecided;

  /// The room on this load: the plan's, never more than the engine's slots.
  /// The open chat is kept even with none.
  int _room = 0;
  final Map<String, _Saved> _saved = {};

  /// The chat the user has open ([open]), or the one a reply is for; never
  /// pushed out for another.
  String? _open;

  /// A [settle] is waiting in the line.
  bool _settling = false;

  /// Deleted chats: never saved again on this load. A save that was already
  /// running when one went must not bring it back into the table.
  final Set<String> _deleted = {};

  /// Slots written on this load: what emptying the slots gives back.
  final Set<int> _written = {};

  /// The chat whose cache the engine holds right now, or null when anything
  /// else may have changed it.
  String? _live;
  int _outside = 0;
  int _clock = 0;

  /// How many chats it keeps for the load it has looked at; 0 when it keeps
  /// none.
  int get chats => _mode == _Mode.on || _mode == _Mode.unprobed ? _count : 0;

  /// Chats it holds a saved cache for.
  int get kept => _saved.length;

  int get _recentWanted => _recent?.call() ?? _room;
  int get _count => koboldKeeperChats(recent: _recentWanted, room: _room);

  /// A chat reply is about to be sent. Loads the chat's saved cache unless
  /// the engine holds it already or it was never saved. A reply is only
  /// sent for the chat the user is in, so that chat is the open one.
  Future<void> chatStart(String key) {
    _open = key;
    return _chatStart(key);
  }

  Future<void> _chatStart(String key) => _guarded(() async {
    if (!await _ready()) return;
    if (_live == key) return;
    final saved = _saved[key];
    if (saved == null) return;
    final loaded = await _call(_generation!, () => _api.load(saved.slot));
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
    _live = key;
  });

  /// A request that is not a chat reply is about to be sent: it changes the
  /// engine's cache.
  void helperStart() => _live = null;

  /// The chat reply ended. [ok] is false when the engine's cache cannot be
  /// trusted (the request failed); a reply the reader stopped is fine. Saves
  /// the chat's cache, however long that takes: the open chat is always
  /// kept. The caller keeps the line until this completes.
  Future<void> chatEnd(String key, {required bool ok}) {
    _live = null;
    if (!ok) return Future<void>.value();
    return _guarded(() async {
      if (!await _ready()) return;
      // Deleted while its reply was written: no slot, so no live chat is
      // pushed out for it.
      if (_deleted.contains(key)) return;
      final generation = _generation!;
      final slot = _slotFor(key);
      if (slot == null) return;
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
      if (_deleted.contains(key)) return;
      (_saved[key] ??= _Saved(slot, saved.tokens, 0))
        ..tokens = saved.tokens
        ..used = ++_clock;
      _live = key;
      // The user may have left the chat while it saved.
      _trim();
    });
  }

  /// The chat the user has open changed: [key], or null when none is (back
  /// in the library). Nothing is let go here: [settle] does that in the
  /// line, after whatever is in it, so a save still running finishes first.
  /// True when a [settle] is to be put in the line.
  bool open(String? key) {
    _open = key;
    return _settleWanted();
  }

  bool _settleWanted() {
    if (_settling) return false;
    _settling = true;
    return true;
  }

  /// Lets go of the chats left behind beyond the recent ones Settings asks
  /// for, the oldest first, and once none is kept empties the slots, so
  /// their memory goes back to the system. KoboldCpp can only empty them
  /// all, so while any chat is kept the slots of those let go stay until a
  /// save writes over them.
  Future<void> settle() {
    _settling = false;
    return _guarded(() async {
      final generation = _generation;
      // A new load since: the slots died with the old one.
      if (generation == null || generation != _loadGeneration()) return;
      _trim();
      if (_saved.isNotEmpty || _written.isEmpty) return;
      if (!await _giveBackMemory(generation)) return;
      _written.clear();
      _log('No chat is kept ready now, so the memory it took was given back.');
    });
  }

  /// The chats other than the open one, beyond the recent ones Settings
  /// asks for and memory has room for, leave the table, the least recently
  /// used first. The open chat's slot is its own: no chat open, or one not
  /// saved yet, does not lend it to a recent chat.
  void _trim() {
    final others = [
      for (final e in _saved.entries)
        if (e.key != _open) e,
    ]..sort((a, b) => b.value.used.compareTo(a.value.used));
    for (final e in others.skip(_count - 1)) {
      _saved.remove(e.key);
    }
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

  /// The chat was deleted: it leaves the table at once and is never saved
  /// again on this load, and its slot is the first free one for the next
  /// chat. KoboldCpp cannot empty one slot, so what it holds there stays
  /// until that save writes over it, or until no chat is kept and [settle]
  /// empties them all. True when a [settle] is to be put in the line.
  bool forget(String key) {
    _saved.remove(key);
    _deleted.add(key);
    if (_live == key) _live = null;
    return _settleWanted();
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
      _written.clear();
      _live = null;
      if (plan.keeps) {
        _mode = _Mode.unprobed;
        _room = plan.chats;
      } else {
        _mode = _Mode.off;
        _room = 0;
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
    if (check.slotTokens.length < _room) _room = check.slotTokens.length;
    _mode = _Mode.on;
    final count = _count;
    _log(
      count == 1
          ? 'Keeping the open chat ready in memory, so a reply after a check '
                'does not read it all again.'
          : 'Keeping up to $count chats ready in memory, so coming back to '
                'one does not read it all again.',
    );
    return true;
  }

  /// The slot [key] is saved in, else a free one, else the least recently
  /// used chat's (that chat is dropped), never the open chat's. Null when
  /// [key] may not be kept: a chat that is not open is kept only as a
  /// recent one, when Settings asks for any.
  int? _slotFor(String key) {
    final count = _count;
    if (key != _open && count < 2) return null;
    final own = _saved[key];
    if (own != null) return own.slot;
    final taken = {for (final s in _saved.values) s.slot};
    for (var slot = 0; slot < count; slot++) {
      if (!taken.contains(slot)) return slot;
    }
    final others = _saved.entries.where((e) => e.key != _open);
    if (others.isEmpty) return null;
    final oldest = others.reduce(
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

  /// Empties every slot. True when the engine did.
  Future<bool> _giveBackMemory(int generation) async {
    try {
      return await _call(generation, _api.clear) ?? false;
    } on KoboldSlotException catch (e) {
      _log('The saved chats could not be cleared: ${e.message}');
      return false;
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
    _room = 0;
    _live = null;
    _saved.clear();
    _log('Chats are no longer kept ready: $why');
    if (failure) _onFailure?.call(why);
  }
}
