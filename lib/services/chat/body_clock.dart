// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// How a body wears with the story clock. Pace scales drops only.
// One ordinary beat is half an hour. There is no per-need tick rate.

/// How fast awake time wears this body down.
enum BodyPace {
  sloth,
  normal,
  fast;

  static BodyPace parse(String? raw) {
    for (final pace in BodyPace.values) {
      if (pace.name == raw) return pace;
    }
    return BodyPace.normal;
  }
}

/// Keys from [all] that are not listed in [off].
List<String> needsThatAreOn(List<String> all, List<String> off) {
  if (off.isEmpty) return all;
  return [
    for (final key in all)
      if (!off.contains(key)) key,
  ];
}

/// The bars a person should see. Stored values for off needs stay put.
/// An empty [off] list leaves the vector as-is — it does not hide the strip.
Map<String, int> visibleNeeds(Map<String, int> vector, List<String> off) {
  if (off.isEmpty) return vector;
  return {
    for (final entry in vector.entries)
      if (!off.contains(entry.key)) entry.key: entry.value,
  };
}

/// Whether a loaded session should run Needs (sidebar bars + wear).
///
/// `sessions.needs_sim_enabled` defaults FALSE and is AND-ed with the card
/// and Porch Life only when a chat is first seeded. A lived-in 1:1 opened
/// after those two were turned ON still has the column at 0, so hydrate
/// used to clear the vector and the sidebar acted like Needs was off.
/// Promote that stale off. A saved vector wins too (hide ≠ erase). Groups
/// keep the stored flag — their on/off is derived from member seeds.
bool needsSimAfterHydrate({
  required bool sessionEnabled,
  required bool cardEnabled,
  required bool globalDefault,
  required bool hasSavedVector,
  required bool isGroup,
}) {
  if (sessionEnabled || hasSavedVector) return true;
  if (isGroup) return false;
  return cardEnabled && globalDefault;
}

/// How many awake minutes this beat should wear.
///
/// Continue is the same moment. A frozen clock is one ordinary beat.
/// Otherwise the clock's committed awake minutes are the whole story
/// (zero on a night, a skip, or time away).
int awakeMinutesForBeat({
  required bool continues,
  required bool clockRunning,
  required int committedAwakeMinutes,
}) {
  if (continues) return 0;
  if (!clockRunning) return kBodyBeatMinutes;
  if (committedAwakeMinutes < 0) return 0;
  return committedAwakeMinutes;
}

/// Minutes that count as one ordinary beat when the clock is off.
const int kBodyBeatMinutes = 30;

/// Points every need loses per ordinary beat, before pace.
const int kBodyWearPerBeat = 2;

/// Two thirds, one, or four thirds. Applied only to negative numbers.
int paceScaledDrop(int delta, BodyPace pace) {
  if (delta >= 0) return delta;
  return switch (pace) {
    BodyPace.sloth => (delta * 2) ~/ 3,
    BodyPace.normal => delta,
    BodyPace.fast => (delta * 4) ~/ 3,
  };
}

/// Awake-time wear at Normal, before pace. A few minutes round to nothing.
int awakeWearPoints(int minutes) {
  if (minutes <= 0) return 0;
  return (kBodyWearPerBeat * minutes) ~/ kBodyBeatMinutes;
}

/// Negative wear for every need, already scaled by [pace]. Empty when
/// the minutes are too short to move a bar.
Map<String, int> awakeWearDeltas(
  int minutes,
  BodyPace pace,
  List<String> keys,
) {
  final points = paceScaledDrop(-awakeWearPoints(minutes), pace);
  if (points == 0) return const {};
  return {for (final key in keys) key: points};
}

void scaleNegativeDrops(Map<String, int> deltas, BodyPace pace) {
  if (pace == BodyPace.normal) return;
  for (final key in deltas.keys.toList()) {
    deltas[key] = paceScaledDrop(deltas[key]!, pace);
  }
}

/// A scene drop cannot take a bar from above zero down to empty.
int clampSceneDrop({required int current, required int delta}) {
  if (delta >= 0 || current <= 0) return delta;
  final floor = current - 1;
  if (-delta > floor) return -floor;
  return delta;
}

