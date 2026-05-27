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

import 'package:front_porch_ai/models/avatar_image.dart';
import 'package:front_porch_ai/models/lorebook.dart';

import 'package:flutter/material.dart';

/// Front Porch AI V2.5 extensions — stored inside V2 `extensions.front_porch`.
///
/// These values seed the Realism Engine's initial state when a new
/// conversation is started with a character. Existing sessions use their
/// own DB-persisted state and are not affected.
class FrontPorchExtensions {
  bool realismEnabled;
  int shortTermBond; // -300 to 300
  int longTermBond; // -300 to 300
  int trustLevel; // -100 to 100
  int dayCount; // starts at 1
  String timeOfDay; // dawn/morning/late_morning/afternoon/evening/night
  String characterEmotion; // e.g. "curious"
  String emotionIntensity; // mild/moderate/strong
  bool nsfwCooldownEnabled;
  bool passageOfTimeEnabled; // sub-toggle for automatic time advancement
  bool chaosModeEnabled;
  bool needsSimEnabled; // per-character default for the needs simulation toggle
  bool
  enjoysLowHygiene; // when true, low hygiene is desirable (inverted behavior for filthy/musky characters)

  // Avatar behavior
  bool
  avatarLocked; // when true, avatar won't grow past default sidebar width on resize

  // Chat appearance colors (null = use global default)
  Color? userBubbleColor;
  Color? userTextColor;
  Color? aiBubbleColor;
  Color? aiTextColor;
  Color? dialogueColor;
  Color? actionColor;

  // Chat font family (null = use system default)
  String? chatFontFamily;

  String currentTask; // initial quest/task for the character

  FrontPorchExtensions({
    this.realismEnabled = false,
    this.shortTermBond = 0,
    this.longTermBond = 0,
    this.trustLevel = 0,
    this.dayCount = 1,
    this.timeOfDay = 'morning',
    this.characterEmotion = '',
    this.emotionIntensity = 'mild',
    this.nsfwCooldownEnabled = false,
    this.passageOfTimeEnabled = true, // defaults to on when realism is enabled
    this.chaosModeEnabled = false,
    this.needsSimEnabled = false,
    this.enjoysLowHygiene = false,

    // Avatar behavior
    this.avatarLocked = false,

    // Chat appearance colors (null = use global default)
    this.userBubbleColor,
    this.userTextColor,
    this.aiBubbleColor,
    this.aiTextColor,
    this.dialogueColor,
    this.actionColor,

    // Chat font family (null = use system default)
    this.chatFontFamily,

    this.currentTask = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'version': '2.5',
      'realism_engine': {
        'enabled': realismEnabled,
        'short_term_bond': shortTermBond,
        'long_term_bond': longTermBond,
        'trust_level': trustLevel,
        'day_count': dayCount,
        'time_of_day': timeOfDay,
        'character_emotion': characterEmotion,
        'emotion_intensity': emotionIntensity,
        'nsfw_cooldown_enabled': nsfwCooldownEnabled,
        'passage_of_time_enabled': passageOfTimeEnabled,
        'chaos_mode_enabled': chaosModeEnabled,
        'needs_sim_enabled': needsSimEnabled,
        'enjoys_low_hygiene': enjoysLowHygiene,
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
      },
    };
  }

  factory FrontPorchExtensions.fromJson(Map<String, dynamic> json) {
    final realism = json['realism_engine'] as Map<String, dynamic>? ?? {};
    return FrontPorchExtensions(
      realismEnabled: realism['enabled'] as bool? ?? false,
      shortTermBond: realism['short_term_bond'] as int? ?? 0,
      longTermBond: realism['long_term_bond'] as int? ?? 0,
      trustLevel: realism['trust_level'] as int? ?? 0,
      dayCount: realism['day_count'] as int? ?? 1,
      timeOfDay: realism['time_of_day'] as String? ?? 'morning',
      characterEmotion: realism['character_emotion'] as String? ?? '',
      emotionIntensity: realism['emotion_intensity'] as String? ?? 'mild',
      nsfwCooldownEnabled: realism['nsfw_cooldown_enabled'] as bool? ?? false,
      passageOfTimeEnabled: realism['passage_of_time_enabled'] as bool? ?? true,
      chaosModeEnabled: realism['chaos_mode_enabled'] as bool? ?? false,
      needsSimEnabled: realism['needs_sim_enabled'] as bool? ?? false,
      enjoysLowHygiene: realism['enjoys_low_hygiene'] as bool? ?? false,
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
    );
  }

