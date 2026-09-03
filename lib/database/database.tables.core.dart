// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Core library/chat/group/persona tables (Characters, AvatarImages, Sessions,
// Messages, Groups, Folders, Personas). See database.dart for the shared
// @DriftDatabase table list and schema-wide docs.

part of 'database.dart';

// ── Table Definitions ─────────────────────────────────────────────────

/// Characters table - stores metadata extracted from PNG tEXt chunks.
/// The PNG file remains the source of truth for import/export interop.
class Characters extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get personality => text().withDefault(const Constant(''))();
  TextColumn get scenario => text().withDefault(const Constant(''))();
  TextColumn get firstMessage => text().withDefault(const Constant(''))();
  TextColumn get mesExample => text().withDefault(const Constant(''))();
  TextColumn get systemPrompt => text().withDefault(const Constant(''))();
  TextColumn get postHistoryInstructions =>
      text().withDefault(const Constant(''))();
  TextColumn get alternateGreetings =>
      text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get tags =>
      text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get imagePath => text().nullable()();
  TextColumn get ttsVoice => text().nullable()();
  TextColumn get folderId => text().nullable()();
  TextColumn get lorebook => text().nullable()(); // JSON blob
  TextColumn get worldNames =>
      text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get memorySources => text().withDefault(
    const Constant('[]'),
  )(); // JSON array of character IDs for cross-character RAG
  TextColumn get evolvedPersonality => text().withDefault(
    const Constant(''),
  )(); // LLM-evolved personality overlay
  TextColumn get evolvedScenario =>
      text().withDefault(const Constant(''))(); // LLM-evolved scenario overlay
  IntColumn get evolutionCount =>
      integer().withDefault(const Constant(0))(); // number of evolutions
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get primeAvatarIndex => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Avatar images for characters.
/// Each character can have up to 10 avatars stored in their subdirectory.
class AvatarImages extends Table {
  TextColumn get id => text()();
  TextColumn get characterId => text()();
  TextColumn get filename => text()();
  TextColumn get label => text().nullable()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Chat sessions - one per conversation thread.
class Sessions extends Table {
  TextColumn get id => text()(); // timestamp-based ID
  TextColumn get characterId => text().nullable()();
  TextColumn get groupId => text().nullable()();
  TextColumn get name => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get authorNote => text().withDefault(const Constant(''))();
  IntColumn get authorNoteDepth => integer().withDefault(const Constant(4))();
  TextColumn get summary => text().nullable()(); // rolling chat summary
  IntColumn get summaryLastIndex =>
      integer().nullable()(); // message index at last summary update
  /// True once this chat's world attachments have been decided — either seeded
  /// at creation, back-filled from the character, or set by hand (including
  /// deliberately emptied). Lets an empty list mean "the user removed them"
  /// instead of "this chat predates the character having a world", so a
  /// back-fill can never undo a deliberate detach.
  BoolColumn get worldsInitialized =>
      boolean().withDefault(const Constant(false))();
  TextColumn get parentSession => text().nullable()();
  IntColumn get forkIndex => integer().nullable()();
  IntColumn get affectionScore =>
      integer().withDefault(const Constant(0))(); // short-term tension points
  IntColumn get relationshipTier =>
      integer().withDefault(const Constant(0))(); // short-term tier
  IntColumn get longTermScore =>
      integer().withDefault(const Constant(0))(); // slowly accumulating bond
  IntColumn get longTermTier =>
      integer().withDefault(const Constant(0))(); // long-term rank
  IntColumn get turnsSinceLongTermCheck =>
      integer().withDefault(const Constant(0))(); // long-term check window
  IntColumn get shortTermDeltasSummary =>
      integer().withDefault(const Constant(0))(); // trends over the LT window
  BoolColumn get realismEnabled =>
      boolean().withDefault(const Constant(false))(); // master realism toggle
  IntColumn get shortTermMood =>
      integer().withDefault(const Constant(0))(); // -5 to +5
  IntColumn get moodDecayCounter =>
      integer().withDefault(const Constant(0))(); // msgs since last mood change
  TextColumn get characterEmotion =>
      text().withDefault(const Constant(''))(); // e.g. "amused"
  TextColumn get emotionIntensity =>
      text().withDefault(const Constant(''))(); // mild/moderate/strong
  TextColumn get timeOfDay =>
      text().withDefault(const Constant('morning'))(); // dawn/morning/etc
  IntColumn get dayCount =>
      integer().withDefault(const Constant(1))(); // starts at Day 1
  IntColumn get startDayOfWeek => integer().withDefault(
    const Constant(0),
  )(); // 1=Mon..7=Sun; legacy anchor, now WRITTEN as weekday(storyStartDate) so external readers stay consistent
  TextColumn get storyClock => text()
      .nullable()(); // ISO-8601 story datetime — canonical clock (design: story-calendar.md)
  TextColumn get storyStartDate => text()
      .nullable()(); // ISO-8601 date of Day 1 — canonical anchor; null = legacy row (synthesized on load)
  BoolColumn get nsfwCooldownEnabled =>
      boolean().withDefault(const Constant(false))(); // sub-toggle
  BoolColumn get passageOfTimeEnabled => boolean().withDefault(
    const Constant(true),
  )(); // sub-toggle for automatic time advancement
  IntColumn get arousalLevel =>
      integer().withDefault(const Constant(0))(); // 0 to 10 scale
  IntColumn get cooldownTurnsRemaining =>
      integer().withDefault(const Constant(0))(); // 0 = no cooldown
  IntColumn get cooldownTurnsTotal => integer().withDefault(
    const Constant(0),
  )(); // refractory length at climax — persists the cooldown progress denominator

