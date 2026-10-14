// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

/// Mood with bite (docs/design/mood-with-bite.md): the mood state, the rules
/// that apply a judge's answer to it, the easing schedule, and the tone
/// family a label belongs to. Pure Dart, no model call, no setting.
library;

import 'package:front_porch_ai/utils/emotion_labels.dart';

/// Stamp and wire keys. Label and intensity are the two keys every realism
/// stamp has carried since the engine began; cause and hold are the two this
/// design adds beside them.
const String kMoodStampLabel = 'characterEmotion';
const String kMoodStampIntensity = 'emotionIntensity';
const String kMoodStampCause = 'emotionCause';
const String kMoodStampHeld = 'emotionHeldTurns';

/// How the judge says the feeling moved this turn.
enum MoodChange {
  /// The same feeling, carrying on. The schedule eases it.
  held,

  /// The same feeling, freshly fed by this turn. The clock restarts.
  stoked,

  /// A different feeling now.
  moved,
}

/// The pull a feeling has on what the character does; chosen from the label.
enum MoodTone { sour, low, anxious, lifted, warm, charged }

/// A mood the character carries: what, how strongly, why, and for how long.
class MoodState {
  const MoodState({
    this.label = '',
    this.intensity = '',
    this.cause = '',
    this.held = 0,
  });

  final String label;
  final String intensity;
  final String cause;

  /// Judge passes in a row that have kept this feeling; 0 when it just
  /// changed or was just set.
  final int held;

  static const MoodState neutral = MoodState();

  bool get isNeutral => label.trim().isEmpty || label.trim() == 'neutral';

  int get intensityRank => moodIntensityRank(intensity);

  MoodState copyWith({
    String? label,
    String? intensity,
    String? cause,
    int? held,
  }) => MoodState(
    label: label ?? this.label,
    intensity: intensity ?? this.intensity,
    cause: cause ?? this.cause,
    held: held ?? this.held,
  );

  /// The four stamp keys, written beside bond and trust on every reply.
  Map<String, dynamic> toStamp() => {
    kMoodStampLabel: label,
    kMoodStampIntensity: intensity,
    kMoodStampCause: cause,
    kMoodStampHeld: held,
  };

