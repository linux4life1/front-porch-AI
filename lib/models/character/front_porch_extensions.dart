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
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/models/character/front_porch_extensions_codec.dart';
import 'package:front_porch_ai/models/greeting_realism_seed.dart';

/// Front Porch AI V2.5 extensions — stored inside V2 `extensions.front_porch`.
///
/// These values seed the Realism Engine's initial state when a new
/// conversation is started with a character. Existing sessions use their
/// own DB-persisted state and are not affected.
///
/// stableId (inside realism_engine) provides a persistent identity across
/// PNG rewrites/reimports so that library dbId and chat history are never lost
/// on realism/needs edits (import path now updates in place for stable matches).

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

  /// The card's own Needs choice; null when the card says nothing (no
  /// `needs_sim_enabled` key, e.g. an imported Chub or SillyTavern card).
  /// A silent card lets the Porch Life Needs switch decide when a chat
  /// starts (maintainer ruling 2026-10-10); an explicit false still wins.
  /// Kept null through copyWith and toJson so a re-save never invents a
  /// false the card did not have.
  bool? needsSimChoice;

  /// True only when the card explicitly asks for Needs. Not "does this card
  /// get Needs": a silent card reads false here yet follows the Porch Life
  /// switch, so anything deciding whether a chat runs Needs reads
  /// [needsSimChoice] (ChatService `_seedNeedsSim`).
  bool get needsSimEnabled => needsSimChoice ?? false;
  set needsSimEnabled(bool value) => needsSimChoice = value;

  /// Per-character Pockets & Wardrobe. AND-gated with the Porch Life global
  /// (`realismSettings.pocketsEnabled`). Missing / null JSON treats as **on**
  /// so old cards keep running when the global is on. Explicit false disables
  /// this character only.
  bool pocketsEnabled;
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

  /// Occupation, hours, job brief, and which weekdays they work — identity.
  /// Travel with the card like [planLines]. Blank occupation/hours/brief are
  /// omitted from JSON. [workDays] is DateTime.weekday ints (1=Mon…7=Sun);
  /// missing means Mon–Fri at derive; written `[]` means never at work.
  /// At-work is derived from these plus the story clock, not stored here.
  /// [occupationBrief] grounds at-work narration; empty means today — do
  /// not invent the job.
  String occupation;
  String hours;
  String occupationBrief;
  List<int>? workDays;

  /// Calendar birthday `YYYY-MM-DD`. Blank is omitted. Feb 29 is rejected
  /// at parse. Age and "days away" are story-clock math, not wall-clock.
  String birthday;

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

  // Director authority on needs deltas. Off by default.
  bool realismNeedsDirectorAuthority;

  /// Body pace: sloth, normal, or fast. Scales drops only.
  String needsPace;

  /// Need keys this character has turned off. Empty means all seven are on.
  /// The stored bar stays; it is just not worn, shown, or scored.
  /// Growable — Save / persist mutate this in place when a need is
  /// toggled. A const default throws "Cannot modify an unmodifiable list".
  List<String> needsOff;

  // Per-need baseline values (0-100). Used to seed the needs vector when starting a new session
  // with this character. Default 80 matches legacy initialization behavior.
  int needsBaselineHunger;
  int needsBaselineBladder;
  int needsBaselineEnergy;
  int needsBaselineSocial;
  int needsBaselineFun;
  int needsBaselineHygiene;
  int needsBaselineComfort;

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

  /// Sparse opening-state overlays, parallel to [CharacterCard.alternateGreetings].
  /// Index 0 = first alternate (`allGreetings[1]`). Null slot = read-the-room;
  /// empty overlay = inherit this object's card-level seeds and skip eval.
  /// `first_mes` keeps using the fields above.
  List<GreetingRealismSeed?> greetingSeeds;

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
    bool? needsSimEnabled,
    this.pocketsEnabled = true,
    this.enjoysLowHygiene = false,
    // Never mutated in place — always replaced wholesale (copyWith/editor),
    // so the const default is safe.
    this.ambitions = const [],
    this.planLines = const [],
    this.occupation = '',
    this.hours = '',
    this.occupationBrief = '',
    this.workDays,
    this.birthday = '',
    this.likes = const [],
    this.dislikes = const [],
    this.intimateInto = const [],
    this.intimateNotInto = const [],
    this.inventory = const {},

    // Realism Verification (Director/Verifier) — optional, off by default (zero cost when off)
    this.realismVerificationEnabled = false,
    this.realismVerificationMaxReprocesses = 1,
    this.realismVerificationStrictness = 3,

    this.realismNeedsDirectorAuthority = false,

    this.needsPace = 'normal',
    List<String>? needsOff,

    // Per-need baseline values (0-100). Default 80 matches legacy initialization.
    this.needsBaselineHunger = 80,
    this.needsBaselineBladder = 80,
    this.needsBaselineEnergy = 80,
    this.needsBaselineSocial = 80,
    this.needsBaselineFun = 80,
    this.needsBaselineHygiene = 80,
    this.needsBaselineComfort = 80,

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
    this.greetingSeeds = const [],
    this.stableId,
    this.tier,
    this.favoriteAvatarId,
  }) : needsSimChoice = needsSimEnabled,
       needsOff = List<String>.from(needsOff ?? const []);

  /// Parses `extensions.front_porch`. Malformed fields fall back to defaults
  /// rather than failing the import; see [decodeFrontPorchExtensions].
  factory FrontPorchExtensions.fromJson(
    Map<String, dynamic> json, {
    List<String> alternateGreetings = const [],
  }) =>
      decodeFrontPorchExtensions(json, alternateGreetings: alternateGreetings);

  Map<String, dynamic> toJson() => encodeFrontPorchExtensions(this);

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
    bool? pocketsEnabled,
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
    String? needsPace,
    List<String>? needsOff,
    int? needsBaselineHunger,
    int? needsBaselineBladder,
    int? needsBaselineEnergy,
    int? needsBaselineSocial,
    int? needsBaselineFun,
    int? needsBaselineHygiene,
    int? needsBaselineComfort,
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
      needsSimEnabled: needsSimEnabled ?? needsSimChoice,
      pocketsEnabled: pocketsEnabled ?? this.pocketsEnabled,
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
      needsPace: needsPace ?? this.needsPace,
      needsOff: List<String>.from(needsOff ?? this.needsOff),
      needsBaselineHunger: needsBaselineHunger ?? this.needsBaselineHunger,
      needsBaselineBladder: needsBaselineBladder ?? this.needsBaselineBladder,
      needsBaselineEnergy: needsBaselineEnergy ?? this.needsBaselineEnergy,
      needsBaselineSocial: needsBaselineSocial ?? this.needsBaselineSocial,
      needsBaselineFun: needsBaselineFun ?? this.needsBaselineFun,
      needsBaselineHygiene: needsBaselineHygiene ?? this.needsBaselineHygiene,
      needsBaselineComfort: needsBaselineComfort ?? this.needsBaselineComfort,
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

  /// Card-level opening used as the merge base for greeting overlays.
  GreetingOpeningBase get openingBase => GreetingOpeningBase(
    shortTermBond: shortTermBond,
    longTermBond: longTermBond,
    trustLevel: trustLevel,
    dayCount: dayCount,
    timeOfDay: timeOfDay,
    storyStartDate: storyStartDate,
    storyStartTime: storyStartTime,
    characterEmotion: characterEmotion,
    emotionIntensity: emotionIntensity,
    currentTask: currentTask,
    needsBaselineHunger: needsBaselineHunger,
    needsBaselineBladder: needsBaselineBladder,
    needsBaselineEnergy: needsBaselineEnergy,
    needsBaselineSocial: needsBaselineSocial,
    needsBaselineFun: needsBaselineFun,
    needsBaselineHygiene: needsBaselineHygiene,
    needsBaselineComfort: needsBaselineComfort,
    inventory: inventory,
  );
}
