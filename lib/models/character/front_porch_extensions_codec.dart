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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/character/front_porch_extensions.dart';
import 'package:front_porch_ai/models/character/recovery_profile.dart';
import 'package:front_porch_ai/models/greeting_realism_seed.dart';

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

/// Card JSON → [FrontPorchExtensions]. Behind [FrontPorchExtensions.fromJson].
FrontPorchExtensions decodeFrontPorchExtensions(
  Map<String, dynamic> json, {
  List<String> alternateGreetings = const [],
}) {
  // `is Map` + copy rather than `as Map<String, dynamic>?`: jsonDecode always
  // hands back Map<String, dynamic>, but a card map BUILT IN DART (a group
  // member seed, a test fixture, anything assembled from literals) can be
  // Map<dynamic, dynamic>, and the old cast threw on it — failing the entire
  // card import over a type argument nobody chose deliberately.
  final raw = json['realism_engine'];
  final realism = raw is Map
      ? Map<String, dynamic>.from(raw)
      : <String, dynamic>{};
  return FrontPorchExtensions(
    stableId: realism['stable_id'] as String?,
    realismEnabled: realism['enabled'] as bool? ?? false,
    shortTermBond: realism['short_term_bond'] as int? ?? 0,
    longTermBond: realism['long_term_bond'] as int? ?? 0,
    trustLevel: realism['trust_level'] as int? ?? 0,
    dayCount: realism['day_count'] as int? ?? 1,
    timeOfDay: realism['time_of_day'] as String? ?? 'morning',
    storyStartDate: realism['story_start_date'] as String?,
    storyStartTime: realism['story_start_time'] as String?,
    characterEmotion: realism['character_emotion'] as String? ?? '',
    emotionIntensity: realism['emotion_intensity'] as String? ?? 'mild',
    nsfwCooldownEnabled: realism['nsfw_cooldown_enabled'] as bool? ?? false,
    passageOfTimeEnabled: realism['passage_of_time_enabled'] as bool? ?? true,
    chaosModeEnabled: realism['chaos_mode_enabled'] as bool? ?? false,
    needsSimEnabled: realism['needs_sim_enabled'] as bool?,
    pocketsEnabled: realism['pockets_enabled'] as bool? ?? true,
    afterglowEnabled: realism['afterglow_enabled'] as bool? ?? true,
    enjoysLowHygiene: realism['enjoys_low_hygiene'] as bool? ?? false,
    ambitions: _phrases(realism['ambitions']),
    planLines: _phrases(realism['plan_lines']),
    occupation: realism['occupation'] as String? ?? '',
    hours: realism['hours'] as String? ?? '',
    occupationBrief: realism['occupationBrief'] as String? ?? '',
    workDays: _workDays(realism),
    birthday: realism['birthday'] as String? ?? '',
    likes: _phrases(realism['likes']),
    dislikes: _phrases(realism['dislikes']),
    intimateInto: _phrases(_intimate(realism)['into']),
    intimateNotInto: _phrases(_intimate(realism)['not_into']),
    sex: normalizeCharacterSex(realism['sex']),
    recovery: RecoveryProfile.fromJson(realism['recovery']),
    inventory: realism['inventory'] is Map
        ? Map<String, dynamic>.from(realism['inventory'] as Map)
        : const {},
    realismVerificationEnabled:
        realism['realism_verification_enabled'] as bool? ?? false,
    realismVerificationMaxReprocesses:
        realism['realism_verification_max_reprocesses'] as int? ?? 1,
    realismVerificationStrictness:
        realism['realism_verification_strictness'] as int? ?? 3,
    realismNeedsDirectorAuthority:
        realism['realism_needs_director_authority'] as bool? ?? false,
    needsPace: realism['needs_pace'] as String? ?? 'normal',
    needsOff: realism['needs_off'] is List
        ? [
            for (final item in realism['needs_off'] as List)
              if (item is String) item,
          ]
        : <String>[],
    needsBaselineHunger: realism['needs_baseline_hunger'] as int? ?? 80,
    needsBaselineBladder: realism['needs_baseline_bladder'] as int? ?? 80,
    needsBaselineEnergy: realism['needs_baseline_energy'] as int? ?? 80,
    needsBaselineSocial: realism['needs_baseline_social'] as int? ?? 80,
    needsBaselineFun: realism['needs_baseline_fun'] as int? ?? 80,
    needsBaselineHygiene: realism['needs_baseline_hygiene'] as int? ?? 80,
    needsBaselineComfort: realism['needs_baseline_comfort'] as int? ?? 80,
    avatarLocked: realism['avatar_locked'] as bool? ?? false,

    // Chat appearance colors (null = use global default)
    userBubbleColor: realism['user_bubble_color'] != null
        ? Color(realism['user_bubble_color'] as int)
        : null,
    userTextColor: realism['user_text_color'] != null
        ? Color(realism['user_text_color'] as int)
        : null,
    aiBubbleColor: realism['ai_bubble_color'] != null
        ? Color(realism['ai_bubble_color'] as int)
        : null,
    aiTextColor: realism['ai_text_color'] != null
        ? Color(realism['ai_text_color'] as int)
        : null,
    dialogueColor: realism['dialogue_color'] != null
        ? Color(realism['dialogue_color'] as int)
        : null,
    actionColor: realism['action_color'] != null
        ? Color(realism['action_color'] as int)
        : null,

    // Chat font family (null = use system default)
    chatFontFamily: realism['chat_font_family'] as String?,

    currentTask: realism['current_task'] as String? ?? '',
    greetingSeeds: () {
      final parsed = parseGreetingSeeds(realism['greeting_seeds']);
      if (alternateGreetings.isEmpty) return parsed;
      return compactGreetingPairs(alternateGreetings, parsed).seeds;
    }(),
    tier: realism['tier'] as String?,
    favoriteAvatarId: realism['favorite_avatar_id'] as String?,
  );
}

