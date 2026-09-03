// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Feature-system tables: worlds/RAG/journal/growth/objectives/stories/
// members/web-auth. See database.dart for the shared @DriftDatabase table
// list and schema-wide docs.

part of 'database.dart';

/// World/lorebook definitions (Living Worlds: portable places).
class Worlds extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get lorebook => text().nullable()(); // JSON blob
  TextColumn get linkedCharacterName => text().nullable()();
  // v40 — Living Worlds (docs/design/living-worlds.md)
  TextColumn get coverImage => text().nullable()();
  IntColumn get formatVersion => integer().withDefault(const Constant(1))();
  TextColumn get sourceId => text().nullable()();
  TextColumn get linkedCharacterId => text().nullable()();

  /// Built-in biome id; null ⇒ temperate.
  TextColumn get biomeId => text().nullable()();

  /// Full custom biome JSON (phase 2); null when using a built-in.
  TextColumn get biomeJson => text().nullable()();

  /// Description injection opt-in; false for rows migrated from library labels.
  BoolColumn get injectDescription =>
      boolean().withDefault(const Constant(true))();

  /// v51 — per-world climate/weather/atmosphere/gravity plug. Default ON so
  /// every existing world keeps its weather machine; false is a lorebook-only
  /// bookshelf world. SQLite INTEGER 1/0, same shape as [injectDescription].
  BoolColumn get climateEnabled =>
      boolean().withDefault(const Constant(true))();

  /// v41 — place traits JSON (atmosphere/gravity enums + future trait keys;
  /// one flexible column so new traits never need another migration).
  TextColumn get placeTraits => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Per-chat world attachments (session id space for 1:1 and group chats).
/// groups.world_ids remains a template applied at chat creation.
class ChatWorlds extends Table {
  TextColumn get id => text()();
  TextColumn get chatId => text()();
  TextColumn get worldId => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Biome changeover spans — full biome snapshot, never a live pointer.
/// effective_from_day is story dayCount when the span began.
class ChatBiomeSpans extends Table {
  TextColumn get id => text()();
  TextColumn get chatId => text()();
  IntColumn get effectiveFromDay => integer()();
  TextColumn get biomeJson => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Message embeddings for RAG memory retrieval.
class MessageEmbeddings extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get characterId => text().nullable()();
  IntColumn get positionStart => integer()();
  IntColumn get positionEnd => integer()();
  TextColumn get content => text()();
  BlobColumn get embedding => blob()();
  IntColumn get dimensions => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// 'message' for normal RAG windows (default). DORMANT: the 'needs_event'
  /// type (and its writer/reader in MemoryService) was removed with the
  /// Journal work — column kept for additive-migration safety.
  TextColumn get memoryType => text().withDefault(const Constant('message'))();

