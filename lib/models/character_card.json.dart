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

part of 'character_card.dart';

/// Coerce an untrusted JSON value into a list of non-blank trimmed phrases.
///
/// Every authored phrase list on a card (ambitions, likes, dislikes, the
/// intimate pair) parses through here. `is List` rather than `as List?` on
/// purpose: a card can arrive from ANYWHERE — a PNG someone mailed you, a
/// Stoop download, a hand-edited JSON — so a field that is present but the
/// wrong type must yield an empty list rather than throw and fail the whole
/// import. The same cast bug was caught in review on the Stoop card panel
/// (2026-08-07); this is the one place it can now be got wrong.
List<String> _phrases(Object? raw) => [
  for (final v in raw is List ? raw : const [])
    if (v is String && v.trim().isNotEmpty) v.trim(),
];

/// The nested `intimate_preferences` object, or an empty map when absent or
/// malformed. Nested (rather than two flat keys) so the 18+ pair travels as
/// one strippable object.
Map<String, dynamic> _intimate(Map<String, dynamic> realism) {
  final v = realism['intimate_preferences'];
  return v is Map ? Map<String, dynamic>.from(v) : const {};
}

/// Card `workDays`: key missing → null (derive treats as Mon–Fri). Written
/// `[]` stays empty (never at work). Junk / all-invalid → null, not [].
List<int>? _workDays(Map<String, dynamic> realism) {
  if (!realism.containsKey('workDays')) return null;
  final raw = realism['workDays'];
  if (raw is! List) return null;
  if (raw.isEmpty) return const [];
  final days = <int>{};
  for (final e in raw) {
    final n = e is int
        ? e
        : e is num
        ? e.toInt()
        : e is String
        ? int.tryParse(e.trim())
        : null;
    if (n != null && n >= DateTime.monday && n <= DateTime.sunday) {
      days.add(n);
    }
  }
  if (days.isEmpty) return null;
  final list = days.toList()..sort();
  return list;
}

extension FrontPorchExtensionsJson on FrontPorchExtensions {
  Map<String, dynamic> toJson() {
    return {
      'version': '2.5',
      'realism_engine': {
        'stable_id': stableId,
        'enabled': realismEnabled,
        'short_term_bond': shortTermBond,
        'long_term_bond': longTermBond,
        'trust_level': trustLevel,
        'day_count': dayCount,
        'time_of_day': timeOfDay,
        'story_start_date': ?storyStartDate,
        'story_start_time': ?storyStartTime,
        'character_emotion': characterEmotion,
        'emotion_intensity': emotionIntensity,
        'nsfw_cooldown_enabled': nsfwCooldownEnabled,
        'passage_of_time_enabled': passageOfTimeEnabled,
        'chaos_mode_enabled': chaosModeEnabled,
        'needs_sim_enabled': needsSimEnabled,
        'enjoys_low_hygiene': enjoysLowHygiene,
        'ambitions': ambitions,
        'plan_lines': planLines,
        if (occupation.isNotEmpty) 'occupation': occupation,
        if (hours.isNotEmpty) 'hours': hours,
        if (occupationBrief.isNotEmpty) 'occupationBrief': occupationBrief,
        if (hours.isNotEmpty && workDays != null) 'workDays': workDays,
        if (birthday.isNotEmpty) 'birthday': birthday,
        'likes': likes,
        'dislikes': dislikes,
        // Nested so the 18+ pair can be stripped from a share as one object.
        'intimate_preferences': {
          'into': intimateInto,
          'not_into': intimateNotInto,
        },
        if (inventory.isNotEmpty) 'inventory': inventory,
        'realism_verification_enabled': realismVerificationEnabled,
        'realism_verification_max_reprocesses':
            realismVerificationMaxReprocesses,
        'realism_verification_strictness': realismVerificationStrictness,
        'realism_needs_director_authority': realismNeedsDirectorAuthority,
        'needs_sim_strength': needsSimStrength,
        // Per-need baseline values
        'needs_baseline_hunger': needsBaselineHunger,
        'needs_baseline_bladder': needsBaselineBladder,
        'needs_baseline_energy': needsBaselineEnergy,
        'needs_baseline_social': needsBaselineSocial,
        'needs_baseline_fun': needsBaselineFun,
        'needs_baseline_hygiene': needsBaselineHygiene,
        'needs_baseline_comfort': needsBaselineComfort,

        'needs_decay_hunger': needsDecayHunger,
        'needs_decay_bladder': needsDecayBladder,
        'needs_decay_energy': needsDecayEnergy,
        'needs_decay_social': needsDecaySocial,
        'needs_decay_fun': needsDecayFun,
        'needs_decay_hygiene': needsDecayHygiene,
        'needs_decay_comfort': needsDecayComfort,

        'avatar_locked': avatarLocked,

        // Chat appearance colors (null = use global default)
        'user_bubble_color': userBubbleColor?.toARGB32(),
        'user_text_color': userTextColor?.toARGB32(),
        'ai_bubble_color': aiBubbleColor?.toARGB32(),
        'ai_text_color': aiTextColor?.toARGB32(),
        'dialogue_color': dialogueColor?.toARGB32(),
        'action_color': actionColor?.toARGB32(),

        // Chat font family (null = use system default)
        'chat_font_family': chatFontFamily,

        'current_task': currentTask,
        if (compactGreetingSeeds(greetingSeeds).isNotEmpty)
          'greeting_seeds': [
            for (final s in compactGreetingSeeds(greetingSeeds)) s?.toJson(),
          ],
        'tier': ?tier,
        'favorite_avatar_id': ?favoriteAvatarId,
      },
    };
  }

