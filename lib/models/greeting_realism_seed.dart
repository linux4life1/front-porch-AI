// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part 'greeting_realism_seed.opening.dart';

/// Sparse per-alternate-greeting overlay for the Realism Engine + Needs
/// opening. Parallel to `alternate_greetings` (index 0 = first alt =
/// `allGreetings[1]`). `first_mes` keeps using the card-level
/// `realism_engine` fields.
///
/// A **missing / null** slot means "no authored seed" — alternate greets
/// still get reading-the-room. An **empty object** `{}` means "inherit the
/// card (or group) defaults and do not read the room." Present keys override
/// that base at chat-open / greeting-commit time.
class GreetingRealismSeed {
  final String? characterEmotion;
  final String? emotionIntensity;
  final int? shortTermBond;
  final int? longTermBond;
  final int? trustLevel;
  final int? dayCount;
  final String? timeOfDay;
  final String? storyStartDate;
  final String? storyStartTime;
  final String? currentTask;
  final int? needsBaselineHunger;
  final int? needsBaselineBladder;
  final int? needsBaselineBowels;
  final int? needsBaselineEnergy;
  final int? needsBaselineSocial;
  final int? needsBaselineFun;
  final int? needsBaselineHygiene;
  final int? needsBaselineComfort;
  final Map<String, dynamic>? inventory;

  const GreetingRealismSeed({
    this.characterEmotion,
    this.emotionIntensity,
    this.shortTermBond,
    this.longTermBond,
    this.trustLevel,
    this.dayCount,
    this.timeOfDay,
    this.storyStartDate,
    this.storyStartTime,
    this.currentTask,
    this.needsBaselineHunger,
    this.needsBaselineBladder,
    this.needsBaselineBowels,
    this.needsBaselineEnergy,
    this.needsBaselineSocial,
    this.needsBaselineFun,
    this.needsBaselineHygiene,
    this.needsBaselineComfort,
    this.inventory,
  });

  /// True when no field is set. An empty overlay is still an *authored*
  /// inherit (`{}` in JSON); [isEmpty] only means "no numeric/text overrides."
  bool get isEmpty =>
      characterEmotion == null &&
      emotionIntensity == null &&
      shortTermBond == null &&
      longTermBond == null &&
      trustLevel == null &&
      dayCount == null &&
      timeOfDay == null &&
      storyStartDate == null &&
      storyStartTime == null &&
      currentTask == null &&
      needsBaselineHunger == null &&
      needsBaselineBladder == null &&
      needsBaselineBowels == null &&
      needsBaselineEnergy == null &&
      needsBaselineSocial == null &&
      needsBaselineFun == null &&
      needsBaselineHygiene == null &&
      needsBaselineComfort == null &&
      inventory == null;

  static const _keep = Object();

  GreetingRealismSeed copyWith({
    Object? characterEmotion = _keep,
    Object? emotionIntensity = _keep,
    Object? shortTermBond = _keep,
    Object? longTermBond = _keep,
    Object? trustLevel = _keep,
    Object? dayCount = _keep,
    Object? timeOfDay = _keep,
    Object? storyStartDate = _keep,
    Object? storyStartTime = _keep,
    Object? currentTask = _keep,
    Object? needsBaselineHunger = _keep,
    Object? needsBaselineBladder = _keep,
    Object? needsBaselineBowels = _keep,
    Object? needsBaselineEnergy = _keep,
    Object? needsBaselineSocial = _keep,
    Object? needsBaselineFun = _keep,
    Object? needsBaselineHygiene = _keep,
    Object? needsBaselineComfort = _keep,
    Object? inventory = _keep,
  }) {
    T? take<T>(Object? incoming, T? current) =>
        identical(incoming, _keep) ? current : incoming as T?;
    return GreetingRealismSeed(
      characterEmotion: take(characterEmotion, this.characterEmotion),
      emotionIntensity: take(emotionIntensity, this.emotionIntensity),
      shortTermBond: take(shortTermBond, this.shortTermBond),
      longTermBond: take(longTermBond, this.longTermBond),
      trustLevel: take(trustLevel, this.trustLevel),
      dayCount: take(dayCount, this.dayCount),
      timeOfDay: take(timeOfDay, this.timeOfDay),
      storyStartDate: take(storyStartDate, this.storyStartDate),
      storyStartTime: take(storyStartTime, this.storyStartTime),
      currentTask: take(currentTask, this.currentTask),
      needsBaselineHunger: take(needsBaselineHunger, this.needsBaselineHunger),
      needsBaselineBladder: take(
        needsBaselineBladder,
        this.needsBaselineBladder,
      ),
      needsBaselineBowels: take(needsBaselineBowels, this.needsBaselineBowels),
      needsBaselineEnergy: take(needsBaselineEnergy, this.needsBaselineEnergy),
      needsBaselineSocial: take(needsBaselineSocial, this.needsBaselineSocial),
      needsBaselineFun: take(needsBaselineFun, this.needsBaselineFun),
      needsBaselineHygiene: take(
        needsBaselineHygiene,
        this.needsBaselineHygiene,
      ),
      needsBaselineComfort: take(
        needsBaselineComfort,
        this.needsBaselineComfort,
      ),
      inventory: take(inventory, this.inventory),
    );
  }