  /// Optional JSON blob for event details. DORMANT (see memoryType) —
  /// null for ordinary message embeddings.
  TextColumn get metadata => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Single-row sync metadata for version-based cloud sync.
class SyncMeta extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get version => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastModifiedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Data Bank entries — user-provided knowledge per character for RAG retrieval.
class DataBankEntries extends Table {
  TextColumn get id => text()();
  TextColumn get characterId => text()(); // which character this belongs to
  TextColumn get title => text()(); // user-given label
  TextColumn get content => text()(); // the actual text content
  BlobColumn get embedding =>
      blob().nullable()(); // pre-computed embedding vector
  IntColumn get dimensions => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// The Journal — per-chat, per-character memory cards
/// (design: docs/design/journal-memory.md).
/// Strictly session-scoped: cards never cross chats. Phase-2 columns (heat,
/// accessCount, embedding) are present from day one so no second migration
/// is needed when the emotional-physics layer lands.
@TableIndex(
  name: 'journal_memories_session_character',
  columns: {#sessionId, #characterId},
)
@DataClassName('JournalMemoryData')
class JournalMemories extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get sessionId => text()(); // scoping key — cards never cross chats
  TextColumn get characterId => text()(); // diary owner (stableGroupId)

  /// JSON array of int message POSITIONS (not DB ids — message UUIDs are
  /// regenerated on every save, so positions are the stable receipt, same
  /// trade-off MessageEmbeddings.positionStart/End already makes).
  TextColumn get sourceMessageIds => text().nullable()();
  TextColumn get content => text()(); // the memory, first person
  TextColumn get category => text().withDefault(
    const Constant('moment'),
  )(); // about_user/about_us/moment/promise
  TextColumn get emotionLabel => text().nullable()(); // current feeling
  TextColumn get emotionIntensity =>
      text().nullable()(); // mild/moderate/strong
  TextColumn get originalEmotionLabel =>
      text().nullable()(); // set only when the feeling was later revised
  RealColumn get heat => real().withDefault(const Constant(1.0))(); // phase 2
  IntColumn get accessCount =>
      integer().withDefault(const Constant(0))(); // phase 2
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BlobColumn get embedding => blob().nullable()(); // phase 2
  IntColumn get dimensions => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastAccessedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get metadata =>
      text().nullable()(); // JSON pouch (additive future)

  @override
  Set<Column> get primaryKey => {id};
}

/// Growth Rings — per-chat, per-character personality growth entries
/// (design: docs/design/growth-rings.md). Replaces the monolithic evolved
/// personality/scenario blobs. Strictly session-scoped: rings never cross
/// chats and die with the chat (same invariant as JournalMemories).
@TableIndex(
  name: 'growth_rings_session_character',
  columns: {#sessionId, #characterId},
)
@DataClassName('GrowthRingData')
class GrowthRings extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get sessionId => text()(); // scoping key — rings never cross chats
  TextColumn get characterId => text()(); // ring owner (stableGroupId)
  TextColumn get content => text()(); // one sentence, {{char}}/{{user}} macros
  TextColumn get category => text().withDefault(
    const Constant('trait'),
  )(); // trait/stance/habit/skill/scar/archive
  RealColumn get strength => real().withDefault(
    const Constant(0.3),
  )(); // 0..1; tiers derived in GrowthPhysics (emerging/developing/established)
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get retired => boolean().withDefault(
    const Constant(false),
  )(); // past growth — visible in history, never injected

  /// JSON array of int message POSITIONS (receipts; reinforcement appends).
  /// Positions, not DB ids — same trade-off as JournalMemories.
  TextColumn get sourceMessageIds => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastReinforcedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get metadata =>
      text().nullable()(); // JSON pouch (additive future)

  @override
  Set<Column> get primaryKey => {id};
}

/// Growth Rings — per-session pass cursor (its own row instead of a Sessions
/// column so the Character-Card-Forge-written tables stay untouched).
@DataClassName('GrowthStateData')
class GrowthState extends Table {
  TextColumn get sessionId => text()();
  IntColumn get cursor => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {sessionId};
}

/// Objectives — quest/task system for guided roleplay.
class Objectives extends Table {
  TextColumn get id => text()();
  TextColumn get characterId =>
      text()(); // which character this objective belongs to
  TextColumn get chatId =>
      text().nullable()(); // session ID this objective belongs to
  TextColumn get objective => text()(); // the main goal
  TextColumn get tasks => text().withDefault(
    const Constant('[]'),
  )(); // JSON array of {description, completed}
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  BoolColumn get isPrimary => boolean().withDefault(
    const Constant(false),
  )(); // Primary vs secondary goal
  IntColumn get checkFrequency => integer().withDefault(
    const Constant(3),
  )(); // check task completion every N messages
  IntColumn get injectionDepth => integer().withDefault(
    const Constant(4),
  )(); // how many messages from end to inject (0=strongest)