/// Chip text for minutes the clock actually applied. Null when there is
/// nothing to show. A skip uses the time-skip chip instead, so pass
/// [isSkip] and this returns null.
String? timePassedLabel({
  required int minutes,
  required bool nextMorning,
  required bool isSkip,
}) {
  if (isSkip) return null;
  if (nextMorning) return 'Next morning';
  if (minutes < 1) return null;
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (rest == 0) return hours == 1 ? '1 hr' : '$hours hr';
  return '$hours hr $rest min';
}

/// Stamped on the reply before awake wear. Regen starts from this, not from
/// the bars the beat already wore down.
const String kNeedsPreWearByMember = 'needs_pre_wear_by_member';

/// Where every present body landed after that beat's wear. A swipe shows this.
const String kNeedsWornByMember = 'needs_worn_by_member';

/// Wear [minutes] off each present body. [before] is the bars at the start
/// of the beat. An empty wear (a few minutes, or Continue) leaves them.
Map<String, Map<String, int>> wearPresentBodies({
  required Map<String, Map<String, int>> before,
  required int minutes,
  required BodyPace Function(String id) paceOf,
  required List<String> Function(String id) needsOn,
}) {
  final out = <String, Map<String, int>>{};
  for (final entry in before.entries) {
    final wear = awakeWearDeltas(
      minutes,
      paceOf(entry.key),
      needsOn(entry.key),
    );
    final next = Map<String, int>.from(entry.value);
    for (final change in wear.entries) {
      final cur = next[change.key] ?? 80;
      next[change.key] = (cur + change.value).clamp(0, 100);
    }
    out[entry.key] = next;
  }
  return out;
}

/// The bars a regen must load before it wears the beat again.
///
/// [worn] is where the bodies are now, after the beat being replaced.
/// Starting the replay there wears them a second time (80 → 78 → 76).
Map<String, Map<String, int>> presentBodiesForReplay({
  required Map<String, Map<String, int>> before,
  required Map<String, Map<String, int>> worn,
}) {
  // [worn] is the wrong base. Keep the parameter so a replay that feeds
  // the live bars in is still forced to start from [before].
  if (worn.isEmpty && before.isEmpty) return const {};
  return {for (final id in before.keys) id: Map<String, int>.from(before[id]!)};
}

/// One beat, then a regen of that same beat. The second wear starts from
/// [before], so a Normal half hour leaves hunger at 78, not 76.
Map<String, Map<String, int>> replayPresentWear({
  required Map<String, Map<String, int>> before,
  required Map<String, Map<String, int>> worn,
  required int minutes,
  required BodyPace Function(String id) paceOf,
  required List<String> Function(String id) needsOn,
}) {
  return wearPresentBodies(
    before: presentBodiesForReplay(before: before, worn: worn),
    minutes: minutes,
    paceOf: paceOf,
    needsOn: needsOn,
  );
}

/// Undo one beat's wear for everyone except the deleted speaker.
///
/// [captured] is each body BEFORE delete time-travel. The previous speaker's
/// snapshot is already their post-turn bars (78). Ana's beat wore those to
/// 76. Refunding the restored 78 adds the drop back (80). Refund the capture.
Map<String, Map<String, int>> refundCoPresentWear({
  required Map<String, Map<String, int>> captured,
  required Map<String, Map<String, int>> preWear,
  required Map<String, Map<String, int>> worn,
  String? skipId,
}) {
  final out = <String, Map<String, int>>{};
  for (final id in preWear.keys) {
    if (id == skipId) continue;
    final pre = preWear[id];
    final post = worn[id];
    final base = captured[id];
    if (pre == null || post == null || base == null) continue;
    final next = Map<String, int>.from(base);
    var changed = false;
    for (final key in post.keys) {
      if (!next.containsKey(key)) continue;
      final delta = post[key]! - (pre[key] ?? post[key]!);
      if (delta == 0) continue;
      next[key] = (next[key]! - delta).clamp(0, 100);
      changed = true;
    }
    if (changed) out[id] = next;
  }
  return out;
}

/// Read a stamped present-body map. Metadata comes back untyped.
Map<String, Map<String, int>> presentBodiesFromMeta(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, Map<String, int>>{};
  for (final entry in raw.entries) {
    final body = entry.value;
    if (body is! Map) continue;
    out[entry.key.toString()] = {
      for (final need in body.entries)
        if (need.value is num) need.key.toString(): (need.value as num).toInt(),
    };
  }
  return out;
}