  // Realism Engine v3.0 Behavioral Mechanics
  IntColumn get trustLevel =>
      integer().withDefault(const Constant(0))(); // -100 to 100 paranoia/trust
  TextColumn get activeFixation =>
      text().withDefault(const Constant(''))(); // ongoing obsession topic
  IntColumn get fixationLifespan =>
      integer().withDefault(const Constant(0))(); // decay turns
  TextColumn get spatialStance =>
      text().withDefault(const Constant(''))(); // physical anchor
  /// v49 — 1:1 glance bit. NULL = unknown (keyword fallback).
  /// Group members keep theirs in group_realism_state.
  BoolColumn get withUser => boolean().nullable()();
  BoolColumn get trustRepairPending => boolean().withDefault(
    const Constant(false),
  )(); // repair window armed after severe trust drop

  // Chance Time / Chaos Mode (v21)
  BoolColumn get chaosModeEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get chaosPressure => integer().withDefault(
    const Constant(0),
  )(); // 0-100 escalating trigger chance

  // Sims/Needs Simulation (clean port on 0.9.8)
  BoolColumn get needsSimEnabled =>
      boolean().withDefault(const Constant(false))(); // per-session toggle
  TextColumn get needsVector =>
      text().nullable()(); // JSON map of current need levels

  /// v47 — the 1:1 speaker's Pockets record, as `{worn: [...], carrying: [...]}`.
  ///
  /// The mirror of [needsVector], and it exists for the same reason. Group
  /// chats persist their per-member pockets inside `group_realism_state`, so
  /// they always survived a reload; a 1:1 chat had NO home for the record at
  /// all. It lived in memory, snapshotted into each message's `realism_state`
  /// — but that snapshot is only restored on regen, swipe and delete, never on
  /// session load. So closing a 1:1 chat and reopening it emptied her pockets,
  /// while the feature's own description promised the opposite. Straight
  /// 1:1-vs-group parity break.
  ///
  /// Nullable with no default: NULL means "nothing recorded", which is the
  /// honest value both for every chat that predates this column and for any
  /// chat where Pockets is switched off.
  TextColumn get pockets => text().nullable()();

  /// v48 — the live Today side-quest row for this chat, or null if none.
  ///
  /// Shape is not enough: a user-typed secondary is also isPrimary false,
  /// tasks [], servedAmbition null. Persist the id so reload rebinds this
  /// row and never guesses among secondaries. Nullable, no default: every
  /// chat older than the column has no Today hold.
  TextColumn get todayObjectiveId => text().nullable()();

  // Per-session character evolution (v19)
  // 1:1 chats: plain evolved text
  TextColumn get evolvedPersonality => text().withDefault(const Constant(''))();
  TextColumn get evolvedScenario => text().withDefault(const Constant(''))();
  IntColumn get evolutionCount => integer().withDefault(const Constant(0))();
  // Group chats: JSON maps { charId → evolved text }
  TextColumn get groupEvolvedPersonalities =>
      text().withDefault(const Constant('{}'))();
  TextColumn get groupEvolvedScenarios =>
      text().withDefault(const Constant('{}'))();

  // Per-session generation parameter overrides (v22)
  TextColumn get generationSettings =>
      text().nullable()(); // JSON blob, null = use global defaults

  // User persona linked to this session (v25)
  TextColumn get userPersonaId => text().nullable()();

  /// The gallery "look" (avatar) selected for THIS chat, or null → show the
  /// character's library face (`imagePath`). Per-chat selection over the global
  /// look collection. Nullable + additive.
  TextColumn get selectedLookAvatarId => text().nullable()();

  /// Per-chat theme overrides JSON. Was repair-only until 2026-08-04 — fresh
  /// createAll() DBs (unit tests) lacked it. No schemaVersion bump: live DBs
  /// get it from the always-on repair before open() returns. Raw-SQL access.
  TextColumn get themeOverrides => text().nullable()();
  TextColumn get contextBudgetJson => text().nullable()(); // v44 Context Budget

  /// Per-chat Objectives switch (v45). Defaults TRUE because objectives have
  /// always run unconditionally — every existing row must keep behaving
  /// exactly as it did, so the migration's default is the no-op value.
  /// AND-gated against the global `objectivesEnabled` the same way
  /// [needsSimEnabled] is gated against `needsSimDefault`.
  BoolColumn get objectivesEnabled =>
      boolean().withDefault(const Constant(true))();

