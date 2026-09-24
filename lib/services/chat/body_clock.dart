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
Map<String, int> visibleNeeds(Map<String, int> vector, List<String> off) {
  if (off.isEmpty) return vector;
  return {
    for (final entry in vector.entries)
      if (!off.contains(entry.key)) entry.key: entry.value,
  };
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