  /// Create a deep copy of this extensions object
  FrontPorchExtensions copyWith({
    bool? realismEnabled,
    int? shortTermBond,
    int? longTermBond,
    int? trustLevel,
    int? dayCount,
    String? timeOfDay,
    String? characterEmotion,
    String? emotionIntensity,
    bool? nsfwCooldownEnabled,
    bool? passageOfTimeEnabled,
    bool? chaosModeEnabled,
    bool? needsSimEnabled,
    bool? enjoysLowHygiene,
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
  }) {
    return FrontPorchExtensions(
      realismEnabled: realismEnabled ?? this.realismEnabled,
      shortTermBond: shortTermBond ?? this.shortTermBond,
      longTermBond: longTermBond ?? this.longTermBond,
      trustLevel: trustLevel ?? this.trustLevel,
      dayCount: dayCount ?? this.dayCount,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      characterEmotion: characterEmotion ?? this.characterEmotion,
      emotionIntensity: emotionIntensity ?? this.emotionIntensity,
      nsfwCooldownEnabled: nsfwCooldownEnabled ?? this.nsfwCooldownEnabled,
      passageOfTimeEnabled: passageOfTimeEnabled ?? this.passageOfTimeEnabled,
      chaosModeEnabled: chaosModeEnabled ?? this.chaosModeEnabled,
      needsSimEnabled: needsSimEnabled ?? this.needsSimEnabled,
      enjoysLowHygiene: enjoysLowHygiene ?? this.enjoysLowHygiene,
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
    );
  }
}

class CharacterCard {
  String name;
  String description;
  String personality;
  String scenario;
  String firstMessage;
  String mesExample;
  String systemPrompt;
  String postHistoryInstructions;
  List<String> alternateGreetings;
  List<String> tags;
  String? imagePath;
  String? folderId;
  Lorebook? lorebook;
  List<String> worldNames;

  /// Per-character TTS voice assignment.
  ///
  /// This must be a valid voice key for the *currently selected* TTS engine
  /// (e.g. 'af_heart' for Kokoro, 'en_US-lessac-medium' for Piper, etc.).
  /// The UI now prevents (and warns about) cross-engine assignments.
  String? ttsVoice;
  String? dbId; // UUID primary key (runtime only, not serialized)
  FrontPorchExtensions? frontPorchExtensions; // V2.5 Realism Engine defaults
  Map<String, dynamic>?
  rawExtensions; // Preserve unknown third-party extension keys
  List<AvatarImage>? avatarImages; // Multiple avatar images for the character
  int primeAvatarIndex = 1; // 1-based index of the prime (default) avatar

  CharacterCard({
    required this.name,
    this.description = '',
    this.personality = '',
    this.scenario = '',
    this.firstMessage = '',
    this.mesExample = '',
    this.systemPrompt = '',
    this.postHistoryInstructions = '',
    this.alternateGreetings = const [],
    this.tags = const [],
    this.imagePath,
    this.folderId,
    this.lorebook,
    this.worldNames = const [],
    this.ttsVoice,
    this.frontPorchExtensions,
    this.rawExtensions,
    this.avatarImages,
    int? primeAvatarIndex,
  }) : primeAvatarIndex = primeAvatarIndex ?? 1;

  /// All greetings: primary first message + alternates
  List<String> get allGreetings {
    final greetings = <String>[firstMessage];
    greetings.addAll(alternateGreetings);
    return greetings.where((g) => g.isNotEmpty).toList();
  }

  Map<String, dynamic> toJson() {
    // Build extensions map: merge raw (third-party) keys with our namespace
    Map<String, dynamic>? extensions;
    if (frontPorchExtensions != null ||
        (rawExtensions != null && rawExtensions!.isNotEmpty)) {
      extensions = <String, dynamic>{};
      // Preserve any third-party extension keys first
      if (rawExtensions != null) extensions.addAll(rawExtensions!);
      // Add/overwrite our namespace
      if (frontPorchExtensions != null) {
        extensions['front_porch'] = frontPorchExtensions!.toJson();
      }
    }

    return {
      'name': name,
      'description': description,
      'personality': personality,
      'scenario': scenario,
      'first_mes': firstMessage,
      'mes_example': mesExample,
      'system_prompt': systemPrompt,
      'post_history_instructions': postHistoryInstructions,
      'alternate_greetings': alternateGreetings,
      'tags': tags,
      'character_book': lorebook?.toCharacterBook(),
      'world_names': worldNames,
      if (ttsVoice != null) 'tts_voice': ttsVoice,
      'extensions': ?extensions,
    };
  }

  String replacePlaceholders(String text, {String userName = 'You'}) {
    return text
        .replaceAll(RegExp(r'\{\{char\}\}', caseSensitive: false), name)
        .replaceAll(RegExp(r'<char>', caseSensitive: false), name)
        .replaceAll(RegExp(r'\{\{user\}\}', caseSensitive: false), userName)
        .replaceAll(RegExp(r'<user>', caseSensitive: false), userName);
  }

  String get formattedDescription => replacePlaceholders(description);

  /// Whether this card has any Front Porch extensions configured.
  bool get hasFrontPorchExtensions => frontPorchExtensions != null;
}