/// [FrontPorchExtensions] → card JSON. Behind [FrontPorchExtensions.toJson].
Map<String, dynamic> encodeFrontPorchExtensions(FrontPorchExtensions e) {
  return {
    'version': '2.5',
    'realism_engine': {
      'stable_id': e.stableId,
      'enabled': e.realismEnabled,
      'short_term_bond': e.shortTermBond,
      'long_term_bond': e.longTermBond,
      'trust_level': e.trustLevel,
      'day_count': e.dayCount,
      'time_of_day': e.timeOfDay,
      'story_start_date': ?e.storyStartDate,
      'story_start_time': ?e.storyStartTime,
      'character_emotion': e.characterEmotion,
      'emotion_intensity': e.emotionIntensity,
      'nsfw_cooldown_enabled': e.nsfwCooldownEnabled,
      'passage_of_time_enabled': e.passageOfTimeEnabled,
      'chaos_mode_enabled': e.chaosModeEnabled,
      // Omit when the card never chose, so the Porch Life switch decides.
      'needs_sim_enabled': ?e.needsSimChoice,
      // Omit when on (the default) so old cards stay byte-identical.
      if (!e.pocketsEnabled) 'pockets_enabled': false,
      if (!e.afterglowEnabled) 'afterglow_enabled': false,
      'enjoys_low_hygiene': e.enjoysLowHygiene,
      'ambitions': e.ambitions,
      'plan_lines': e.planLines,
      if (e.occupation.isNotEmpty) 'occupation': e.occupation,
      if (e.hours.isNotEmpty) 'hours': e.hours,
      if (e.occupationBrief.isNotEmpty) 'occupationBrief': e.occupationBrief,
      if (e.hours.isNotEmpty && e.workDays != null) 'workDays': e.workDays,
      if (e.birthday.isNotEmpty) 'birthday': e.birthday,
      'likes': e.likes,
      'dislikes': e.dislikes,
      // Nested so the 18+ pair can be stripped from a share as one object.
      'intimate_preferences': {
        'into': e.intimateInto,
        'not_into': e.intimateNotInto,
      },
      // Additive keys (Afterglow overhaul PR 2): omitted when the card says
      // nothing, so pre-feature cards stay byte-identical and old apps read
      // them exactly as before.
      if (e.sex.isNotEmpty) 'sex': e.sex,
      if (!e.recovery.isDefault) 'recovery': e.recovery.toJson(),
      if (e.inventory.isNotEmpty) 'inventory': e.inventory,
      'realism_verification_enabled': e.realismVerificationEnabled,
      'realism_verification_max_reprocesses':
          e.realismVerificationMaxReprocesses,
      'realism_verification_strictness': e.realismVerificationStrictness,
      'realism_needs_director_authority': e.realismNeedsDirectorAuthority,
      'needs_pace': e.needsPace,
      if (e.needsOff.isNotEmpty) 'needs_off': e.needsOff,
      // Per-need baseline values
      'needs_baseline_hunger': e.needsBaselineHunger,
      'needs_baseline_bladder': e.needsBaselineBladder,
      'needs_baseline_energy': e.needsBaselineEnergy,
      'needs_baseline_social': e.needsBaselineSocial,
      'needs_baseline_fun': e.needsBaselineFun,
      'needs_baseline_hygiene': e.needsBaselineHygiene,
      'needs_baseline_comfort': e.needsBaselineComfort,

      'avatar_locked': e.avatarLocked,

      // Chat appearance colors (null = use global default)
      'user_bubble_color': e.userBubbleColor?.toARGB32(),
      'user_text_color': e.userTextColor?.toARGB32(),
      'ai_bubble_color': e.aiBubbleColor?.toARGB32(),
      'ai_text_color': e.aiTextColor?.toARGB32(),
      'dialogue_color': e.dialogueColor?.toARGB32(),
      'action_color': e.actionColor?.toARGB32(),

      // Chat font family (null = use system default)
      'chat_font_family': e.chatFontFamily,

      'current_task': e.currentTask,
      if (compactGreetingSeeds(e.greetingSeeds).isNotEmpty)
        'greeting_seeds': [
          for (final s in compactGreetingSeeds(e.greetingSeeds)) s?.toJson(),
        ],
      'tier': ?e.tier,
      'favorite_avatar_id': ?e.favoriteAvatarId,
    },
  };
}
