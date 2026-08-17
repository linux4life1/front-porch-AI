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
import 'package:front_porch_ai/models/lorebook_export.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// Front Porch AI V2.5 extensions — stored inside V2 `extensions.front_porch`.
///
/// These values seed the Realism Engine's initial state when a new
/// conversation is started with a character. Existing sessions use their
/// own DB-persisted state and are not affected.
///
/// stableId (inside realism_engine) provides a persistent identity across
/// PNG rewrites/reimports so that library dbId and chat history are never lost
/// on realism/needs edits (import path now updates in place for stable matches).

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

class FrontPorchExtensions {
  bool realismEnabled;
  int shortTermBond; // -300 to 300
  int longTermBond; // -300 to 300
  int trustLevel; // -100 to 100
  int dayCount; // starts at 1
  String timeOfDay; // dawn/morning/late_morning/afternoon/evening/night

  // Story Calendar (docs/design/story-calendar.md §3a). Additive next to the
  // kept day_count/time_of_day so cards round-trip through The Stoop and
  // stay readable by older apps.
  String?
  storyStartDate; // ISO date the story begins on; null = "the day the chat starts"
  String? storyStartTime; // "HH:MM" exact opening clock; null = period default
  String characterEmotion; // e.g. "curious"
  String emotionIntensity; // mild/moderate/strong
  bool nsfwCooldownEnabled;
  bool passageOfTimeEnabled; // sub-toggle for automatic time advancement
  bool chaosModeEnabled;
  bool needsSimEnabled; // per-character default for the needs simulation toggle
  bool
  enjoysLowHygiene; // when true, low hygiene is desirable (inverted behavior for filthy/musky characters)

  /// Long-term ambitions — the character's ends, distinct from short-lived
  /// objectives (the means) and fixations (emotional obsessions). Identity,
  /// not story state: they travel with the card; per-chat PROGRESS lives in
  /// journal cards (Living Time §6). Authored in the character editor.
  List<String> ambitions;

  /// Short plan-line sentences. Identity like [ambitions]: travel with the card.
  /// The today sentence is session state, never stored here.
  List<String> planLines;

  /// What this character is drawn to, and what puts them off — short phrases,
  /// authored on the card. Identity like [ambitions]: they travel with it.
  ///
  /// The precedent already in-tree is [enjoysLowHygiene]: ONE hardcoded
  /// preference that flips needs behaviour. These make that pattern
  /// author-editable data instead of a single boolean somebody had to write
  /// code for. Two consumers: the behavioural injection (so the character
  /// ACTS on them, which needs no engine) and the realism eval prompts (so
  /// bond/trust/emotion deltas become character-specific, which does).
  List<String> likes;
  List<String> dislikes;

  /// The 18+ half of the same idea. Kept as its own pair rather than mixed
  /// into [likes]/[dislikes] so it can be hidden, or stripped from a share,
  /// with one decision instead of phrase-by-phrase judgement. Surfaces in
  /// editors ONLY when NSFW is enabled. Transported nested under
  /// `intimate_preferences: {into: [], not_into: []}`.
  List<String> intimateInto;
  List<String> intimateNotInto;

  /// Starting Pockets & Wardrobe — what the character already has when a chat
  /// opens: `{worn: [...], carrying: [...]}`, entries either plain strings or
  /// `{name, state}`. Optional and additive, so older apps and The Stoop
  /// ignore it and a card without one simply starts empty.
  ///
  /// Kept as a raw map rather than a typed Pockets: this is the MODEL layer and
  /// it must not depend on a chat service leaf. The one place that reads it
  /// (chat_service_pockets.dart) parses it through Pockets.fromJson, which
  /// already tolerates both shapes.
  Map<String, dynamic> inventory;

  // Optional director/verifier thread for Realism Engine + Needs (ingests full latent context + deltas JSON;
  // rules + optional reprocess with corrections up to full per-eval clamp limits; per-char in Optional Features).
  bool realismVerificationEnabled;
  int realismVerificationMaxReprocesses; // 1-5
  int
  realismVerificationStrictness; // 1-5 (default 3 = Balanced; higher = stricter director)

  // Director authority on needs deltas (simple model+Director path): when true, verified/corrected deltas from Director review loop take authority for needs_impact (straight decay ticks + model deltas + optional director corrections; no legacy buffers/table/spaghetti). Off by default for conservative behavior.
  bool realismNeedsDirectorAuthority;

