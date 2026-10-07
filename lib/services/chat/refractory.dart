// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The refractory on the story clock (docs/design/needs-on-the-clock.md,
// "Refractory on the clock"). It counts story minutes: the judge's turns at
// 15 minutes each, worn down by every clock advance, or a quarter hour per
// reply while Passage of Time is off. Pure; NsfwService and ChatService
// apply it.

/// One judge turn of refractory, and one reply with the clock off.
const int kRefractoryMinutesPerTurn = 15;

/// Snapshot, member-map and receipt keys. The two turn keys are what chats
/// saved before minutes; they are read once, as turns × 15.
abstract final class RefractoryKeys {
  static const minutes = 'refractoryMinutesRemaining';
  static const total = 'refractoryMinutesTotal';
  static const opened = 'refractoryOpened';
  static const legacyTurns = 'cooldownTurnsRemaining';
  static const legacyTotal = 'cooldownTurnsTotal';
  static const all = [minutes, total, opened, legacyTurns, legacyTotal];
}

/// One body's refractory: story minutes left, the length it started at, and
/// whether its opening afterglow turn (the one reply that may show a limp,
/// spent body) has been spoken.
class Refractory {
  const Refractory({this.minutes = 0, this.total = 0, this.opened = false});

  static const none = Refractory();

  final int minutes;
  final int total;
  final bool opened;

  bool get running => minutes > 0;

  /// The first reply after the climax reply, and only that one.
  bool get isOpeningTurn => running && !opened;

  /// Set at climax from the judge's `refractory_turns`.
  factory Refractory.fromJudgeTurns(int turns) {
    final m = turns * kRefractoryMinutesPerTurn;
    return m > 0 ? Refractory(minutes: m, total: m) : none;
  }

  /// A count saved in replies before minutes existed. The opening turn was
  /// already spoken once a reply had ticked it (remaining below total).
  factory Refractory.fromLegacyTurns(int remaining, int total) {
    if (remaining <= 0) return none;
    final t = total > remaining ? total : remaining;
    return Refractory(
      minutes: remaining * kRefractoryMinutesPerTurn,
      total: t * kRefractoryMinutesPerTurn,
      opened: remaining < t,
    );
  }

  /// Reads [RefractoryKeys] from a snapshot, a member map or a session row.
  /// Minutes win; turns are read only where minutes were never written.
  /// Null when neither is there, so a restore keeps what it has.
  static Refractory? read(Map<dynamic, dynamic> src) {
    final m = src[RefractoryKeys.minutes];
    if (m is num) {
      final minutes = m.toInt();
      if (minutes <= 0) return none;
      final t = src[RefractoryKeys.total];
      final total = t is num ? t.toInt() : 0;
      return Refractory(
        minutes: minutes,
        total: total > minutes ? total : minutes,
        opened: src[RefractoryKeys.opened] == true,
      );
    }
    final turns = src[RefractoryKeys.legacyTurns];
    if (turns is! num) return null;
    final total = src[RefractoryKeys.legacyTotal];
    return Refractory.fromLegacyTurns(
      turns.toInt(),
      total is num ? total.toInt() : 0,
    );
  }

  Map<String, Object> toSnapshot() => {
    RefractoryKeys.minutes: minutes,
    RefractoryKeys.total: total,
    RefractoryKeys.opened: opened,
  };

  /// [elapsed] story minutes on a body whose arousal is [arousal]. When the
  /// refractory ends the total clears and a negative arousal halves toward
  /// neutral, so nobody leaves it reading as cold or repelled.
  ({Refractory refractory, int arousal}) elapse(
    int elapsed, {
    required int arousal,
  }) {
    if (!running || elapsed <= 0) return (refractory: this, arousal: arousal);
    final left = minutes - elapsed;
    if (left > 0) {
      return (
        refractory: Refractory(minutes: left, total: total, opened: opened),
        arousal: arousal,
      );
    }
    return (refractory: none, arousal: arousal < 0 ? arousal ~/ 2 : arousal);
  }

  /// The opening turn has been spoken.
  Refractory markOpened() => isOpeningTurn
      ? Refractory(minutes: minutes, total: total, opened: true)
      : this;

  @override
  bool operator ==(Object other) =>
      other is Refractory &&
      other.minutes == minutes &&
      other.total == total &&
      other.opened == opened;

  @override
  int get hashCode => Object.hash(minutes, total, opened);

  @override
  String toString() => 'Refractory($minutes/$total, opened: $opened)';
}

/// The countdown in the words the sidebar chip, the eval prompt and the phone
/// share. Clock on: story minutes, to the nearest 5. Clock off: replies, each
/// a quarter hour, rounded up.
({String chip, String prompt}) describeRefractory(
  int minutes, {
  required bool clockRunning,
}) {
  if (minutes <= 0) return (chip: '', prompt: '');
  final String left;
  if (clockRunning) {
    final rounded = ((minutes + 2) ~/ 5) * 5;
    left = 'about ${rounded < 5 ? 5 : rounded} min';
  } else {
    final replies =
        (minutes + kRefractoryMinutesPerTurn - 1) ~/ kRefractoryMinutesPerTurn;
    left = replies == 1 ? '1 reply' : '$replies replies';
  }
  return (chip: 'Refractory: $left', prompt: '($left left)');
}

/// Stamped on a reply: each body the beat moved, as the beat found it (regen
/// and a tail delete put it back) and as the beat left it (a swipe shows it).
const String kRefractoryPreBeat = 'refractory_pre_beat';
const String kRefractoryPostBeat = 'refractory_post_beat';

/// One body in a receipt. Arousal rides along because a refractory that ends
/// halves a negative arousal.
typedef RefractoryBody = ({Refractory refractory, int arousal});

/// Records [id] on the receipts in [meta]. The first record of a beat keeps
/// its "before"; the latest keeps its "after".
void noteRefractoryBeat(
  Map<String, dynamic> meta,
  String id, {
  required RefractoryBody before,
  required RefractoryBody after,
}) {
  final pre = Map<String, dynamic>.from(
    meta[kRefractoryPreBeat] as Map? ?? const {},
  );
  pre.putIfAbsent(id, () => _bodyJson(before));
  meta[kRefractoryPreBeat] = pre;
  final post = Map<String, dynamic>.from(
    meta[kRefractoryPostBeat] as Map? ?? const {},
  );
  post[id] = _bodyJson(after);
  meta[kRefractoryPostBeat] = post;
}

/// Reads one receipt off a message. Metadata comes back untyped.
Map<String, RefractoryBody> refractoryReceipt(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, RefractoryBody>{};
  for (final entry in raw.entries) {
    final body = entry.value;
    if (body is! Map) continue;
    final arousal = body['arousal'];
    out[entry.key.toString()] = (
      refractory: Refractory.read(body) ?? Refractory.none,
      arousal: arousal is num ? arousal.toInt() : 0,
    );
  }
  return out;
}

Map<String, Object> _bodyJson(RefractoryBody body) => {
  ...body.refractory.toSnapshot(),
  'arousal': body.arousal,
};
