// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

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

/// Filled opening state after merging a [GreetingRealismSeed] onto a base
/// (card-level `realism_engine`, or a group's per-member seed).
class GreetingOpeningSnapshot {
  final int shortTermBond;
  final int longTermBond;
  final int trustLevel;
  final int dayCount;
  final String timeOfDay;
  final String? storyStartDate;
  final String? storyStartTime;
  final String characterEmotion;
  final String emotionIntensity;
  final String currentTask;
  final int needsBaselineHunger;
  final int needsBaselineBladder;
  final int needsBaselineEnergy;
  final int needsBaselineSocial;
  final int needsBaselineFun;
  final int needsBaselineHygiene;
  final int needsBaselineComfort;
  final Map<String, dynamic> inventory;

  const GreetingOpeningSnapshot({
    required this.shortTermBond,
    required this.longTermBond,
    required this.trustLevel,
    required this.dayCount,
    required this.timeOfDay,
    this.storyStartDate,
    this.storyStartTime,
    required this.characterEmotion,
    required this.emotionIntensity,
    required this.currentTask,
    required this.needsBaselineHunger,
    required this.needsBaselineBladder,
    required this.needsBaselineEnergy,
    required this.needsBaselineSocial,
    required this.needsBaselineFun,
    required this.needsBaselineHygiene,
    required this.needsBaselineComfort,
    required this.inventory,
  });

  Map<String, int> get needsBaselines => {
    'hunger': needsBaselineHunger,
    'bladder': needsBaselineBladder,
    'energy': needsBaselineEnergy,
    'social': needsBaselineSocial,
    'fun': needsBaselineFun,
    'hygiene': needsBaselineHygiene,
    'comfort': needsBaselineComfort,
  };
}

/// Card / group defaults the overlay is merged onto.
class GreetingOpeningBase {
  final int shortTermBond;
  final int longTermBond;
  final int trustLevel;
  final int dayCount;
  final String timeOfDay;
  final String? storyStartDate;
  final String? storyStartTime;
  final String characterEmotion;
  final String emotionIntensity;
  final String currentTask;
  final int needsBaselineHunger;
  final int needsBaselineBladder;
  final int needsBaselineEnergy;
  final int needsBaselineSocial;
  final int needsBaselineFun;
  final int needsBaselineHygiene;
  final int needsBaselineComfort;
  final Map<String, dynamic> inventory;

  const GreetingOpeningBase({
    this.shortTermBond = 0,
    this.longTermBond = 0,
    this.trustLevel = 0,
    this.dayCount = 1,
    this.timeOfDay = 'morning',
    this.storyStartDate,
    this.storyStartTime,
    this.characterEmotion = '',
    this.emotionIntensity = 'mild',
    this.currentTask = '',
    this.needsBaselineHunger = 80,
    this.needsBaselineBladder = 80,
    this.needsBaselineEnergy = 80,
    this.needsBaselineSocial = 80,
    this.needsBaselineFun = 80,
    this.needsBaselineHygiene = 80,
    this.needsBaselineComfort = 80,
    this.inventory = const {},
  });
}

/// Metadata key stamped on the opening bubble so greeting index survives
/// reload without a session-column bump.
const kGreetingIndexMetadataKey = 'greeting_index';

/// Parse `realism_engine.greeting_seeds` (or the web `greetingSeeds` list).
/// Null entries stay null. Junk is skipped.
List<GreetingRealismSeed?> parseGreetingSeeds(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e == null)
        null
      else if (e is Map)
        GreetingRealismSeed.fromJson(Map<String, dynamic>.from(e))
      else
        null,
  ];
}

/// Keep JSON-null / non-string greet slots as empty placeholders so zip
/// stays index-aligned; [compactGreetingPairs] then drops empty+seed together.
/// Numbers coerce to string (V2 hostile cards); null stays `''`.
List<String> greetingSlotsFromRaw(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      e == null
          ? ''
          : e is String
          ? e
          : e.toString(),
  ];
}

/// Pad / trim so [seeds] is the same length as the alternate-greetings list.
List<GreetingRealismSeed?> alignGreetingSeeds(
  List<GreetingRealismSeed?> seeds,
  int altCount,
) {
  if (altCount <= 0) return const [];
  if (seeds.length == altCount) return List<GreetingRealismSeed?>.from(seeds);
  if (seeds.length > altCount) {
    return seeds.sublist(0, altCount);
  }
  return [
    ...seeds,
    ...List<GreetingRealismSeed?>.filled(altCount - seeds.length, null),
  ];
}

/// Drop trailing nulls so the card JSON stays sparse.
List<GreetingRealismSeed?> compactGreetingSeeds(
  List<GreetingRealismSeed?> seeds,
) {
  var end = seeds.length;
  while (end > 0 && seeds[end - 1] == null) {
    end--;
  }
  if (end == 0) return const [];
  return seeds.sublist(0, end);
}

/// Drop empty greet rows *and* the seed slot at the same index so compact
/// never prefix-aligns a furious seed onto the wrong alt (Add / blank / Add).
({List<String> greetings, List<GreetingRealismSeed?> seeds})
compactGreetingPairs(List<String> greetings, List<GreetingRealismSeed?> seeds) {
  final aligned = alignGreetingSeeds(seeds, greetings.length);
  final outG = <String>[];
  final outS = <GreetingRealismSeed?>[];
  for (var i = 0; i < greetings.length; i++) {
    if (greetings[i].trim().isEmpty) continue;
    outG.add(greetings[i]);
    outS.add(aligned[i]);
  }
  return (greetings: outG, seeds: compactGreetingSeeds(outS));
}