  // User-chosen exponent (1-5) for Needs Simulation delta magnitude. 1 = baseline (current behavior).
  // Higher values make swings larger (e.g. model/Director emits -3 hygiene → at 5x becomes -15).
  // The value is injected into the first-pass needs impact eval prompt and the Director (needs_impact)
  // so both the model emission and any corrections are produced at the user-requested scale.
  // Applied as rawDelta * strength (safety) in the evaluator for both authority and legacy paths.
  // Stored per-card (and per-member via frontPorch in groups). Default 1 = no behavior change.
  int needsSimStrength;

  // Per-need baseline values (0-100). Used to seed the needs vector when starting a new session
  // with this character. Default 80 matches legacy initialization behavior.
  int needsBaselineHunger;
  int needsBaselineBladder;
  int needsBaselineEnergy;
  int needsBaselineSocial;
  int needsBaselineFun;
  int needsBaselineHygiene;
  int needsBaselineComfort;

  // Per-need decay rates (0-10). Applied as base decay per turn in tickDecay().
  // Defaults match the legacy hardcoded NeedsSimulation.needDecay values.
  int needsDecayHunger;
  int needsDecayBladder;
  int needsDecayEnergy;
  int needsDecaySocial;
  int needsDecayFun;
  int needsDecayHygiene;
  int needsDecayComfort;

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

  /// Stable identity UUID for this logical character.
  /// Carried inside the PNG (under extensions.front_porch.realism_engine.stable_id).
  /// Generated once per library entry (on create/import/touch); used to match on
  /// re-import (e.g. after realism/needs edits) so that dbId + sessions are preserved.
  /// Legacy cards without it get one injected on first save/import.
  /// Duplicates get fresh stableId. Never changes for an existing library character.
  String? stableId;

  /// App-internal character tier. `'lite'` marks a Scene Guest (Lite NPC):
  /// a real library character that can join a 1:1 scene as its own bubble but
  /// carries NO Realism Engine / Needs state (parity-safe). `null` = a normal
  /// full character. Stored inside the PNG extensions only; never affects
  /// external direct-writer schema.
  String? tier;

  /// The character's starred "canonical avatar": the id of an `avatar_images`
  /// row (a gallery look OR an expression image) to use as the card cover on
  /// export and as the default face a new chat opens with. `null` = the portrait
  /// (`imagePath`). Exactly one at a time. A pointer only — it never mutates
  /// `imagePath`. Stored inside the PNG extensions (no external-writer schema).
  String? favoriteAvatarId;