  /// Create a deep copy of this extensions object
  FrontPorchExtensions copyWith({
    bool? realismEnabled,
    int? shortTermBond,
    int? longTermBond,
    int? trustLevel,
    int? dayCount,
    String? timeOfDay,
    String? storyStartDate,
    String? storyStartTime,
    String? characterEmotion,
    String? emotionIntensity,
    bool? nsfwCooldownEnabled,
    bool? passageOfTimeEnabled,
    bool? chaosModeEnabled,
    bool? needsSimEnabled,
    bool? enjoysLowHygiene,
    List<String>? ambitions,
    List<String>? planLines,
    String? occupation,
    String? hours,
    String? occupationBrief,
    List<int>? workDays,
    String? birthday,
    List<String>? likes,
    List<String>? dislikes,
    List<String>? intimateInto,
    List<String>? intimateNotInto,
    Map<String, dynamic>? inventory,
    bool? realismVerificationEnabled,
    int? realismVerificationMaxReprocesses,
    int? realismVerificationStrictness,
    bool? realismNeedsDirectorAuthority,
    int? needsSimStrength,
    int? needsBaselineHunger,
    int? needsBaselineBladder,
    int? needsBaselineEnergy,
    int? needsBaselineSocial,
    int? needsBaselineFun,
    int? needsBaselineHygiene,
    int? needsBaselineComfort,
    int? needsDecayHunger,
    int? needsDecayBladder,
    int? needsDecayEnergy,
    int? needsDecaySocial,
    int? needsDecayFun,
    int? needsDecayHygiene,
    int? needsDecayComfort,
    bool? avatarLocked,

    // Chat appearance colors (null = use global default)
    Color? userBubbleColor,
    Color? userTextColor,
    Color? aiBubbleColor,
    Color? aiTextColor,
    Color? dialogueColor,
    Color? actionColor,

    // Chat font family (null = use system default)
    String? chatFontFamily,

    String? currentTask,
    List<GreetingRealismSeed?>? greetingSeeds,
    String? stableId,
    String? tier,
    String? favoriteAvatarId,
  }) {
    return FrontPorchExtensions(
      realismEnabled: realismEnabled ?? this.realismEnabled,
      shortTermBond: shortTermBond ?? this.shortTermBond,
      longTermBond: longTermBond ?? this.longTermBond,
      trustLevel: trustLevel ?? this.trustLevel,
      dayCount: dayCount ?? this.dayCount,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      storyStartDate: storyStartDate ?? this.storyStartDate,
      storyStartTime: storyStartTime ?? this.storyStartTime,
      characterEmotion: characterEmotion ?? this.characterEmotion,
      emotionIntensity: emotionIntensity ?? this.emotionIntensity,
      nsfwCooldownEnabled: nsfwCooldownEnabled ?? this.nsfwCooldownEnabled,
      passageOfTimeEnabled: passageOfTimeEnabled ?? this.passageOfTimeEnabled,
      chaosModeEnabled: chaosModeEnabled ?? this.chaosModeEnabled,
      needsSimEnabled: needsSimEnabled ?? this.needsSimEnabled,
      enjoysLowHygiene: enjoysLowHygiene ?? this.enjoysLowHygiene,
      ambitions: ambitions ?? this.ambitions,
      planLines: planLines ?? this.planLines,
      occupation: occupation ?? this.occupation,
      hours: hours ?? this.hours,
      occupationBrief: occupationBrief ?? this.occupationBrief,
      workDays: workDays ?? this.workDays,
      birthday: birthday ?? this.birthday,
      likes: likes ?? this.likes,
      dislikes: dislikes ?? this.dislikes,
      intimateInto: intimateInto ?? this.intimateInto,
      intimateNotInto: intimateNotInto ?? this.intimateNotInto,
      inventory: inventory ?? this.inventory,
      realismVerificationEnabled:
          realismVerificationEnabled ?? this.realismVerificationEnabled,
      realismVerificationMaxReprocesses:
          realismVerificationMaxReprocesses ??
          this.realismVerificationMaxReprocesses,
      realismVerificationStrictness:
          realismVerificationStrictness ?? this.realismVerificationStrictness,
      realismNeedsDirectorAuthority:
          realismNeedsDirectorAuthority ?? this.realismNeedsDirectorAuthority,
      needsSimStrength: needsSimStrength ?? this.needsSimStrength,
      needsBaselineHunger: needsBaselineHunger ?? this.needsBaselineHunger,
      needsBaselineBladder: needsBaselineBladder ?? this.needsBaselineBladder,
      needsBaselineEnergy: needsBaselineEnergy ?? this.needsBaselineEnergy,
      needsBaselineSocial: needsBaselineSocial ?? this.needsBaselineSocial,
      needsBaselineFun: needsBaselineFun ?? this.needsBaselineFun,
      needsBaselineHygiene: needsBaselineHygiene ?? this.needsBaselineHygiene,
      needsBaselineComfort: needsBaselineComfort ?? this.needsBaselineComfort,
      needsDecayHunger: needsDecayHunger ?? this.needsDecayHunger,
      needsDecayBladder: needsDecayBladder ?? this.needsDecayBladder,
      needsDecayEnergy: needsDecayEnergy ?? this.needsDecayEnergy,
      needsDecaySocial: needsDecaySocial ?? this.needsDecaySocial,
      needsDecayFun: needsDecayFun ?? this.needsDecayFun,
      needsDecayHygiene: needsDecayHygiene ?? this.needsDecayHygiene,
      needsDecayComfort: needsDecayComfort ?? this.needsDecayComfort,
      avatarLocked: avatarLocked ?? this.avatarLocked,

      // Chat appearance colors (null = use global default)
      userBubbleColor: userBubbleColor ?? this.userBubbleColor,
      userTextColor: userTextColor ?? this.userTextColor,
      aiBubbleColor: aiBubbleColor ?? this.aiBubbleColor,
      aiTextColor: aiTextColor ?? this.aiTextColor,
      dialogueColor: dialogueColor ?? this.dialogueColor,
      actionColor: actionColor ?? this.actionColor,

      // Chat font family (null = use system default)
      chatFontFamily: chatFontFamily ?? this.chatFontFamily,

      currentTask: currentTask ?? this.currentTask,
      greetingSeeds: greetingSeeds ?? this.greetingSeeds,
      stableId: stableId ?? this.stableId,
      tier: tier ?? this.tier,
      favoriteAvatarId: favoriteAvatarId ?? this.favoriteAvatarId,
    );
  }
}