  /// Card JSON (snake_case, nested under `realism_engine.greeting_seeds`).
  Map<String, dynamic> toJson() {
    return {
      if (characterEmotion != null) 'character_emotion': characterEmotion,
      if (emotionIntensity != null) 'emotion_intensity': emotionIntensity,
      if (shortTermBond != null) 'short_term_bond': shortTermBond,
      if (longTermBond != null) 'long_term_bond': longTermBond,
      if (trustLevel != null) 'trust_level': trustLevel,
      if (dayCount != null) 'day_count': dayCount,
      if (timeOfDay != null) 'time_of_day': timeOfDay,
      if (storyStartDate != null) 'story_start_date': storyStartDate,
      if (storyStartTime != null) 'story_start_time': storyStartTime,
      if (currentTask != null) 'current_task': currentTask,
      if (needsBaselineHunger != null)
        'needs_baseline_hunger': needsBaselineHunger,
      if (needsBaselineBladder != null)
        'needs_baseline_bladder': needsBaselineBladder,
      if (needsBaselineBowels != null)
        'needs_baseline_bowels': needsBaselineBowels,
      if (needsBaselineEnergy != null)
        'needs_baseline_energy': needsBaselineEnergy,
      if (needsBaselineSocial != null)
        'needs_baseline_social': needsBaselineSocial,
      if (needsBaselineFun != null) 'needs_baseline_fun': needsBaselineFun,
      if (needsBaselineHygiene != null)
        'needs_baseline_hygiene': needsBaselineHygiene,
      if (needsBaselineComfort != null)
        'needs_baseline_comfort': needsBaselineComfort,
      if (inventory != null) 'inventory': inventory,
    };
  }

  /// Web-bridge JSON (camelCase, matches the React form).
  Map<String, dynamic> toFields() {
    return {
      if (characterEmotion != null) 'characterEmotion': characterEmotion,
      if (emotionIntensity != null) 'emotionIntensity': emotionIntensity,
      if (shortTermBond != null) 'shortTermBond': shortTermBond,
      if (longTermBond != null) 'longTermBond': longTermBond,
      if (trustLevel != null) 'trustLevel': trustLevel,
      if (dayCount != null) 'dayCount': dayCount,
      if (timeOfDay != null) 'timeOfDay': timeOfDay,
      if (storyStartDate != null) 'storyStartDate': storyStartDate,
      if (storyStartTime != null) 'storyStartTime': storyStartTime,
      if (currentTask != null) 'currentTask': currentTask,
      if (needsBaselineHunger != null)
        'needsBaselineHunger': needsBaselineHunger,
      if (needsBaselineBladder != null)
        'needsBaselineBladder': needsBaselineBladder,
      if (needsBaselineBowels != null)
        'needsBaselineBowels': needsBaselineBowels,
      if (needsBaselineEnergy != null)
        'needsBaselineEnergy': needsBaselineEnergy,
      if (needsBaselineSocial != null)
        'needsBaselineSocial': needsBaselineSocial,
      if (needsBaselineFun != null) 'needsBaselineFun': needsBaselineFun,
      if (needsBaselineHygiene != null)
        'needsBaselineHygiene': needsBaselineHygiene,
      if (needsBaselineComfort != null)
        'needsBaselineComfort': needsBaselineComfort,
      if (inventory != null) 'inventory': inventory,
    };
  }

  /// Accepts card snake_case, web camelCase, or a mix. Wrong types are
  /// skipped rather than throwing — same contract as [FrontPorchExtensions].
  factory GreetingRealismSeed.fromJson(Map<String, dynamic> json) {
    return GreetingRealismSeed(
      characterEmotion: _str(json, 'character_emotion', 'characterEmotion'),
      emotionIntensity: _str(json, 'emotion_intensity', 'emotionIntensity'),
      shortTermBond: _int(json, 'short_term_bond', 'shortTermBond'),
      longTermBond: _int(json, 'long_term_bond', 'longTermBond'),
      trustLevel: _int(json, 'trust_level', 'trustLevel'),
      dayCount: _int(json, 'day_count', 'dayCount'),
      timeOfDay: _str(json, 'time_of_day', 'timeOfDay'),
      storyStartDate: _str(json, 'story_start_date', 'storyStartDate'),
      storyStartTime: _str(json, 'story_start_time', 'storyStartTime'),
      currentTask: _str(json, 'current_task', 'currentTask'),
      needsBaselineHunger: _int(
        json,
        'needs_baseline_hunger',
        'needsBaselineHunger',
      ),
      needsBaselineBladder: _int(
        json,
        'needs_baseline_bladder',
        'needsBaselineBladder',
      ),
      needsBaselineBowels: _int(
        json,
        'needs_baseline_bowels',
        'needsBaselineBowels',
      ),
      needsBaselineEnergy: _int(
        json,
        'needs_baseline_energy',
        'needsBaselineEnergy',
      ),
      needsBaselineSocial: _int(
        json,
        'needs_baseline_social',
        'needsBaselineSocial',
      ),
      needsBaselineFun: _int(json, 'needs_baseline_fun', 'needsBaselineFun'),
      needsBaselineHygiene: _int(
        json,
        'needs_baseline_hygiene',
        'needsBaselineHygiene',
      ),
      needsBaselineComfort: _int(
        json,
        'needs_baseline_comfort',
        'needsBaselineComfort',
      ),
      inventory: _map(json, 'inventory'),
    );
  }
}