/// Compact rewritten alternate greetings.
///
/// When [authoredSeeds] is omitted/null, pair against empty so leftover
/// source seeds (enhance `copyWith` of the original, chargen base leftovers)
/// cannot land furious on Get out. When enhance/chargen actually authored
/// seeds alongside the new alts (including `[]`), pass those so they are
/// not wiped.
({List<String> greetings, List<GreetingRealismSeed?> seeds})
compactRewrittenGreetingAlts(
  List<String> alts, [
  List<GreetingRealismSeed?>? authoredSeeds,
]) =>
    compactGreetingPairs(greetingSlotsFromRaw(alts), authoredSeeds ?? const []);

/// True when first_mes is missing or whitespace-only. Same pairing as empty.
bool greetingFirstMesEmpty(String firstMes) => firstMes.trim().isEmpty;

/// Overlay for `allGreetings[index]`.
///
/// When [firstMesEmpty] is false (non-empty first_mes), index 0 is always
/// null — that opening uses the card-level fields — and alts are
/// `seeds[index - 1]`. When first_mes is empty, `allGreetings` drops it so
/// displayed 0 is alt[0] and must read `seeds[0]`.
GreetingRealismSeed? greetingOverlayAt(
  List<GreetingRealismSeed?> seeds,
  int greetingIndex, {
  bool firstMesEmpty = false,
}) {
  if (firstMesEmpty) {
    if (greetingIndex < 0 || greetingIndex >= seeds.length) return null;
    return seeds[greetingIndex];
  }
  if (greetingIndex <= 0) return null;
  final i = greetingIndex - 1;
  if (i < 0 || i >= seeds.length) return null;
  return seeds[i];
}

/// Authored seed? First greet with a present first_mes: any Front Porch
/// extensions object counts. When first_mes is empty, displayed 0 is an alt
/// and uses the seed slot. Alts: a non-null slot (including `{}`) counts;
/// missing means read-the-room.
bool greetingHasAuthoredSeed({
  required bool hasCardExtensions,
  required List<GreetingRealismSeed?> seeds,
  required int greetingIndex,
  bool firstMesEmpty = false,
}) {
  if (firstMesEmpty) {
    return greetingOverlayAt(seeds, greetingIndex, firstMesEmpty: true) != null;
  }
  if (greetingIndex <= 0) return hasCardExtensions;
  return greetingOverlayAt(seeds, greetingIndex) != null;
}

GreetingOpeningSnapshot resolveGreetingOpening(
  GreetingOpeningBase base,
  GreetingRealismSeed? overlay,
) {
  final o = overlay;
  return GreetingOpeningSnapshot(
    shortTermBond: o?.shortTermBond ?? base.shortTermBond,
    longTermBond: o?.longTermBond ?? base.longTermBond,
    trustLevel: o?.trustLevel ?? base.trustLevel,
    dayCount: (o?.dayCount ?? base.dayCount).clamp(1, 9999),
    timeOfDay: o?.timeOfDay ?? base.timeOfDay,
    storyStartDate: o?.storyStartDate ?? base.storyStartDate,
    storyStartTime: o?.storyStartTime ?? base.storyStartTime,
    characterEmotion: o?.characterEmotion ?? base.characterEmotion,
    emotionIntensity: o?.emotionIntensity ?? base.emotionIntensity,
    currentTask: o?.currentTask ?? base.currentTask,
    needsBaselineHunger: o?.needsBaselineHunger ?? base.needsBaselineHunger,
    needsBaselineBladder: o?.needsBaselineBladder ?? base.needsBaselineBladder,
    needsBaselineEnergy: o?.needsBaselineEnergy ?? base.needsBaselineEnergy,
    needsBaselineSocial: o?.needsBaselineSocial ?? base.needsBaselineSocial,
    needsBaselineFun: o?.needsBaselineFun ?? base.needsBaselineFun,
    needsBaselineHygiene: o?.needsBaselineHygiene ?? base.needsBaselineHygiene,
    needsBaselineComfort: o?.needsBaselineComfort ?? base.needsBaselineComfort,
    inventory: o?.inventory ?? base.inventory,
  );
}

/// Recover the greeting cursor from stamped metadata, else by matching the
/// opening bubble text against already-macro-resolved greetings.
int recoverGreetingIndex({
  required List<String> resolvedGreetings,
  required String currentText,
  Object? storedIndex,
}) {
  if (storedIndex is int &&
      storedIndex >= 0 &&
      storedIndex < resolvedGreetings.length) {
    return storedIndex;
  }
  if (storedIndex is num) {
    final i = storedIndex.toInt();
    if (i >= 0 && i < resolvedGreetings.length) return i;
  }
  final t = currentText;
  for (var i = 0; i < resolvedGreetings.length; i++) {
    if (resolvedGreetings[i] == t) return i;
  }
  return 0;
}

String? _str(Map<String, dynamic> json, String snake, String camel) {
  final v = json.containsKey(snake) ? json[snake] : json[camel];
  if (v is String) return v;
  return null;
}

int? _int(Map<String, dynamic> json, String snake, String camel) {
  final v = json.containsKey(snake) ? json[snake] : json[camel];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

Map<String, dynamic>? _map(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}