  FrontPorchExtensions({
    this.realismEnabled = false,
    this.shortTermBond = 0,
    this.longTermBond = 0,
    this.trustLevel = 0,
    this.dayCount = 1,
    this.timeOfDay = 'morning',
    this.storyStartDate,
    this.storyStartTime,
    this.characterEmotion = '',
    this.emotionIntensity = 'mild',
    this.nsfwCooldownEnabled = false,
    this.passageOfTimeEnabled = true, // defaults to on when realism is enabled
    this.chaosModeEnabled = false,
    this.needsSimEnabled = false,
    this.enjoysLowHygiene = false,
    // Never mutated in place — always replaced wholesale (copyWith/editor),
    // so the const default is safe.
    this.ambitions = const [],
    this.planLines = const [],
    this.likes = const [],
    this.dislikes = const [],
    this.intimateInto = const [],
    this.intimateNotInto = const [],
    this.inventory = const {},

    // Realism Verification (Director/Verifier) — optional, off by default (zero cost when off)
    this.realismVerificationEnabled = false,
    this.realismVerificationMaxReprocesses = 1,
    this.realismVerificationStrictness = 3,

    // Director authority on needs deltas (simple model+Director path; off default = legacy conservative)
    this.realismNeedsDirectorAuthority = false,

    // Needs delta strength (1-5). Injected into the first needs-impact model call and (when Director
    // authority is enabled) the verifier prompt so the model and Director emit/correct deltas at the
    // requested magnitude on the first pass. The Director must not receive an already-scaled value
    // and then scale it again. What the (Director-corrected) call returns is applied directly.
    this.needsSimStrength = 1,

    // Per-need baseline values (0-100). Default 80 matches legacy initialization.
    this.needsBaselineHunger = 80,
    this.needsBaselineBladder = 80,
    this.needsBaselineEnergy = 80,
    this.needsBaselineSocial = 80,
    this.needsBaselineFun = 80,
    this.needsBaselineHygiene = 80,
    this.needsBaselineComfort = 80,

    this.needsDecayHunger = 4,
    this.needsDecayBladder = 6,
    this.needsDecayEnergy = 3,
    this.needsDecaySocial = 2,
    this.needsDecayFun = 2,
    this.needsDecayHygiene = 1,
    this.needsDecayComfort = 2,

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
    this.stableId,
    this.tier,
    this.favoriteAvatarId,
  });

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
        'tier': ?tier,
        'favorite_avatar_id': ?favoriteAvatarId,
      },
    };
  }

  factory FrontPorchExtensions.fromJson(Map<String, dynamic> json) {
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
      needsSimEnabled: realism['needs_sim_enabled'] as bool? ?? false,
      enjoysLowHygiene: realism['enjoys_low_hygiene'] as bool? ?? false,
      ambitions: _phrases(realism['ambitions']),
      planLines: _phrases(realism['plan_lines']),
      likes: _phrases(realism['likes']),
      dislikes: _phrases(realism['dislikes']),
      intimateInto: _phrases(_intimate(realism)['into']),
      intimateNotInto: _phrases(_intimate(realism)['not_into']),
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
      needsSimStrength: realism['needs_sim_strength'] as int? ?? 1,
      needsBaselineHunger: realism['needs_baseline_hunger'] as int? ?? 80,
      needsBaselineBladder: realism['needs_baseline_bladder'] as int? ?? 80,
      needsBaselineEnergy: realism['needs_baseline_energy'] as int? ?? 80,
      needsBaselineSocial: realism['needs_baseline_social'] as int? ?? 80,
      needsBaselineFun: realism['needs_baseline_fun'] as int? ?? 80,
      needsBaselineHygiene: realism['needs_baseline_hygiene'] as int? ?? 80,
      needsBaselineComfort: realism['needs_baseline_comfort'] as int? ?? 80,
      needsDecayHunger: realism['needs_decay_hunger'] as int? ?? 4,
      needsDecayBladder: realism['needs_decay_bladder'] as int? ?? 6,
      needsDecayEnergy: realism['needs_decay_energy'] as int? ?? 3,
      needsDecaySocial: realism['needs_decay_social'] as int? ?? 2,
      needsDecayFun: realism['needs_decay_fun'] as int? ?? 2,
      needsDecayHygiene: realism['needs_decay_hygiene'] as int? ?? 1,
      needsDecayComfort: realism['needs_decay_comfort'] as int? ?? 2,
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
      tier: realism['tier'] as String?,
      favoriteAvatarId: realism['favorite_avatar_id'] as String?,
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
      stableId: stableId ?? this.stableId,
      tier: tier ?? this.tier,
      favoriteAvatarId: favoriteAvatarId ?? this.favoriteAvatarId,
    );
  }

  static final Uuid _uuid = Uuid();

  /// Ensures this extensions object has a non-empty stableId.
  /// Generates a fresh v4 UUID only if missing or empty.
  /// Call this on any FP object right before a saveCardAsPng / persist that will embed it
  /// (creation, realism edits, import collision update-in-place, duplicate gets fresh instead).
  void ensureStableId() {
    if (stableId == null || stableId!.isEmpty) {
      stableId = _uuid.v4();
    }
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
  /// V2 spec credits — round-trip so Stoop/Chub author names survive import.
  String creator;
  String creatorNotes;
  String characterVersion;
  String? dbId; // UUID primary key (runtime only, not serialized)
  DateTime? createdAt; // library "date added" from DB (runtime only, not serialized)
  FrontPorchExtensions? frontPorchExtensions; // V2.5 Realism Engine defaults
  Map<String, dynamic>?
  rawExtensions; // Preserve unknown third-party extension keys
  List<AvatarImage>? avatarImages; // Multiple avatar images for the character
  int primeAvatarIndex = 1; // 1-based index of the prime (default) avatar

  CharacterCard({
    this.dbId,
    this.creator = '',
    this.creatorNotes = '',
    this.characterVersion = '',
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
      'character_book': lorebook == null ? null : encodeCharacterBook(lorebook!),
      'world_names': worldNames,
      if (ttsVoice != null) 'tts_voice': ttsVoice,
      if (creator.isNotEmpty) 'creator': creator,
      if (creatorNotes.isNotEmpty) 'creator_notes': creatorNotes,
      if (characterVersion.isNotEmpty) 'character_version': characterVersion,
      'extensions': ?extensions,
    };
  }

  String replacePlaceholders(String text, {String userName = 'You'}) {
    return MacroResolver().resolve(
      text,
      MacroContext(userName: userName, characterName: name),
    );
  }

  String get formattedDescription => replacePlaceholders(description);

  /// Whether this card has any Front Porch extensions configured.
  bool get hasFrontPorchExtensions => frontPorchExtensions != null;

  /// Whether this card is a Scene Guest (Lite NPC): a real library character
  /// that can join a 1:1 scene as its own bubble but carries no Realism/Needs
  /// state. Determined by `frontPorchExtensions.tier == 'lite'`.
  bool get isLite => frontPorchExtensions?.tier == 'lite';
}