  /// Reads a stamp the way every restore door reads label and intensity:
  /// a missing key keeps [fallback]'s value. A stamp written before cause and
  /// hold existed carries a label but neither new key; it reads as a fresh
  /// feeling with no cause, which is exactly what it was.
  static MoodState fromStamp(Map<dynamic, dynamic>? stamp, MoodState fallback) {
    if (stamp == null) return fallback;
    final rawLabel = stamp[kMoodStampLabel];
    final rawIntensity = stamp[kMoodStampIntensity];
    final hasLabel = rawLabel is String;
    final cause = stamp[kMoodStampCause];
    final held = stamp[kMoodStampHeld];
    return MoodState(
      label: hasLabel ? rawLabel : fallback.label,
      intensity: rawIntensity is String ? rawIntensity : fallback.intensity,
      cause: cause is String ? cause : (hasLabel ? '' : fallback.cause),
      held: held is num ? held.toInt() : (hasLabel ? 0 : fallback.held),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MoodState &&
      other.label == label &&
      other.intensity == intensity &&
      other.cause == cause &&
      other.held == held;

  @override
  int get hashCode => Object.hash(label, intensity, cause, held);

  @override
  String toString() => 'MoodState($label, $intensity, "$cause", held $held)';
}

/// What the emotional judge answered, before the rules below apply it.
class MoodJudgeResult {
  const MoodJudgeResult({
    required this.label,
    required this.intensity,
    this.cause,
    this.change,
  });

  final String label;
  final String intensity;

  /// Null when the judge gave none; the stored cause then stands.
  final String? cause;

  /// Null when the judge did not answer (an older model, a confused reply);
  /// the rules then compare families to decide held or moved.
  final MoodChange? change;
}

/// mild 1, moderate 2, strong 3; unknown or empty 0.
int moodIntensityRank(String intensity) =>
    switch (intensity.trim().toLowerCase()) {
      'strong' || 'high' || 'intense' => 3,
      'moderate' || 'medium' => 2,
      'mild' || 'low' || 'faint' => 1,
      _ => 0,
    };

String moodIntensityWord(int rank) => switch (rank) {
  >= 3 => 'strong',
  2 => 'moderate',
  1 => 'mild',
  _ => '',
};

/// Parses the judge's `emotion_change` forgivingly. Legacy YES/NO answers
/// to the earlier "same feeling?" question read as held / moved.
MoodChange? parseMoodChange(Object? raw) {
  if (raw == null) return null;
  if (raw is bool) return raw ? MoodChange.held : MoodChange.moved;
  final text = raw.toString().trim().toLowerCase();
  if (text.isEmpty) return null;
  if (text.startsWith('stok') || text.startsWith('fed')) {
    return MoodChange.stoked;
  }
  if (text.startsWith('held') ||
      text.startsWith('hold') ||
      text.startsWith('same') ||
      text == 'yes' ||
      text == 'y' ||
      text == 'true') {
    return MoodChange.held;
  }
  if (text.startsWith('mov') ||
      text.startsWith('chang') ||
      text.startsWith('new') ||
      text == 'no' ||
      text == 'n' ||
      text == 'false') {
    return MoodChange.moved;
  }
  return null;
}

/// The cause as the prompt and the sidebar carry it: one line, no quotes,
/// no trailing stop, at most twelve words. "none" and its kin are empty.
String cleanMoodCause(String? raw) {
  if (raw == null) return '';
  var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  text = text.replaceAll(RegExp(r'''^["'“”‘’]+|["'“”‘’]+$'''), '').trim();
  text = text.replaceAll(RegExp(r'[.。]+$'), '').trim();
  final lower = text.toLowerCase();
  if (lower.isEmpty ||
      lower == 'none' ||
      lower == 'n/a' ||
      lower == 'null' ||
      lower == 'nothing' ||
      lower == 'unknown') {
    return '';
  }
  final words = text.split(' ');
  if (words.length <= 12) return text;
  return words.take(12).join(' ');
}

/// The hold, in words, never a count: nothing for a fresh feeling, "still"
/// once it has survived a couple of passes, "for a while now" after five.
String moodHoldWord(int held) {
  if (held >= 5) return 'for a while now';
  if (held >= 2) return 'still';
  return '';
}

/// Canonical (expression-set) label for a nuanced word: "prickly" is anger,
/// "wistful" is sadness. Unknown words come back as themselves.
String canonicalMoodLabel(String label) {
  final l = label.trim().toLowerCase().replaceAll(' ', '_');
  if (l.isEmpty) return '';
  return EmotionLabels.nuancedToStandard[l] ?? l;
}

const Map<String, MoodTone> _toneByCanonical = {
  'anger': MoodTone.sour,
  'annoyance': MoodTone.sour,
  'disgust': MoodTone.sour,
  'disapproval': MoodTone.sour,
  'sadness': MoodTone.low,
  'grief': MoodTone.low,
  'disappointment': MoodTone.low,
  'remorse': MoodTone.low,
  'fear': MoodTone.anxious,
  'nervousness': MoodTone.anxious,
  'confusion': MoodTone.anxious,
  'embarrassment': MoodTone.anxious,
  'joy': MoodTone.lifted,
  'amusement': MoodTone.lifted,
  'excitement': MoodTone.lifted,
  'optimism': MoodTone.lifted,
  'pride': MoodTone.lifted,
  'relief': MoodTone.lifted,
  'gratitude': MoodTone.lifted,
  'admiration': MoodTone.lifted,
  'approval': MoodTone.lifted,
  'love': MoodTone.warm,
  'affection': MoodTone.warm,
  'caring': MoodTone.warm,
  'desire': MoodTone.charged,
  'anticipation': MoodTone.charged,
  'curiosity': MoodTone.charged,
  'surprise': MoodTone.charged,
  'realization': MoodTone.charged,
};

/// The tone family of a label, or null for neutral and for words the map
/// does not know (they get no effects line; the cause does the work).
MoodTone? moodToneOf(String label) =>
    _toneByCanonical[canonicalMoodLabel(label)];

/// The easing schedule. A feeling that holds eases one step the third pass
/// it is kept and one more the sixth; mild is the floor. Applied to the
/// intensity the feeling has NOW, so a judge that eased it faster is not
/// pulled back up.
int easedMoodRank(int currentRank, int held) {
  if (currentRank <= 0) return currentRank;
  if (held == 3 || held == 6) return currentRank - 1 < 1 ? 1 : currentRank - 1;
  return currentRank;
}

/// Applies one judge answer to the stored mood (docs/design/mood-with-bite.md
/// "The judge"). Pure: the caller stamps and saves.
MoodState applyMoodJudge({
  required MoodState stored,
  required MoodJudgeResult judged,
}) {
  final judgedLabel = judged.label.trim().toLowerCase();
  final judgedRank = moodIntensityRank(judged.intensity);
  final judgedCause = cleanMoodCause(judged.cause);

  var change = judged.change;
  if (stored.isNeutral) {
    change = MoodChange.moved;
  } else if (change == null) {
    final same =
        judgedLabel.isNotEmpty &&
        canonicalMoodLabel(judgedLabel) == canonicalMoodLabel(stored.label);
    change = same ? MoodChange.held : MoodChange.moved;
  } else if (change != MoodChange.moved &&
      judgedLabel.isNotEmpty &&
      judgedLabel != 'neutral' &&
      canonicalMoodLabel(judgedLabel) != canonicalMoodLabel(stored.label)) {
    // "Held" with a different family is a moved answer in disguise: the
    // judge changed its mind about the feeling, not about its course.
    change = MoodChange.moved;
  }

  switch (change) {
    case MoodChange.moved:
      if (judgedLabel.isEmpty) return stored;
      // A judged neutral keeps the word, as every stamp before this design
      // wrote it; a missing intensity keeps the one going in, as before.
      if (judgedLabel == 'neutral') return const MoodState(label: 'neutral');
      return MoodState(
        label: judgedLabel,
        intensity: moodIntensityWord(
          judgedRank > 0
              ? judgedRank
              : (stored.intensityRank > 0 ? stored.intensityRank : 2),
        ),
        cause: judgedCause,
        held: 0,
      );
    case MoodChange.stoked:
      return MoodState(
        label: stored.label,
        intensity: moodIntensityWord(
          judgedRank > 0 ? judgedRank : stored.intensityRank,
        ),
        cause: judgedCause.isNotEmpty ? judgedCause : stored.cause,
        held: 0,
      );
    case MoodChange.held:
      final held = stored.held + 1;
      final current = stored.intensityRank > 0 ? stored.intensityRank : 2;
      final eased = easedMoodRank(current, held);
      final rank = judgedRank > 0 && judgedRank < eased ? judgedRank : eased;
      return MoodState(
        label: stored.label,
        intensity: moodIntensityWord(rank),
        cause: stored.cause.isNotEmpty ? stored.cause : judgedCause,
        held: held,
      );
  }
}

/// A story day crossed eases one step; past mild the mood clears. Backward
/// or zero days change nothing: rewinds restore the mood from stamps.
MoodState easeMoodForDays(MoodState stored, int days) {
  if (days <= 0 || stored.isNeutral) return stored;
  var rank = stored.intensityRank > 0 ? stored.intensityRank : 2;
  for (var i = 0; i < days; i++) {
    if (rank <= 1) return MoodState.neutral;
    rank -= 1;
  }
  return stored.copyWith(intensity: moodIntensityWord(rank));
}