  /// Live per-character realism/needs state for group sessions.
  /// JSON map: { charId: { emotion, needs, affection, trust, fixation, relationships, ... } }
  /// Replaces the old hidden __group_state__ checkpoint message system (clean break in v30).
  /// Only populated for sessions where groupId is not null.
  TextColumn get groupRealismState =>
      text().withDefault(const Constant('{}'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Individual chat messages within a session.
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  IntColumn get position => integer()(); // ordering within session
  TextColumn get sender => text()();
  BoolColumn get isUser => boolean()();
  TextColumn get characterId => text().nullable()(); // for group chats
  TextColumn get swipes =>
      text().withDefault(const Constant('[]'))(); // JSON array
  IntColumn get swipeIndex => integer().withDefault(const Constant(0))();
  TextColumn get swipeDurations =>
      text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get metadata => text().nullable()();
  TextColumn get swipeMetadata => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Group chat definitions.
class Groups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get characterIds =>
      text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get turnOrder =>
      text().withDefault(const Constant('roundRobin'))();
  BoolColumn get autoAdvance => boolean().withDefault(const Constant(false))();
  BoolColumn get directorMode => boolean().withDefault(const Constant(false))();
  TextColumn get firstMessage => text().withDefault(const Constant(''))();
  TextColumn get scenario => text().withDefault(const Constant(''))();
  TextColumn get systemPrompt => text().withDefault(const Constant(''))();

  /// Portable default realism/needs state for this group definition.
  /// JSON: { charId: { emotion, needs, affection, trust, fixation, relationships, ... } }
  /// Used for Group Card export/import and as seed when starting new group sessions
  /// or splitting group members to solo characters.
  /// Added in schema v30 as part of proper DB-backed group realism (clean break from
  /// old hidden __group_state__ checkpoint messages).
  TextColumn get defaultMemberRealismState =>
      text().withDefault(const Constant('{}'))();

  // v31: Group-level config columns stored as first-class typed Drift columns (Bool/Text)
  // rather than inside JSON blobs or overloaded existing fields. This follows the v30
  // precedent of surfacing hidden state (the old __group_state__ messages) into explicit,
  // queryable, self-documenting columns. Explicit columns improve type safety, allow
  // simpler direct SQL from external tools, and make Group Card round-tripping obvious.
  BoolColumn get chaosModeEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get chaosNsfwEnabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get groupLorebook => text().withDefault(const Constant(''))();
  TextColumn get worldIds => text().withDefault(
    const Constant('[]'),
  )(); // JSON array of world IDs for scoping
  BoolColumn get inheritCharacterLorebooks =>
      boolean().withDefault(const Constant(true))();

  /// Immutable creation-time baseline realism/needs seed for this group definition.
  /// JSON shape is identical to defaultMemberRealismState and sessions.group_realism_state.
  /// This is the frozen seed captured at group creation / Group Card import time only.
  /// Distinct from defaultMemberRealismState (which can be updated later for new sessions).
  /// Clean column (not a blob) per v30 philosophy of explicit storage — makes the
  /// immutable-seed contract visible to code and to external direct-SQL tools.
  /// Added in schema v31.
  TextColumn get baselineRealismState =>
      text().withDefault(const Constant('{}'))();

  /// Per-character system prompt overrides scoped to this group.
  /// Stored as a first-class JSON column (Map&lt;String, String&gt; keyed by stable charId).
  ///
  /// This was previously the last remaining "Path B" transitional hack stored inside
  /// the defaultMemberRealismState JSON blob. As of v32 it has its own proper column.
  /// The old extraction/promotion logic inside the realism blob has been fully removed.
  ///
  /// Takes precedence over a character's normal system prompt when that character
  /// speaks inside this specific group, but sits under the group-level systemPrompt.
  TextColumn get characterSystemPrompts =>
      text().withDefault(const Constant('{}'))();

  /// Portable, device-independent stable id for this group (schema v34).
  ///
  /// Distinct from [id] (a device-local `group_<timestamp>` handle): this id
  /// travels in the exported Group Card and is preserved on import, so a shared
  /// group can be UPDATED in place on The Stoop (no duplicate) and re-associated
  /// after switching devices — the group analogue of a character's stable id.
  /// Nullable + additive. Generated lazily in code.
  TextColumn get stableId => text().nullable()();

  /// Home-screen folder membership (schema v42), the group analogue of
  /// Characters.folderId. Null = top level. Nullable + additive.
  TextColumn get folderId => text().nullable()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Character folder organization.
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// User personas.
class Personas extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant('User'))();
  TextColumn get persona => text().withDefault(const Constant(''))();
  TextColumn get learnedFacts => text().withDefault(
    const Constant('[]'),
  )(); // JSON array of fact strings from auto-persona
  TextColumn get avatarPath => text().nullable()();

  /// v50 — optional calendar birthday (`YYYY-MM-DD`). NULL = unset.
  /// Feb 29 is rejected in code; the column does not enforce it.
  TextColumn get birthday => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