  /// v46 — the ambition this objective is a step toward, stored as the
  /// ambition's TEXT (the same string the card authors and the journal
  /// progress cards key on), or NULL for a situational quest that serves no
  /// long-term goal.
  ///
  /// Nullable with no default on purpose: NULL is a real, common answer, not
  /// a missing value. Ambition (the mountain) → Objectives (the switchbacks)
  /// → Tasks (the steps); most switchbacks are on the mountain, but life
  /// happens and some are not.
  ///
  /// Text and not an index: ambitions live in the card's `ambitions` list,
  /// which the author can reorder or edit at any time, so a stored index
  /// would silently start pointing at a different goal. The text is what
  /// AmbitionService already keys progress on, so the two agree by
  /// construction.
  TextColumn get servedAmbition => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Porch Stories — AI-generated novel projects.
class StoryProjects extends Table {
  TextColumn get id => text()();
  TextColumn get title =>
      text().withDefault(const Constant('Untitled Story'))();
  TextColumn get data => text()(); // Full StoryProject JSON blob
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Group-owned characters (decoupled from the singular CharacterRepository / library).
///
/// Per the clean-break architecture (2026-05): group members are fully separate entities.
/// They live only in this table + private files under StorageService.groupsDir/&lt;groupId&gt;/avatars/.
/// There is NO reference to library characters, no shared stable IDs, no automatic population,
/// and no JSON blob for the card definition itself — all fields are typed columns.
///
/// - Internal id: UUID (v4) generated at copy/add time. Used for all per-member keys
///   (realism in defaultMemberRealismState, characterSystemPrompts, objectives, RAG, etc.).
/// - Exactly one primary avatar PNG per member (avatarFilename); multi-avatar/expressions
///   explicitly not supported for groups.
/// - The only path from a group member into the user's singular library is the explicit
///   user-initiated "Separate to my library" (extract) action.
/// - On group delete, the row(s) and the entire groups/&lt;groupId&gt;/ tree are removed (best effort).
///
/// External companion tools writing groups must not assume members; they write to this
/// table for group card fidelity. The human will notify such tools after this feature is
/// 100% complete and stable.
@DataClassName('GroupMemberRow')
class GroupMembers extends Table {
  TextColumn get id =>
      text()(); // UUID PK — stable for this member *inside this group only*
  TextColumn get groupId => text()(); // references Groups.id

  // Full card definition as typed columns (no JSON blob for the member "character" itself).
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

  /// Basename of the single primary PNG stored in this group's private avatars dir.
  /// Resolved at runtime via StorageService.groupsDir + groupId + 'avatars' + this filename.
  /// Never a full path, never an expression list.
  TextColumn get avatarFilename => text().nullable()();

  TextColumn get ttsVoice => text().nullable()();

  TextColumn get lorebook =>
      text().nullable()(); // JSON (same shape as Characters.lorebook)
  TextColumn get worldNames =>
      text().withDefault(const Constant('[]'))(); // JSON array

  /// JSON of FrontPorchExtensions (realism defaults etc.) + any raw third-party extensions.
  TextColumn get frontPorchExtensions => text().nullable()();
  TextColumn get rawExtensions => text().nullable()();

  /// Small JSON for any *group-scoped* per-member state that travels with the group definition
  /// (e.g. initial realism seed fragments specific to this membership, or future overrides).
  /// The primary evolving per-char realism + needs lives in sessions.group_realism_state
  /// (keyed by these member UUIDs) and groups.defaultMemberRealismState (for seeds/export).
  /// This column keeps the member rows free of "the card" blobs while still self-contained.
  TextColumn get memberState => text().withDefault(const Constant('{}'))();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// IntColumn (not DateTime) DEFAULT 0 — byte-matches the repaired physical
  /// shape. Was repair-only until 2026-08-04; see Sessions.themeOverrides.
  IntColumn get createdAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Web UI secure-login account credentials (the rewritten web server's auth).
///
/// Single-account model: exactly one row with id 'local'. Replaces the old
/// plaintext 6-digit web-server PIN. New table (v33); must never be confused
/// with the chat [Sessions] table.
class WebAuthCredentials extends Table {
  TextColumn get id => text()(); // always 'local' for the single host account
  TextColumn get username => text()();
  TextColumn get passwordHash => text()(); // Argon2id PHC string (hashlib)
  TextColumn get totpSecret =>
      text().nullable()(); // base32, only if 2FA set up
  BoolColumn get totpEnabled => boolean().withDefault(const Constant(false))();
  TextColumn get recoveryCodes =>
      text().nullable()(); // JSON array of Argon2id-hashed single-use codes
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Persisted web-login sessions (one row per signed-in device).
///
/// The raw cookie token is never stored — only its SHA-256 ([tokenHash]) — so a
/// DB leak cannot be replayed as a live session. Time fields are epoch
/// milliseconds for precise sliding-expiry math. NEW table (v33); not an
/// external-writer table.
class WebAuthSessions extends Table {
  TextColumn get id => text()(); // internal row uuid (NOT the cookie value)
  TextColumn get tokenHash => text()(); // SHA-256 hex of the raw cookie token
  TextColumn get userId => text()(); // -> web_auth_credentials.id
  IntColumn get createdAt => integer().withDefault(const Constant(0))();
  IntColumn get lastSeenAt => integer().withDefault(const Constant(0))();
  IntColumn get expiresAt => integer().withDefault(const Constant(0))();
  TextColumn get userAgent => text().nullable()();
  TextColumn get ip => text().nullable()();
  BoolColumn get revoked => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
