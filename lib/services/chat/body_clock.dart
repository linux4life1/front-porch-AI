// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pace scales scene drops only. There is no clock tax.

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

/// Whether a loaded session should run Needs (sidebar bars + scene eval).
///
/// `sessions.needs_sim_enabled` defaults FALSE and is AND-ed with the card
/// and Porch Life only when a chat is first seeded. A lived-in 1:1 that
/// never flipped the column (no saved vector) still promotes ON when those
/// two ask for Needs.
///
/// The chat-gear switch sticks both ways. An explicit ON stays ON. An
/// explicit OFF keeps its saved vector (hide ≠ erase) and must not look
/// like a never-seeded row — false + a vector stays OFF. Groups keep the
/// stored flag; their on/off is derived from member seeds.
bool needsSimAfterHydrate({
  required bool sessionEnabled,
  required bool cardEnabled,
  required bool globalDefault,
  required bool hasSavedVector,
  required bool isGroup,
}) {
  if (sessionEnabled) return true;
  if (hasSavedVector) return false;
  if (isGroup) return false;
  return cardEnabled && globalDefault;
}

/// Two thirds, one, or four thirds. Applied only to negative numbers.
int paceScaledDrop(int delta, BodyPace pace) {
  if (delta >= 0) return delta;
  return switch (pace) {
    BodyPace.sloth => (delta * 2) ~/ 3,
    BodyPace.normal => delta,
    BodyPace.fast => (delta * 4) ~/ 3,
  };
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

/// Chip text for minutes the clock actually applied. A skip uses the
/// time-skip chip instead, so pass [isSkip] and this returns null.
/// Zero minutes still names the beat ("same moment") so the chip paints.
String? timePassedLabel({
  required int minutes,
  required bool nextMorning,
  required bool isSkip,
}) {
  if (isSkip) return null;
  if (nextMorning) return 'Next morning';
  if (minutes < 1) return 'same moment';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (rest == 0) return hours == 1 ? '1 hr' : '$hours hr';
  return '$hours hr $rest min';
}

/// Inverse of [timePassedLabel] for regen/swipe clock rewind.
///
/// Numeric fields pass through. Chip text (`5 min`, `1 hr`, `2 hr 5 min`,
/// `same moment`) becomes minutes. `Next morning` is not an exact span.
int? minutesFromTimePassed(Object? raw) {
  if (raw is num) return raw.toInt();
  if (raw is! String) return null;
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (text == 'same moment') return 0;
  if (text == 'Next morning') return null;
  final hrMin = RegExp(r'^(\d+)\s*hr(?:\s+(\d+)\s*min)?$').firstMatch(text);
  if (hrMin != null) {
    final hours = int.parse(hrMin.group(1)!);
    final mins = int.parse(hrMin.group(2) ?? '0');
    return hours * 60 + mins;
  }
  final mins = RegExp(r'^(\d+)\s*min$').firstMatch(text);
  if (mins != null) return int.parse(mins.group(1)!);
  return null;
}

/// Minutes a rejected turn recorded: `time_passed` chip first, then a
/// numeric `minutes` / `minutes_elapsed` field.
int? minutesRecordedForClockRewind(Map<String, dynamic>? meta) {
  if (meta == null) return null;
  final fromChip = minutesFromTimePassed(meta['time_passed']);
  if (fromChip != null) return fromChip;
  final minutes = meta['minutes'];
  if (minutes is num) return minutes.toInt();
  final elapsed = meta['minutes_elapsed'];
  if (elapsed is num) return elapsed.toInt();
  return null;
}

/// Short no-action turn: Needs ran, bars did not move. Shown as its own chip.
const String kNeedsUnaffectedMeta = 'needs_unaffected';

/// Copy on the chip. Keep in lockstep with `web_ui` ChipsRow.
const String kNeedsUnaffectedLabel = 'No needs affected';

/// Stamped on the reply before awake wear. Regen starts from this, not from
/// the bars the beat already wore down.
const String kNeedsPreWearByMember = 'needs_pre_wear_by_member';

/// Where every present body landed after that beat's wear. A swipe shows this.
const String kNeedsWornByMember = 'needs_worn_by_member';

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
