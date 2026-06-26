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

import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/db_reunification_service.dart';

part 'database.g.dart';

const _uuid = Uuid();

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
      integer().withDefault(const Constant(0))(); // 5-turn counter
  IntColumn get shortTermDeltasSummary =>
      integer().withDefault(const Constant(0))(); // trends over 5 turns
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
  )(); // 1=Mon..7=Sun anchor for narrativeWeekday; 0=legacy/unset (compute on first load)
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
  // External direct-SQL writers (e.g. Character Card Forge) must supply values or rely
  // on the NOT NULL DEFAULTs when INSERTing into groups.
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
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// World/lorebook definitions.
class Worlds extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get lorebook => text().nullable()(); // JSON blob
  TextColumn get linkedCharacterName => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

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

  /// 'message' for normal RAG windows (default), 'needs_event' for long-term
  /// salient Needs simulation events (high-magnitude pleasure/embarrassment etc.).
  TextColumn get memoryType => text().withDefault(const Constant('message'))();

  /// Optional JSON blob for event details (e.g. {"category":"pleasure","magnitude":8,"..."}).
  /// Null for ordinary message embeddings.
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

  @override
  Set<Column> get primaryKey => {id};
}

/// Web UI secure-login account credentials (the rewritten web server's auth).
///
/// Single-account model: exactly one row with id 'local'. Replaces the old
/// plaintext 6-digit web-server PIN. This is a NEW table (v33) — it is NOT in
/// the Character Card Forge external-direct-writer set (characters/sessions/
/// messages/avatar_images/sync_meta) and must never be confused with the chat
/// [Sessions] table.
class WebAuthCredentials extends Table {
  TextColumn get id => text()(); // always 'local' for the single host account
  TextColumn get username => text()();
  TextColumn get passwordHash => text()(); // Argon2id PHC string (hashlib)
  TextColumn get totpSecret => text().nullable()(); // base32, only if 2FA set up
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

// ── Database Definition ─────────────────────────────────────────────────

@DriftDatabase(
  tables: [
    Characters,
    Sessions,
    Messages,
    Groups,
    Folders,
    Personas,
    Worlds,
    MessageEmbeddings,
    DataBankEntries,
    Objectives,
    StoryProjects,
    SyncMeta,
    AvatarImages,
    GroupMembers, // group-owned characters (clean break from library; see class docs)
    WebAuthCredentials, // v33 — web secure-login account
    WebAuthSessions, // v33 — persisted web-login sessions
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._internal(super.e);

  static AppDatabase? _instance;
  static String? _dbPath;
  static String? _dbDir;

  /// Singleton access. Call [AppDatabase.instance()] to get the shared database.
  ///
  /// Pre-release builds (alpha/beta/rc/dev) automatically use a separate
  /// `front_porch_beta.db` to protect the production database from schema
  /// changes that may be incompatible with the stable release.
  static Future<AppDatabase> instance() async {
    if (_instance != null) return _instance!;
    final prefs = await SharedPreferences.getInstance();
    // Mirror StorageService: use a separate prefs key for beta builds so the
    // beta DB path never overwrites the stable user's custom root path.
    final rootPathKey = isPreRelease ? 'root_path_beta' : 'root_path';
    final rootPath = prefs.getString(rootPathKey);
    final defaultRootName = isPreRelease ? 'FrontPorchAI-Beta' : 'FrontPorchAI';
    final basePath =
        rootPath ??
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          defaultRootName,
        );
    final dbDir = p.join(basePath, 'KoboldManager');
    _dbDir = dbDir;

    // Choose database filename based on release type
    final dbName = isPreRelease ? 'front_porch_beta.db' : 'front_porch.db';
    final file = File(p.join(dbDir, dbName));
    await file.parent.create(recursive: true);

    // For pre-release: if no beta DB exists yet, copy the production DB
    // so users get all their data without modifying the stable database.
    // The copy is gated by the import dialog — it only happens after the
    // user has seen the dialog and chosen Import (or skipped the dialog
    // entirely for non-pre-release builds).
    if (isPreRelease && !file.existsSync()) {
      final prefs = await SharedPreferences.getInstance();
      final shown = prefs.getBool('beta_stable_import_shown') ?? false;
      if (shown) {
        // Dialog has been shown — respect the user's choice
        final skipped = prefs.getBool('beta_stable_import_skipped') ?? false;
        if (!skipped) {
          final prodFile = File(p.join(dbDir, 'front_porch.db'));
          if (prodFile.existsSync()) {
            debugPrint(
              '[DB] Pre-release build — copying production DB to beta DB',
            );
            await prodFile.copy(file.path);
          }
        }
      } else {
        // Dialog not yet shown — defer to the import dialog which will
        // show after the first frame and trigger the copy manually.
        debugPrint(
          '[DB] Pre-release build — import dialog pending, skipping copy',
        );
      }
    }

    // For stable builds: reunify beta DB into production if both exist.
    // This is a one-time operation on the first 0.9.0 stable launch.
    // Steps 1-2 run here (backup + promote). Steps 3-5 (diff + import)
    // run later in main.dart with a UI overlay.
    if (!isPreRelease &&
        await DbReunificationService.needsReunification(dbDir)) {
      debugPrint(
        '[DB] Reunification needed — backing up and promoting beta DB',
      );
      await DbReunificationService.createBackups(dbDir);
      await DbReunificationService.promoteBetaDb(dbDir);
    }

    _dbPath = file.path;
    _instance = AppDatabase._internal(
      NativeDatabase.createInBackground(
        file,
        setup: (db) {
          db.execute('PRAGMA synchronous = FULL');
          debugPrint('[DB] PRAGMA synchronous = FULL set');
        },
      ),
    );

    // Robust, always-on schema repair for long-lived user databases.
    // Any previous schemaVersion onUpgrade block that used bare `try { ALTER } catch (_) {}`
    // could leave the physical DB permanently behind the Dart Table definitions (e.g. the
    // v29 `chat_id` on objectives, or v30-v32 group columns). This repair uses PRAGMA
    // table_info introspection + conditional ADD COLUMN only. It creates a timestamped
    // .db backup the first time it actually mutates schema, then guarantees the columns
    // the rest of the app (group chat, per-character objectives, Realism/Needs, Chaos)
    // now unconditionally reference. Never deletes or mutates user rows. Safe and cheap
    // to run on every normal launch.
    await _instance!._repairMissingSchemaColumns();

    return _instance!;
  }

  /// The absolute path to the database file on disk.
  static String? get dbFilePath => _dbPath;

  /// The directory containing the database files.
  static String? get dbDirPath => _dbDir;

  /// Flush WAL (Write-Ahead Log) to the main database file.
  /// Call this before uploading the .db file to ensure it's self-contained.
  Future<void> checkpoint() async {
    await customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
  }

  /// Run a fast integrity check on the database.
  /// Returns `true` if the database is healthy, `false` if corruption is detected.
  Future<bool> integrityCheck() async {
    try {
      final result = await customSelect('PRAGMA quick_check').get();
      if (result.isNotEmpty && result.first.data.values.first == 'ok') {
        debugPrint('[DB] Integrity check passed');
        return true;
      }
      debugPrint(
        '[DB] Integrity check FAILED: ${result.map((r) => r.data).toList()}',
      );
      return false;
    } catch (e) {
      debugPrint('[DB] Integrity check error: $e');
      return false;
    }
  }

  /// Ensures all columns that the current Dart schema and application code expect
  /// are physically present in the database. This is the robust, always-on safety
  /// net for users whose databases predate recent features (group cards, per-character
  /// objectives, expanded Realism/Needs/Chaos columns). It replaces the fragile
  /// pattern of silent `try { ALTER ... } catch (_) {}` inside versioned migration blocks.
  ///
  /// Strategy:
  /// - Uses PRAGMA table_info (fast, reliable even on ancient SQLite files).
  /// - Only ever does ADD COLUMN with exact NOT NULL DEFAULTs that match the Table
  ///   class definitions and the historical ALTER statements.
  /// - On first actual mutation for a given launch, creates a timestamped backup of
  ///   the .db file next to the original so users with years of chats have an
  ///   immediate rollback artifact.
  /// - Failures to add a single column are logged but do not prevent app launch.
  /// - Idempotent and safe to call on every open (including after cloud sync restore).
  ///
  /// This must be kept in sync with any future columns added to Sessions, Groups,
  /// Objectives, Characters, etc. Add the new "COL TYPE [NOT NULL DEFAULT x]" entry
  /// here in the same change that adds it to the Table class.
  Future<void> _repairMissingSchemaColumns() async {
    final stopwatch = Stopwatch()..start();
    bool anyRepairDone = false;

    // Physical table -> list of "col_name TYPE [NOT NULL DEFAULT 'lit']" fragments.
    // These are exactly the columns that were added (or re-added) via the old
    // silent-catch ALTERs in onUpgrade for schema versions 9 through 32.
    // The presence of these in the list is what guarantees 1:1 + group chat parity
    // features will not produce "no such column" on real user databases.
    const Map<String, List<String>> columnsToEnsure = {
      'objectives': [
        'chat_id TEXT', // v29 — the one that was actively crashing group objective loads
        'is_primary INTEGER NOT NULL DEFAULT 1', // v20
        'injection_depth INTEGER NOT NULL DEFAULT 4', // safety (was in v8 CREATE + v9 ALTER)
      ],
      'groups': [
        // v30
        'default_member_realism_state TEXT NOT NULL DEFAULT "{}"',
        // v31 — the full set of explicit typed columns for Group Card roundtrip + Chaos + lore scoping
        'chaos_mode_enabled INTEGER NOT NULL DEFAULT 0',
        'chaos_nsfw_enabled INTEGER NOT NULL DEFAULT 0',
        "group_lorebook TEXT NOT NULL DEFAULT ''",
        "world_ids TEXT NOT NULL DEFAULT '[]'",
        'inherit_character_lorebooks INTEGER NOT NULL DEFAULT 1',
        'baseline_realism_state TEXT NOT NULL DEFAULT "{}"',
        // v32 — final deprecation of the last blob hack
        'character_system_prompts TEXT NOT NULL DEFAULT "{}"',
      ],
      'sessions': [
        // v30 — the live per-group-member realism state (clean replacement for hidden checkpoint msgs)
        'group_realism_state TEXT NOT NULL DEFAULT "{}"',
        // Additional columns added with the same fragile pattern that group/per-char
        // Realism, Needs, Chaos, and evolution paths now depend on unconditionally.
        'group_evolved_personalities TEXT NOT NULL DEFAULT "{}"',
        'group_evolved_scenarios TEXT NOT NULL DEFAULT "{}"',
        'needs_sim_enabled INTEGER NOT NULL DEFAULT 0',
        'needs_vector TEXT',
        'start_day_of_week INTEGER NOT NULL DEFAULT 0',
        'chaos_mode_enabled INTEGER NOT NULL DEFAULT 0',
        'chaos_pressure INTEGER NOT NULL DEFAULT 0',
        'generation_settings TEXT',
        'user_persona_id TEXT',
        'passage_of_time_enabled INTEGER NOT NULL DEFAULT 1',
        'nsfw_cooldown_enabled INTEGER NOT NULL DEFAULT 0',
        'cooldown_turns_remaining INTEGER NOT NULL DEFAULT 0',
        'cooldown_turns_total INTEGER NOT NULL DEFAULT 0',
      ],
      'group_members': [
        // Per current GroupMembers Dart definition + created_at (to match the repair-path CREATE TABLE).
        // This gives the PRAGMA+ALTER+backup guard for any future columns added to the table
        // (addresses the previous limitation where only IF NOT EXISTS creation was used).
        'group_id TEXT NOT NULL',
        'name TEXT NOT NULL',
        "description TEXT NOT NULL DEFAULT ''",
        "personality TEXT NOT NULL DEFAULT ''",
        "scenario TEXT NOT NULL DEFAULT ''",
        "first_message TEXT NOT NULL DEFAULT ''",
        "mes_example TEXT NOT NULL DEFAULT ''",
        "system_prompt TEXT NOT NULL DEFAULT ''",
        "post_history_instructions TEXT NOT NULL DEFAULT ''",
        "alternate_greetings TEXT NOT NULL DEFAULT '[]'",
        "tags TEXT NOT NULL DEFAULT '[]'",
        'avatar_filename TEXT',
        'tts_voice TEXT',
        'lorebook TEXT',
        "world_names TEXT NOT NULL DEFAULT '[]'",
        'front_porch_extensions TEXT',
        'raw_extensions TEXT',
        "member_state TEXT NOT NULL DEFAULT '{}'",
        'updated_at INTEGER NOT NULL DEFAULT 0',
        'created_at INTEGER NOT NULL DEFAULT 0',
      ],
    };

    for (final entry in columnsToEnsure.entries) {
      final table = entry.key;
      final expectedDefs = entry.value;

      final existing = await _getExistingColumnNames(table);
      if (existing.isEmpty) {
        // Table does not exist in this DB yet. A future onCreate or onUpgrade CREATE
        // TABLE will bring it in with the full modern definition. Nothing to repair.
        continue;
      }

      final missingDefs = <String>[];
      for (final def in expectedDefs) {
        final colName = def.split(' ').first;
        if (!existing.contains(colName)) {
          missingDefs.add(def);
        }
      }

      if (missingDefs.isNotEmpty) {
        if (!anyRepairDone) {
          await _createPreRepairBackup();
          anyRepairDone = true;
        }

        for (final def in missingDefs) {
          final colName = def.split(' ').first;
          try {
            final sql = 'ALTER TABLE $table ADD COLUMN $def';
            await customStatement(sql);
            debugPrint(
              '[DB] Schema repair: added $table.$colName (recovered from incomplete past migration)',
            );
          } catch (e) {
            debugPrint(
              '[DB] Schema repair: FAILED to add $table.$colName — $e (app will continue; some features may be limited until manual intervention)',
            );
            // Intentionally not re-thrown. The user's irreplaceable chats must remain accessible.
          }
        }
      }
    }

    stopwatch.stop();
    if (anyRepairDone) {
      debugPrint(
        '[DB] Schema repair completed in ${stopwatch.elapsedMilliseconds}ms — your database is now consistent with app v32+ expectations',
      );
    }

    // ── New table for decoupled group members (clean break, no legacy, no blobs) ──
    // This table + private per-group avatar files (groups/<groupId>/avatars/*.png)
    // replace all previous characterIds + library materialization for groups.
    // Created with IF NOT EXISTS + the backup-on-mutation guard for users on old DBs.
    // Matches the GroupMembers Dart definition (snake_case) + created_at (repair path).
    // Multi-avatar never supported here; only primary avatarFilename per member.
    try {
      final hasMembersTable = await customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='group_members'",
      ).get();
      if (hasMembersTable.isEmpty) {
        if (!anyRepairDone) {
          await _createPreRepairBackup();
          anyRepairDone = true;
        }
        // External direct-SQL writers (e.g. Character Card Forge): see GroupMembers
        // Dart class docs above for v33+ contract. Do not assume legacy characterIds behavior here.
        // TODO: After this stabilizes in a tagged release, notify maintainers of external direct-SQL tools (Character Card Forge) about the new group_members table and its private-avatar contract.
        await customStatement('''
          CREATE TABLE IF NOT EXISTS group_members (
            -- v33+ table (GroupMembers Dart docs): strict UUID PKs + private-avatar semantics only. No legacy characterIds.
            id TEXT NOT NULL PRIMARY KEY,
            group_id TEXT NOT NULL,
            name TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            personality TEXT NOT NULL DEFAULT '',
            scenario TEXT NOT NULL DEFAULT '',
            first_message TEXT NOT NULL DEFAULT '',
            mes_example TEXT NOT NULL DEFAULT '',
            system_prompt TEXT NOT NULL DEFAULT '',
            post_history_instructions TEXT NOT NULL DEFAULT '',
            alternate_greetings TEXT NOT NULL DEFAULT '[]',
            tags TEXT NOT NULL DEFAULT '[]',
            avatar_filename TEXT,
            tts_voice TEXT,
            lorebook TEXT,
            world_names TEXT NOT NULL DEFAULT '[]',
            front_porch_extensions TEXT,
            raw_extensions TEXT,
            member_state TEXT NOT NULL DEFAULT '{}',
            created_at INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL DEFAULT 0
          )
        ''');
        debugPrint(
          '[DB] Schema repair: created group_members table (decoupled group characters; v33+ contract)',
        );
      }
    } catch (e) {
      debugPrint(
        '[DB] Schema repair: FAILED to ensure group_members table — $e (continuing; groups may be limited)',
      );
    }

    // Post-creation lightweight orphan diagnostic (one query, non-fatal, launch-time only).
    try {
      final res = await customSelect(
        'SELECT COUNT(*) as cnt FROM group_members gm LEFT JOIN groups g ON gm.group_id = g.id WHERE g.id IS NULL',
      ).get();
      final cnt = res.isNotEmpty ? (res.first.data['cnt'] as int? ?? 0) : 0;
      if (cnt > 0) {
        debugPrint(
          '[DB] WARNING: $cnt orphaned group_members row(s) with no matching group (pre-v33 DB integrity issue)',
        );
      }
    } catch (_) {}

    if (anyRepairDone) {
      // Re-log if we did table creation after the column phase
      debugPrint(
        '[DB] Schema repair (including new tables) completed in ${stopwatch.elapsedMilliseconds}ms total',
      );
    }
  }

  /// Introspects the live physical columns using the SQLite PRAGMA that works
  /// even when Drift's internal schema snapshot is ahead of the on-disk reality.
  Future<Set<String>> _getExistingColumnNames(String tableName) async {
    try {
      final result = await customSelect('PRAGMA table_info($tableName)').get();
      return result
          .map((row) => row.data['name'] as String?)
          .where((name) => name != null && name.isNotEmpty)
          .cast<String>()
          .toSet();
    } catch (e) {
      debugPrint(
        '[DB] Could not PRAGMA table_info for $tableName (table may be very old or locked): $e',
      );
      return <String>{};
    }
  }

  /// Creates a byte-for-byte copy of the current .db file with a timestamped suffix
  /// the first time this launch is about to perform any ALTER. This is the belt-and-
  /// suspenders protection for users who have explicitly stated that DB deletion or
  /// any risk of losing character chat history is unacceptable.
  Future<void> _createPreRepairBackup() async {
    try {
      final path = dbFilePath;
      if (path == null) return;
      final dbFile = File(path);
      if (!await dbFile.exists()) return;

      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backupPath = '$path.pre-schema-repair-$ts';
      await dbFile.copy(backupPath);
      debugPrint(
        '[DB] SAFETY BACKUP created before schema repair: $backupPath',
      );
      debugPrint(
        '[DB] If anything ever goes wrong, you can rename this file back to front_porch.db to restore your exact previous state (all chats, objectives, groups, etc.).',
      );
    } catch (e) {
      debugPrint(
        '[DB] Could not create pre-repair backup (non-fatal — repair will still attempt): $e',
      );
    }
  }

  /// Public helper so that direct-open paths (reunification, certain test or recovery
  /// scenarios) can explicitly ensure the schema matches before using group or objective
  /// features. The primary AppDatabase.instance() path calls the repair automatically.
  Future<void> ensureSchemaIsRepaired() => _repairMissingSchemaColumns();

  /// Close the database and clear the singleton so the next call to
  /// [instance()] will open a fresh connection to the file on disk.
  /// Used after cloud sync downloads a new .db file.
  static Future<void> closeAndReset() async {
    if (_instance != null) {
      await _instance!.close();
      _instance = null;
    }
  }

  /// For testing: create a temporary database backed by a real file.
  /// Uses a system temp directory so the background isolate can access it.
  factory AppDatabase.forTesting() {
    final tmpDir = Directory.systemTemp.createTempSync('fpai_test_');
    final file = File('${tmpDir.path}/test.db');
    return AppDatabase._internal(
      NativeDatabase.createInBackground(
        file,
        setup: (db) => db.execute('PRAGMA synchronous = FULL'),
      ),
    );
  }

  /// Open a specific DB file for reunification (runs migrations, not a singleton).
  factory AppDatabase.forReunification(File file) {
    return AppDatabase._internal(
      NativeDatabase.createInBackground(
        file,
        setup: (db) => db.execute('PRAGMA synchronous = FULL'),
      ),
    );
  }

  @override
  int get schemaVersion => 33;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      // Seed the sync_meta row on fresh installs
      await customInsert(
        'INSERT OR IGNORE INTO sync_meta (id, version, last_modified_at) '
        'VALUES (1, 0, ?)',
        variables: [Variable(DateTime.now().millisecondsSinceEpoch ~/ 1000)],
      );
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        // v1→v2: create sync_meta table
        await customStatement(
          'CREATE TABLE IF NOT EXISTS sync_meta ('
          'id INTEGER NOT NULL DEFAULT 1, '
          'version INTEGER NOT NULL DEFAULT 0, '
          'last_modified_at INTEGER NOT NULL DEFAULT 0, '
          'PRIMARY KEY (id))',
        );
        await customInsert(
          'INSERT OR IGNORE INTO sync_meta (id, version, last_modified_at) '
          'VALUES (1, 0, ?)',
          variables: [Variable(DateTime.now().millisecondsSinceEpoch ~/ 1000)],
        );
      }
      if (from < 3) {
        // v2→v3: migrate int PKs to text UUIDs, add updatedAt/deletedAt
        await _migrateToUuids();
      }
      if (from < 4) {
        // v3→v4: add summary columns to sessions
        await customStatement('ALTER TABLE sessions ADD COLUMN summary TEXT');
        await customStatement(
          'ALTER TABLE sessions ADD COLUMN summary_last_index INTEGER',
        );
      }
      if (from < 5) {
        // v4→v5: add message_embeddings table for RAG + memorySources on characters
        await customStatement(
          'CREATE TABLE IF NOT EXISTS message_embeddings ('
          'id TEXT NOT NULL, '
          'session_id TEXT NOT NULL, '
          'character_id TEXT, '
          'position_start INTEGER NOT NULL, '
          'position_end INTEGER NOT NULL, '
          'content TEXT NOT NULL, '
          'embedding BLOB NOT NULL, '
          'dimensions INTEGER NOT NULL, '
          'created_at INTEGER NOT NULL DEFAULT 0, '
          'PRIMARY KEY (id))',
        );
        // Add memorySources column to characters for cross-character RAG
        try {
          await customStatement(
            "ALTER TABLE characters ADD COLUMN memory_sources TEXT NOT NULL DEFAULT '[]'",
          );
        } catch (_) {
          // Column may already exist
        }
      }
      if (from < 6) {
        // v5→v6: add learnedFacts column to personas for auto-persona
        try {
          await customStatement(
            "ALTER TABLE personas ADD COLUMN learned_facts TEXT NOT NULL DEFAULT '[]'",
          );
        } catch (_) {
          // Column may already exist
        }
      }
      if (from < 7) {
        // v6→v7: add data_bank_entries table for knowledge base
        await customStatement(
          'CREATE TABLE IF NOT EXISTS data_bank_entries ('
          'id TEXT NOT NULL, '
          'character_id TEXT NOT NULL, '
          'title TEXT NOT NULL, '
          'content TEXT NOT NULL, '
          'embedding BLOB, '
          'dimensions INTEGER NOT NULL DEFAULT 0, '
          'created_at INTEGER NOT NULL DEFAULT 0, '
          'PRIMARY KEY (id))',
        );
      }
      if (from < 8) {
        // v7→v8: add objectives table for quest/task system
        await customStatement(
          'CREATE TABLE IF NOT EXISTS objectives ('
          'id TEXT NOT NULL, '
          'character_id TEXT NOT NULL, '
          'objective TEXT NOT NULL, '
          'tasks TEXT NOT NULL DEFAULT \'[]\', '
          'active INTEGER NOT NULL DEFAULT 1, '
          'check_frequency INTEGER NOT NULL DEFAULT 3, '
          'injection_depth INTEGER NOT NULL DEFAULT 4, '
          'created_at INTEGER NOT NULL DEFAULT 0, '
          'PRIMARY KEY (id))',
        );
      }
      if (from < 9) {
        // v8→v9: add injection_depth column to objectives
        try {
          await customStatement(
            "ALTER TABLE objectives ADD COLUMN injection_depth INTEGER NOT NULL DEFAULT 4",
          );
        } catch (_) {
          // Column may already exist (fresh v8+ installs)
        }
      }
      if (from < 10) {
        // v9→v10: add character evolution columns
        try {
          await customStatement(
            "ALTER TABLE characters ADD COLUMN evolved_personality TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE characters ADD COLUMN evolved_scenario TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE characters ADD COLUMN evolution_count INTEGER NOT NULL DEFAULT 0",
          );
        } catch (_) {}
      }
      if (from < 11) {
        // v10→v11: add story_projects table for Porch Stories
        await customStatement(
          'CREATE TABLE IF NOT EXISTS story_projects ('
          'id TEXT NOT NULL, '
          'title TEXT NOT NULL DEFAULT \'Untitled Story\', '
          'data TEXT NOT NULL, '
          'created_at INTEGER NOT NULL DEFAULT 0, '
          'updated_at INTEGER NOT NULL DEFAULT 0, '
          'deleted_at INTEGER, '
          'PRIMARY KEY (id))',
        );
      }
      if (from < 12) {
        // v11→v12: add relationship tracker columns to sessions
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN affection_score INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN relationship_tier INTEGER NOT NULL DEFAULT 2',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN relationship_enabled INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
      }
      if (from < 13) {
        // v12→v13: Realism Mode — rename relationship_enabled → realism_enabled, add new columns
        // Rename: SQLite doesn't support RENAME COLUMN on older versions, so we add the new col
        // and copy data if the old one exists.
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN realism_enabled INTEGER NOT NULL DEFAULT 0',
          );
          // Copy existing relationship_enabled values to realism_enabled
          await customStatement(
            'UPDATE sessions SET realism_enabled = relationship_enabled',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN short_term_mood INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN mood_decay_counter INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN character_emotion TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN emotion_intensity TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN time_of_day TEXT NOT NULL DEFAULT 'morning'",
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN day_count INTEGER NOT NULL DEFAULT 1',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN nsfw_cooldown_enabled INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN cooldown_turns_remaining INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
      }
      if (from < 14) {
        // v13→v14: add metadata columns to messages
        try {
          await customStatement(
            'ALTER TABLE messages ADD COLUMN metadata TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE messages ADD COLUMN swipe_metadata TEXT',
          );
        } catch (_) {}
      }
      if (from < 15) {
        // v14→v15: add arousal tracker to sessions
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN arousal_level INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
      }
      if (from < 16) {
        // v15→v16: add long term relationship tracking fields
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN long_term_score INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN long_term_tier INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN turns_since_long_term_check INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN short_term_deltas_summary INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
      }
      if (from < 17) {
        // v16→v17: add behavioral Realism Mechanics
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN trust_level INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN active_fixation TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN fixation_lifespan INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN spatial_stance TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
      }
      if (from < 18) {
        // v17→v18: add trust repair window flag
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN trust_repair_pending INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
      }
      if (from < 19) {
        // v18→v19: per-session character evolution columns
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN evolved_personality TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN evolved_scenario TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN evolution_count INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN group_evolved_personalities TEXT NOT NULL DEFAULT '{}'",
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE sessions ADD COLUMN group_evolved_scenarios TEXT NOT NULL DEFAULT '{}'",
          );
        } catch (_) {}
        // Data preservation: copy existing character-level evolved data into
        // all their matching (non-deleted) session rows so no user data is lost.
        try {
          final evolvedChars = await customSelect(
            "SELECT id, evolved_personality, evolved_scenario, evolution_count "
            "FROM characters "
            "WHERE (evolved_personality != '' OR evolved_scenario != '') "
            "AND deleted_at IS NULL",
          ).get();
          for (final row in evolvedChars) {
            final charId = row.read<String>('id');
            final ep = row.read<String>('evolved_personality');
            final es = row.read<String>('evolved_scenario');
            final ec = row.read<int>('evolution_count');
            await customUpdate(
              'UPDATE sessions SET evolved_personality = ?, evolved_scenario = ?, evolution_count = ? '
              'WHERE character_id = ? AND deleted_at IS NULL',
              variables: [
                Variable(ep),
                Variable(es),
                Variable(ec),
                Variable(charId),
              ],
              updates: {sessions},
            );
            debugPrint(
              '[DB] v19 migration: copied evolution data for character $charId to their sessions',
            );
          }
        } catch (e) {
          debugPrint('[DB] v19 migration: data copy failed (non-fatal): $e');
        }
      }
      if (from < 20) {
        // v19→v20: multi-objective support (primary vs secondary goals)
        try {
          // Defaulting to 1 so any previously active goal becomes the primary goal
          await customStatement(
            'ALTER TABLE objectives ADD COLUMN is_primary INTEGER NOT NULL DEFAULT 1',
          );
        } catch (_) {}
      }
      if (from < 21) {
        // v20→v21: Chaos Mode / Chance Time system
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN chaos_mode_enabled INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN chaos_pressure INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
      }
      if (from < 22) {
        // v21→v22: per-session generation parameter overrides
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN generation_settings TEXT',
          );
        } catch (_) {}
      }
      if (from < 23) {
        // v22->v23: add passage_of_time_enabled sub-toggle for realism mode
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN passage_of_time_enabled INTEGER NOT NULL DEFAULT 1',
          );
        } catch (_) {}
      }
      if (from < 24) {
        // v23->v24: add primeAvatarIndex to characters and avatar_images table
        try {
          await customStatement(
            "ALTER TABLE characters ADD COLUMN prime_avatar_index INTEGER NOT NULL DEFAULT 1",
          );
        } catch (_) {}
        await customStatement(
          'CREATE TABLE IF NOT EXISTS avatar_images ('
          'id TEXT NOT NULL, '
          'character_id TEXT NOT NULL, '
          'filename TEXT NOT NULL, '
          'label TEXT, '
          'display_order INTEGER NOT NULL DEFAULT 0, '
          'created_at INTEGER NOT NULL DEFAULT 0, '
          'PRIMARY KEY (id))',
        );
      }
      if (from < 25) {
        // v24->v25: add userPersonaId to sessions
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN user_persona_id TEXT',
          );
        } catch (_) {}
      }
      if (from < 26) {
        // v25->v26: consolidate persona fields — merge description into persona, drop description
        // For rows where persona is empty but description has content → copy description to persona
        // For rows where both have content → keep persona (it's the full text)
        try {
          await customStatement(
            "UPDATE personas SET persona = COALESCE(NULLIF(persona, ''), description) WHERE description != ''",
          );
          await customStatement('ALTER TABLE personas DROP COLUMN description');
        } catch (_) {}
      }
      if (from < 27) {
        // v26->v27: add per-session needs simulation (flag + vector)
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN needs_sim_enabled INTEGER NOT NULL DEFAULT 0',
          );
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN needs_vector TEXT',
          );
        } catch (_) {}
      }
      if (from < 28) {
        // v27->v28: persist narrative weekday anchor (startDayOfWeek) so Day N always maps to the same weekday across app restarts
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN start_day_of_week INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
      }
      if (from < 29) {
        // v28→v29: scope objectives to chat sessions (fix bleeding between chats)
        try {
          await customStatement(
            'ALTER TABLE objectives ADD COLUMN chat_id TEXT',
          );
        } catch (_) {}
      }
      if (from < 30) {
        // v29→v30: Proper DB-backed group realism/needs storage (clean break — no support
        // for old hidden __group_state__ checkpoint messages). Added with explicit dev
        // authorization. External direct-SQL tools will need to adapt.
        try {
          await customStatement(
            'ALTER TABLE groups ADD COLUMN default_member_realism_state TEXT NOT NULL DEFAULT "{}"',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE sessions ADD COLUMN group_realism_state TEXT NOT NULL DEFAULT "{}"',
          );
        } catch (_) {}
      }
      if (from < 31) {
        // v30→v31: Group configuration columns for Chaos Mode toggles (including NSFW
        // variant), group-scoped lorebook + world selection/inheritance, and an immutable
        // creation-time baseline realism seed (separate from the mutable default member
        // state added in v30). Stored as clean dedicated columns (INTEGER for Bool, TEXT
        // for JSON strings) rather than inside a single JSON blob or piggy-backing on
        // character_ids / scenario etc. Follows v30 precedent of explicit columns over
        // hidden/magic storage for group concerns — improves Drift queries, self-documents
        // the schema for maintainers, and makes the contract obvious for external
        // direct-SQL writers. Purpose: enable precise group-level Chaos + lore scoping +
        // creation-seed baselines for Group Cards and new sessions. Added with explicit
        // dev authorization. External direct-SQL tools will need to adapt (provide values
        // or rely on the NOT NULL DEFAULTs documented here when writing to the groups table).
        try {
          await customStatement(
            'ALTER TABLE groups ADD COLUMN chaos_mode_enabled INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE groups ADD COLUMN chaos_nsfw_enabled INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE groups ADD COLUMN group_lorebook TEXT NOT NULL DEFAULT ''",
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE groups ADD COLUMN world_ids TEXT NOT NULL DEFAULT '[]'",
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE groups ADD COLUMN inherit_character_lorebooks INTEGER NOT NULL DEFAULT 1',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE groups ADD COLUMN baseline_realism_state TEXT NOT NULL DEFAULT "{}"',
          );
        } catch (_) {}
      }

      if (from < 32) {
        // v31→v32: Final cleanup of the last "Path B" transitional JSON blob hack.
        // Per-character system prompts (group-scoped overrides) now have their own
        // first-class TEXT column instead of being merged into defaultMemberRealismState.
        // This completes the move to explicit columns for all group-level configuration
        // (following the v30 and v31 philosophy). All extraction/promotion logic that
        // previously read/wrote 'character_system_prompts' inside the realism blob has
        // been fully removed. Old data in the blob is ignored on load going forward.
        // External direct-SQL tools must now use the new column.
        try {
          await customStatement(
            'ALTER TABLE groups ADD COLUMN character_system_prompts TEXT NOT NULL DEFAULT "{}"',
          );
        } catch (_) {}
      }
      if (from < 33) {
        // v32→v33: web secure-login tables for the rewritten web server.
        // Replaces the old plaintext web-server PIN with username + Argon2id
        // password + optional TOTP, and persists per-device sessions (so they
        // survive app restart). Both are NEW tables — additive and outside the
        // Character Card Forge external-writer set, so this cannot break it.
        await customStatement('''
          CREATE TABLE IF NOT EXISTS web_auth_credentials (
            id TEXT NOT NULL PRIMARY KEY,
            username TEXT NOT NULL,
            password_hash TEXT NOT NULL,
            totp_secret TEXT,
            totp_enabled INTEGER NOT NULL DEFAULT 0,
            recovery_codes TEXT,
            created_at INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await customStatement('''
          CREATE TABLE IF NOT EXISTS web_auth_sessions (
            id TEXT NOT NULL PRIMARY KEY,
            token_hash TEXT NOT NULL,
            user_id TEXT NOT NULL,
            created_at INTEGER NOT NULL DEFAULT 0,
            last_seen_at INTEGER NOT NULL DEFAULT 0,
            expires_at INTEGER NOT NULL DEFAULT 0,
            user_agent TEXT,
            ip TEXT,
            revoked INTEGER NOT NULL DEFAULT 0
          )
        ''');
      }
    },
  );

  /// Migrate all int-keyed tables to UUID text PKs.
  /// Creates new tables, copies data with generated UUIDs, drops old, renames.
  Future<void> _migrateToUuids() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // ── Folders ──────────────────────────────────────────────────
    await customStatement(
      'CREATE TABLE folders_new ('
      'id TEXT NOT NULL, name TEXT NOT NULL, parent_id TEXT, '
      'updated_at INTEGER NOT NULL DEFAULT $now, '
      'deleted_at INTEGER, PRIMARY KEY (id))',
    );
    // Build oldId→uuid map
    final oldFolders = await customSelect(
      'SELECT id, name, parent_id FROM folders',
    ).get();
    final folderIdMap = <int, String>{}; // old int → new uuid
    for (final row in oldFolders) {
      final oldId = row.read<int>('id');
      folderIdMap[oldId] = _uuid.v4();
    }
    for (final row in oldFolders) {
      final oldId = row.read<int>('id');
      final newId = folderIdMap[oldId]!;
      final oldParent = row.readNullable<int>('parent_id');
      final newParent = oldParent != null ? folderIdMap[oldParent] : null;
      await customInsert(
        'INSERT INTO folders_new (id, name, parent_id, updated_at) VALUES (?, ?, ?, ?)',
        variables: [
          Variable(newId),
          Variable(row.read<String>('name')),
          Variable(newParent),
          Variable(now),
        ],
      );
    }
    await customStatement('DROP TABLE folders');
    await customStatement('ALTER TABLE folders_new RENAME TO folders');

    // ── Characters ───────────────────────────────────────────────
    await customStatement(
      'CREATE TABLE characters_new ('
      'id TEXT NOT NULL, name TEXT NOT NULL, '
      'description TEXT NOT NULL DEFAULT \'\', personality TEXT NOT NULL DEFAULT \'\', '
      'scenario TEXT NOT NULL DEFAULT \'\', first_message TEXT NOT NULL DEFAULT \'\', '
      'mes_example TEXT NOT NULL DEFAULT \'\', system_prompt TEXT NOT NULL DEFAULT \'\', '
      'post_history_instructions TEXT NOT NULL DEFAULT \'\', '
      'alternate_greetings TEXT NOT NULL DEFAULT \'[]\', '
      'tags TEXT NOT NULL DEFAULT \'[]\', '
      'image_path TEXT, tts_voice TEXT, folder_id TEXT, '
      'lorebook TEXT, world_names TEXT NOT NULL DEFAULT \'[]\', '
      'created_at INTEGER NOT NULL DEFAULT $now, '
      'updated_at INTEGER NOT NULL DEFAULT $now, '
      'deleted_at INTEGER, PRIMARY KEY (id))',
    );
    final oldChars = await customSelect('SELECT * FROM characters').get();
    final charIdMap = <int, String>{}; // old int → new uuid
    for (final row in oldChars) {
      final oldId = row.read<int>('id');
      charIdMap[oldId] = _uuid.v4();
    }
    for (final row in oldChars) {
      final oldId = row.read<int>('id');
      final newId = charIdMap[oldId]!;
      final oldFolderId = row.readNullable<int>('folder_id');
      final newFolderId = oldFolderId != null ? folderIdMap[oldFolderId] : null;
      await customInsert(
        'INSERT INTO characters_new (id, name, description, personality, scenario, '
        'first_message, mes_example, system_prompt, post_history_instructions, '
        'alternate_greetings, tags, image_path, tts_voice, folder_id, '
        'lorebook, world_names, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable(newId),
          Variable(row.read<String>('name')),
          Variable(row.read<String>('description')),
          Variable(row.read<String>('personality')),
          Variable(row.read<String>('scenario')),
          Variable(row.read<String>('first_message')),
          Variable(row.read<String>('mes_example')),
          Variable(row.read<String>('system_prompt')),
          Variable(row.read<String>('post_history_instructions')),
          Variable(row.read<String>('alternate_greetings')),
          Variable(row.read<String>('tags')),
          Variable(row.readNullable<String>('image_path')),
          Variable(row.readNullable<String>('tts_voice')),
          Variable(newFolderId),
          Variable(row.readNullable<String>('lorebook')),
          Variable(row.read<String>('world_names')),
          Variable(row.read<int>('created_at')),
          Variable(row.read<int>('updated_at')),
        ],
      );
    }
    await customStatement('DROP TABLE characters');
    await customStatement('ALTER TABLE characters_new RENAME TO characters');

    // ── Sessions (already text PK, just remap characterId int→text, add deletedAt) ──
    await customStatement(
      'CREATE TABLE sessions_new ('
      'id TEXT NOT NULL, character_id TEXT, group_id TEXT, '
      'name TEXT, description TEXT, '
      'author_note TEXT NOT NULL DEFAULT \'\', '
      'author_note_depth INTEGER NOT NULL DEFAULT 4, '
      'parent_session TEXT, fork_index INTEGER, '
      'created_at INTEGER NOT NULL DEFAULT $now, '
      'updated_at INTEGER NOT NULL DEFAULT $now, '
      'deleted_at INTEGER, PRIMARY KEY (id))',
    );
    final oldSessions = await customSelect('SELECT * FROM sessions').get();
    for (final row in oldSessions) {
      final oldCharId = row.readNullable<int>('character_id');
      final newCharId = oldCharId != null ? charIdMap[oldCharId] : null;
      await customInsert(
        'INSERT INTO sessions_new (id, character_id, group_id, name, description, '
        'author_note, author_note_depth, parent_session, fork_index, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable(row.read<String>('id')),
          Variable(newCharId),
          Variable(row.readNullable<String>('group_id')),
          Variable(row.readNullable<String>('name')),
          Variable(row.readNullable<String>('description')),
          Variable(row.read<String>('author_note')),
          Variable(row.read<int>('author_note_depth')),
          Variable(row.readNullable<String>('parent_session')),
          Variable(row.readNullable<int>('fork_index')),
          Variable(row.read<int>('created_at')),
          Variable(row.read<int>('updated_at')),
        ],
      );
    }
    await customStatement('DROP TABLE sessions');
    await customStatement('ALTER TABLE sessions_new RENAME TO sessions');

    // ── Messages (int PK → text UUID, add updatedAt/deletedAt) ──
    await customStatement(
      'CREATE TABLE messages_new ('
      'id TEXT NOT NULL, session_id TEXT NOT NULL, '
      'position INTEGER NOT NULL, sender TEXT NOT NULL, '
      'is_user INTEGER NOT NULL, character_id TEXT, '
      'swipes TEXT NOT NULL DEFAULT \'[]\', '
      'swipe_index INTEGER NOT NULL DEFAULT 0, '
      'swipe_durations TEXT NOT NULL DEFAULT \'[]\', '
      'updated_at INTEGER NOT NULL DEFAULT $now, '
      'deleted_at INTEGER, PRIMARY KEY (id))',
    );
    final oldMsgs = await customSelect('SELECT * FROM messages').get();
    for (final row in oldMsgs) {
      await customInsert(
        'INSERT INTO messages_new (id, session_id, position, sender, is_user, '
        'character_id, swipes, swipe_index, swipe_durations, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable(_uuid.v4()), // generate UUID for each message
          Variable(row.read<String>('session_id')),
          Variable(row.read<int>('position')),
          Variable(row.read<String>('sender')),
          Variable(row.read<bool>('is_user') ? 1 : 0),
          Variable(row.readNullable<String>('character_id')),
          Variable(row.read<String>('swipes')),
          Variable(row.read<int>('swipe_index')),
          Variable(row.read<String>('swipe_durations')),
          Variable(now),
        ],
      );
    }
    await customStatement('DROP TABLE messages');
    await customStatement('ALTER TABLE messages_new RENAME TO messages');

    // ── Groups (already text PK, just add updatedAt/deletedAt) ──
    await customStatement(
      'ALTER TABLE groups ADD COLUMN updated_at INTEGER NOT NULL DEFAULT $now',
    );
    await customStatement('ALTER TABLE groups ADD COLUMN deleted_at INTEGER');

    // ── Personas (already text PK, just add updatedAt/deletedAt) ──
    await customStatement(
      'ALTER TABLE personas ADD COLUMN updated_at INTEGER NOT NULL DEFAULT $now',
    );
    await customStatement('ALTER TABLE personas ADD COLUMN deleted_at INTEGER');

    // ── Worlds (int PK → text UUID, add updatedAt/deletedAt) ──
    await customStatement(
      'CREATE TABLE worlds_new ('
      'id TEXT NOT NULL, name TEXT NOT NULL UNIQUE, '
      'description TEXT NOT NULL DEFAULT \'\', '
      'lorebook TEXT, linked_character_name TEXT, '
      'updated_at INTEGER NOT NULL DEFAULT $now, '
      'deleted_at INTEGER, PRIMARY KEY (id))',
    );
    final oldWorlds = await customSelect('SELECT * FROM worlds').get();
    for (final row in oldWorlds) {
      await customInsert(
        'INSERT INTO worlds_new (id, name, description, lorebook, linked_character_name, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        variables: [
          Variable(_uuid.v4()),
          Variable(row.read<String>('name')),
          Variable(row.read<String>('description')),
          Variable(row.readNullable<String>('lorebook')),
          Variable(row.readNullable<String>('linked_character_name')),
          Variable(now),
        ],
      );
    }
    await customStatement('DROP TABLE worlds');
    await customStatement('ALTER TABLE worlds_new RENAME TO worlds');
  }

  // ── Sync Meta Queries ────────────────────────────────────────────────

  /// Get the current sync version (0 if no row exists yet).
  Future<int> getSyncVersion() async {
    try {
      final rows = await customSelect(
        'SELECT version FROM sync_meta WHERE id = 1',
      ).get();
      return rows.isNotEmpty ? rows.first.read<int>('version') : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Increment the sync version counter. Call after every meaningful write.
  Future<void> bumpSyncVersion() async {
    await customUpdate(
      'UPDATE sync_meta SET version = version + 1, '
      'last_modified_at = ? WHERE id = 1',
      variables: [Variable(DateTime.now().millisecondsSinceEpoch ~/ 1000)],
      updates: {syncMeta},
    );
  }

  /// Hard-delete all soft-deleted rows from every table and VACUUM the database
  /// to reclaim disk space. Without this, deleted messages accumulate and bloat
  /// the DB (e.g. 59k deleted messages = 300+ MB of wasted space).
  ///
  /// [skipTables] — optional set of table names (lowercase, e.g. {'characters','groups'})
  ///                whose soft-deleted rows should be left behind. Used before cloud
  ///                sync so that recent character/group deletion flags survive long
  ///                enough for the DB file + merge to propagate them to other devices.
  Future<int> purgeDeletedRows({Set<String> skipTables = const {}}) async {
    int total = 0;
    for (final table in [
      'messages',
      'sessions',
      'characters',
      'groups',
      'folders',
      'personas',
      'worlds',
    ]) {
      if (skipTables.contains(table)) {
        debugPrint(
          '[DB] Skipping purge of soft-deleted rows in $table (deletion signal protection for cloud sync)',
        );
        continue;
      }
      final count = await customUpdate(
        'DELETE FROM $table WHERE deleted_at IS NOT NULL',
        updates: {},
      );
      if (count > 0) {
        debugPrint('[DB] Purged $count deleted rows from $table');
        total += count;
      }
    }
    if (total > 0) {
      debugPrint('[DB] Purged $total deleted rows total — running VACUUM');
      await customStatement('VACUUM');
      debugPrint('[DB] VACUUM complete');
    }
    return total;
  }

  // ── Character Queries ───────────────────────────────────────────────

  Future<List<Character>> getAllCharacters() =>
      (select(characters)..where((c) => c.deletedAt.isNull())).get();

  Stream<List<Character>> watchAllCharacters() =>
      (select(characters)..where((c) => c.deletedAt.isNull())).watch();

  Future<Character> getCharacterById(String id) =>
      (select(characters)..where((c) => c.id.equals(id))).getSingle();

  Future<Character?> getCharacterByImagePath(String path) =>
      (select(characters)
            ..where((c) => c.imagePath.equals(path) & c.deletedAt.isNull()))
          .getSingleOrNull();

  Future<int> insertCharacter(CharactersCompanion character) async {
    // Ensure UUID is set
    if (!character.id.present) {
      character = character.copyWith(id: Value(_uuid.v4()));
    }
    final result = await into(characters).insert(character);
    await bumpSyncVersion();
    return result;
  }

  /// Insert a character and return its UUID (convenience for callers that need the ID).
  Future<String> insertCharacterReturningId(
    CharactersCompanion character,
  ) async {
    final id = character.id.present ? character.id.value : _uuid.v4();
    character = character.copyWith(id: Value(id));
    await into(characters).insert(character);
    await bumpSyncVersion();
    return id;
  }

  Future<bool> updateCharacter(CharactersCompanion character) async {
    // IMPORTANT: Use .write() not .replace() — .replace() overwrites the entire
    // row, wiping any fields not explicitly set (Value.absent → null/default).
    // .write() only updates fields where Value.present is true.
    final rows = await (update(
      characters,
    )..where((c) => c.id.equals(character.id.value))).write(character);
    await bumpSyncVersion();
    return rows > 0;
  }

  /// Update ONLY the imagePath for a character (preserves all other data).
  Future<void> updateCharacterImagePath(String id, String newPath) async {
    await (update(characters)..where((c) => c.id.equals(id))).write(
      CharactersCompanion(imagePath: Value(newPath)),
    );
    await bumpSyncVersion();
  }

  Future<int> deleteCharacterById(String id) async {
    // Hard delete: also cascade to sessions and their messages
    final charSessions = await (select(
      sessions,
    )..where((s) => s.characterId.equals(id))).get();
    for (final s in charSessions) {
      await (delete(messages)..where((m) => m.sessionId.equals(s.id))).go();
    }
    await (delete(sessions)..where((s) => s.characterId.equals(id))).go();
    final count = await (delete(
      characters,
    )..where((c) => c.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  /// Soft-delete a character (sets deletedAt + updatedAt on the row) while
  /// performing the same hard cascade delete of its dependent sessions and
  /// messages. The soft-deleted row remains in the table (with the flag) so
  /// that cloud DB sync + DatabaseMergeService can propagate the deletion
  /// to other devices and prevent resurrection.
  ///
  /// This is the method that should be called from user-facing delete paths
  /// (repositories) when cloud sync is active. The hard `deleteCharacterById`
  /// is retained for internal purge/migration use.
  Future<int> softDeleteCharacterById(String id) async {
    // Hard cascade the child data (sessions + messages). These are not
    // independently surfaced in the UI and do not need soft-delete flags
    // for the character deletion propagation use case.
    final charSessions = await (select(
      sessions,
    )..where((s) => s.characterId.equals(id))).get();
    for (final s in charSessions) {
      await (delete(messages)..where((m) => m.sessionId.equals(s.id))).go();
    }
    await (delete(sessions)..where((s) => s.characterId.equals(id))).go();

    // Soft-delete the primary character row so the flag travels with the DB.
    final now = DateTime.now();
    final count = await (update(characters)..where((c) => c.id.equals(id)))
        .write(
          CharactersCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        );
    await bumpSyncVersion();
    return count;
  }

  // ── Avatar Queries ──────────────────────────────────────────────────

  /// Get all avatar images for a character.
  Future<List<AvatarImage>> getAvatarImagesByCharacterId(
    String characterId,
  ) async {
    return (select(avatarImages)
          ..where((a) => a.characterId.equals(characterId))
          ..orderBy([(a) => OrderingTerm.asc(a.displayOrder)]))
        .get();
  }

  /// Get a single avatar by ID.
  Future<AvatarImage?> getAvatarById(String id) async {
    return (select(
      avatarImages,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
  }

  /// Count avatars for a character (to determine next display order).
  Future<int> countAvatarsForCharacter(String characterId) async {
    final result = await (select(
      avatarImages,
    )..where((a) => a.characterId.equals(characterId))).get();
    return result.length;
  }

  /// Insert an avatar image record.
  Future<void> insertAvatar(AvatarImagesCompanion avatar) async {
    await into(avatarImages).insert(avatar);
    await bumpSyncVersion();
  }

  /// Delete an avatar image record.
  Future<int> deleteAvatar(String id) async {
    final count = await (delete(
      avatarImages,
    )..where((a) => a.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  /// Update the prime avatar index for a character.
  Future<void> updatePrimeAvatarIndex(
    String characterId,
    int primeIndex,
  ) async {
    await (update(characters)..where((c) => c.id.equals(characterId))).write(
      CharactersCompanion(primeAvatarIndex: Value(primeIndex)),
    );
    await bumpSyncVersion();
  }

  /// Update the label for an avatar image.
  Future<void> updateAvatarLabel(String avatarId, String label) async {
    await (update(avatarImages)..where((a) => a.id.equals(avatarId))).write(
      AvatarImagesCompanion(label: Value(label)),
    );
    await bumpSyncVersion();
  }

  // ── Session Queries ─────────────────────────────────────────────────

  /// Get total message count per character (for home screen badges).
  Future<Map<String, int>> getMessageCountsPerCharacter() async {
    final result = await customSelect(
      'SELECT s.character_id, COUNT(m.id) AS cnt '
      'FROM sessions s JOIN messages m ON m.session_id = s.id '
      'WHERE s.character_id IS NOT NULL AND s.deleted_at IS NULL AND m.deleted_at IS NULL '
      'AND m.is_user = 1 '
      'GROUP BY s.character_id',
    ).get();
    final map = <String, int>{};
    for (final row in result) {
      final charId = row.read<String>('character_id');
      final count = row.read<int>('cnt');
      map[charId] = count;
    }
    return map;
  }

  /// Get the most recent session update time per character.
  Future<Map<String, DateTime>> getLastActivityPerCharacter() async {
    final result = await customSelect(
      'SELECT character_id, MAX(created_at) AS last_at '
      'FROM sessions '
      'WHERE character_id IS NOT NULL AND deleted_at IS NULL '
      'GROUP BY character_id',
    ).get();
    final map = <String, DateTime>{};
    for (final row in result) {
      final charId = row.read<String>('character_id');
      final lastAt = row.read<DateTime>('last_at');
      map[charId] = lastAt;
    }
    return map;
  }

  Future<List<Session>> getSessionsForCharacter(String characterId) =>
      (select(sessions)
            ..where(
              (s) => s.characterId.equals(characterId) & s.deletedAt.isNull(),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
          .get();

  Future<List<Session>> getSessionsForGroup(String groupId) =>
      (select(sessions)
            ..where((s) => s.groupId.equals(groupId) & s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
          .get();

  Future<Session?> getSessionById(String id) =>
      (select(sessions)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<int> insertSession(SessionsCompanion session) async {
    final result = await into(sessions).insert(session);
    await bumpSyncVersion();
    return result;
  }

  Future<int> upsertSession(SessionsCompanion session) async {
    final result = await into(sessions).insertOnConflictUpdate(session);
    await bumpSyncVersion();
    return result;
  }

  Future<bool> updateSession(SessionsCompanion session) async {
    final result = await update(sessions).replace(session);
    await bumpSyncVersion();
    return result;
  }

  /// Partial-update a session — only writes fields that are explicitly set
  /// (Value.present). Safe to call without providing the full row.
  Future<bool> patchSession(SessionsCompanion session) async {
    final rows = await (update(
      sessions,
    )..where((s) => s.id.equals(session.id.value))).write(session);
    await bumpSyncVersion();
    return rows > 0;
  }

  Future<int> deleteSessionById(String id) async {
    // Hard delete: also delete all messages in this session
    await (delete(messages)..where((m) => m.sessionId.equals(id))).go();
    final count = await (delete(sessions)..where((s) => s.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  // ── Message Queries ─────────────────────────────────────────────────

  Future<List<Message>> getMessagesForSession(String sessionId) =>
      (select(messages)
            ..where((m) => m.sessionId.equals(sessionId) & m.deletedAt.isNull())
            ..orderBy([(m) => OrderingTerm.asc(m.position)]))
          .get();

  Stream<List<Message>> watchMessagesForSession(String sessionId) =>
      (select(messages)
            ..where((m) => m.sessionId.equals(sessionId) & m.deletedAt.isNull())
            ..orderBy([(m) => OrderingTerm.asc(m.position)]))
          .watch();

  Future<int> insertMessage(MessagesCompanion message) async {
    if (!message.id.present) {
      message = message.copyWith(id: Value(_uuid.v4()));
    }
    final result = await into(messages).insert(message);
    await bumpSyncVersion();
    return result;
  }

  Future<void> insertMessages(List<MessagesCompanion> msgs) async {
    final withIds = msgs
        .map((m) => m.id.present ? m : m.copyWith(id: Value(_uuid.v4())))
        .toList();
    await batch((b) => b.insertAll(messages, withIds));
    await bumpSyncVersion();
  }

  Future<int> deleteMessagesForSession(String sessionId) async {
    final count = await (delete(
      messages,
    )..where((m) => m.sessionId.equals(sessionId))).go();
    await bumpSyncVersion();
    return count;
  }

  Future<int> deleteMessageById(String id) async {
    final count = await (delete(messages)..where((m) => m.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  Future<void> updateMessage(MessagesCompanion message) async {
    await (update(
      messages,
    )..where((m) => m.id.equals(message.id.value))).write(message);
    await bumpSyncVersion();
  }

  // ── Group Queries ───────────────────────────────────────────────────

  Future<List<Group>> getAllGroups() =>
      (select(groups)..where((g) => g.deletedAt.isNull())).get();

  Stream<List<Group>> watchAllGroups() =>
      (select(groups)..where((g) => g.deletedAt.isNull())).watch();

  Future<Group?> getGroupById(String id) =>
      (select(groups)..where((g) => g.id.equals(id))).getSingleOrNull();

  Future<int> insertGroup(GroupsCompanion group) async {
    final result = await into(groups).insert(group);
    await bumpSyncVersion();
    return result;
  }

  Future<bool> updateGroup(GroupsCompanion group) async {
    final result = await update(groups).replace(group);
    await bumpSyncVersion();
    return result;
  }

  Future<int> deleteGroupById(String id) async {
    // Hard delete: also cascade to sessions and their messages
    final groupSessions = await (select(
      sessions,
    )..where((s) => s.groupId.equals(id))).get();
    for (final s in groupSessions) {
      await (delete(messages)..where((m) => m.sessionId.equals(s.id))).go();
    }
    await (delete(sessions)..where((s) => s.groupId.equals(id))).go();

    // Clean group-owned members (decoupled storage). Their private avatar files under
    // groups/<id>/ are cleaned by the repository layer using StorageService.
    await customStatement('DELETE FROM group_members WHERE group_id = ?', [id]);

    final count = await (delete(groups)..where((g) => g.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  /// Soft-delete a group (sets deletedAt + updatedAt) while hard-cascading its
  /// dependent sessions and messages. The soft-deleted row stays so cloud DB
  /// sync can propagate the deletion flag and the merge layer can prevent
  /// resurrection on other devices.
  Future<int> softDeleteGroupById(String id) async {
    final groupSessions = await (select(
      sessions,
    )..where((s) => s.groupId.equals(id))).get();
    for (final s in groupSessions) {
      await (delete(messages)..where((m) => m.sessionId.equals(s.id))).go();
    }
    await (delete(sessions)..where((s) => s.groupId.equals(id))).go();

    // Clean group-owned members (decoupled storage). Avatar files cleaned by repo layer.
    await customStatement('DELETE FROM group_members WHERE group_id = ?', [id]);

    final now = DateTime.now();
    final count = await (update(groups)..where((g) => g.id.equals(id))).write(
      GroupsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await bumpSyncVersion();
    return count;
  }

  // ── Group Member Queries (decoupled characters, UUID keys, no blobs) ──
  // See GroupMembers table docs for contract. All per-member state keys use the UUID id.

  Future<List<GroupMemberRow>> getGroupMembers(String groupId) =>
      (select(groupMembers)..where((m) => m.groupId.equals(groupId))).get();

  Future<int> insertGroupMember(GroupMembersCompanion member) async {
    final result = await into(groupMembers).insert(member);
    await bumpSyncVersion();
    return result;
  }

  Future<void> updateGroupMember(GroupMembersCompanion member) async {
    await (update(groupMembers)..where((m) => m.id.equals(member.id.value))).write(member);
    await bumpSyncVersion();
  }

  Future<int> deleteGroupMembersForGroup(String groupId) async {
    final count = await (delete(
      groupMembers,
    )..where((m) => m.groupId.equals(groupId))).go();
    await bumpSyncVersion();
    return count;
  }

  /// Delete a single group member row by its instance id (the UUID primary key).
  /// Used when one character is removed from a group (not full-group teardown).
  Future<int> deleteGroupMember(String memberId) async {
    final count = await (delete(
      groupMembers,
    )..where((m) => m.id.equals(memberId))).go();
    await bumpSyncVersion();
    return count;
  }

  // ── Folder Queries ──────────────────────────────────────────────────

  Future<List<Folder>> getAllFolders() =>
      (select(folders)..where((f) => f.deletedAt.isNull())).get();

  Future<String> insertFolder(FoldersCompanion folder) async {
    final id = folder.id.present ? folder.id.value : _uuid.v4();
    folder = folder.copyWith(id: Value(id));
    await into(folders).insert(folder);
    await bumpSyncVersion();
    return id;
  }

  Future<int> deleteFolderById(String id) async {
    final count = await (delete(folders)..where((f) => f.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  Future<void> updateFolder(FoldersCompanion folder) async {
    await (update(
      folders,
    )..where((f) => f.id.equals(folder.id.value))).write(folder);
    await bumpSyncVersion();
  }

  // ── Persona Queries ─────────────────────────────────────────────────

  Future<List<Persona>> getAllPersonas() =>
      (select(personas)..where((p) => p.deletedAt.isNull())).get();

  Future<Persona?> getActivePersona() =>
      (select(personas)
            ..where((p) => p.isActive.equals(true) & p.deletedAt.isNull()))
          .getSingleOrNull();

  Future<int> insertPersona(PersonasCompanion persona) async {
    final result = await into(personas).insert(persona);
    await bumpSyncVersion();
    return result;
  }

  Future<bool> updatePersona(PersonasCompanion persona) async {
    final result = await update(personas).replace(persona);
    await bumpSyncVersion();
    return result;
  }

  Future<int> deletePersonaById(String id) async {
    final count = await (delete(personas)..where((p) => p.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  Future<void> setActivePersona(String id) async {
    await transaction(() async {
      // Deactivate all
      await (update(
        personas,
      )).write(const PersonasCompanion(isActive: Value(false)));
      // Activate the chosen one
      await (update(personas)..where((p) => p.id.equals(id))).write(
        const PersonasCompanion(isActive: Value(true)),
      );
    });
    await bumpSyncVersion();
  }

  // ── World Queries ───────────────────────────────────────────────────

  Future<List<World>> getAllWorlds() =>
      (select(worlds)..where((w) => w.deletedAt.isNull())).get();

  Stream<List<World>> watchAllWorlds() =>
      (select(worlds)..where((w) => w.deletedAt.isNull())).watch();

  Future<String> insertWorld(WorldsCompanion world) async {
    final id = world.id.present ? world.id.value : _uuid.v4();
    world = world.copyWith(id: Value(id));
    await into(worlds).insert(world);
    await bumpSyncVersion();
    return id;
  }

  Future<bool> updateWorld(WorldsCompanion world) async {
    final result = await update(worlds).replace(world);
    await bumpSyncVersion();
    return result;
  }

  Future<int> deleteWorldById(String id) async {
    final count = await (delete(worlds)..where((w) => w.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  Future<World?> getWorldByName(String name) =>
      (select(worlds)..where((w) => w.name.equals(name) & w.deletedAt.isNull()))
          .getSingleOrNull();

  // ── Embedding Queries ──────────────────────────────────────────────

  Future<void> insertEmbedding(MessageEmbeddingsCompanion embedding) async {
    if (!embedding.id.present) {
      embedding = embedding.copyWith(id: Value(_uuid.v4()));
    }
    await into(messageEmbeddings).insert(embedding);
  }

  Future<void> insertEmbeddings(
    List<MessageEmbeddingsCompanion> embeddings,
  ) async {
    final withIds = embeddings
        .map((e) => e.id.present ? e : e.copyWith(id: Value(_uuid.v4())))
        .toList();
    await batch((b) => b.insertAll(messageEmbeddings, withIds));
  }

  /// Get all embeddings for a set of character IDs (for cross-character RAG search).
  Future<List<MessageEmbedding>> getEmbeddingsForCharacters(
    List<String> characterIds,
  ) async {
    if (characterIds.isEmpty) return [];
    return (select(
      messageEmbeddings,
    )..where((e) => e.characterId.isIn(characterIds))).get();
  }

  /// Get all embeddings for a specific session.
  Future<List<MessageEmbedding>> getEmbeddingsForSession(String sessionId) =>
      (select(
        messageEmbeddings,
      )..where((e) => e.sessionId.equals(sessionId))).get();

  /// Delete all embeddings for a session (cascading cleanup).
  Future<int> deleteEmbeddingsForSession(String sessionId) => (delete(
    messageEmbeddings,
  )..where((e) => e.sessionId.equals(sessionId))).go();

  /// Delete all embeddings for a character.
  Future<int> deleteEmbeddingsForCharacter(String characterId) => (delete(
    messageEmbeddings,
  )..where((e) => e.characterId.equals(characterId))).go();

  /// Count total embeddings (for debug/settings display).
  Future<int> countEmbeddings() async {
    final result = await customSelect(
      'SELECT COUNT(*) AS cnt FROM message_embeddings',
    ).getSingle();
    return result.read<int>('cnt');
  }

  // ── Data Bank Queries ────────────────────────────────────────────────────────

  Future<void> insertDataBankEntry(DataBankEntriesCompanion entry) async {
    if (!entry.id.present) {
      entry = entry.copyWith(id: Value(_uuid.v4()));
    }
    await into(dataBankEntries).insert(entry);
  }

  Future<List<DataBankEntry>> getDataBankEntriesForCharacter(
    String characterId,
  ) => (select(
    dataBankEntries,
  )..where((e) => e.characterId.equals(characterId))).get();

  Future<void> updateDataBankEntry(DataBankEntriesCompanion entry) => (update(
    dataBankEntries,
  )..where((e) => e.id.equals(entry.id.value))).write(entry);

  Future<int> deleteDataBankEntry(String id) =>
      (delete(dataBankEntries)..where((e) => e.id.equals(id))).go();

  Future<int> deleteDataBankEntriesForCharacter(String characterId) => (delete(
    dataBankEntries,
  )..where((e) => e.characterId.equals(characterId))).go();

  // ── Objectives ─────────────────────────────────────────────────────

  Future<List<Objective>> getObjectivesForCharacter(
    String characterId, {
    String? chatId,
  }) =>
      (select(objectives)
            ..where((o) => o.characterId.equals(characterId))
            ..where(
              (o) =>
                  chatId == null ? o.chatId.isNull() : o.chatId.equals(chatId),
            )
            ..orderBy([
              (o) => OrderingTerm(
                expression: o.createdAt,
                mode: OrderingMode.desc,
              ),
            ]))
          .get();

  Future<List<Objective>> getActiveObjectives(
    String characterId, {
    required String chatId,
  }) =>
      (select(objectives)
            ..where(
              (o) =>
                  o.characterId.equals(characterId) &
                  o.chatId.equals(chatId) &
                  o.active.equals(true),
            )
            ..orderBy([
              (o) => OrderingTerm(
                expression: o.isPrimary,
                mode: OrderingMode.desc,
              ),
              (o) =>
                  OrderingTerm(expression: o.createdAt, mode: OrderingMode.asc),
            ]))
          .get();

  Future<void> insertObjective(ObjectivesCompanion entry) async {
    final id = entry.id.present ? entry.id.value : const Uuid().v4();
    await into(objectives).insert(entry.copyWith(id: Value(id)));
  }

  Future<void> updateObjective(ObjectivesCompanion entry) => (update(
    objectives,
  )..where((o) => o.id.equals(entry.id.value))).write(entry);

  Future<int> deleteObjective(String id) =>
      (delete(objectives)..where((o) => o.id.equals(id))).go();

  /// Re-key objectives from one character id to another within a session (used
  /// when a chat collapses group->1:1: the survivor's objectives move from its
  /// group member instance id to the origin library id, preserving the rows).
  Future<int> reassignObjectives(
    String fromCharacterId,
    String toCharacterId, {
    required String chatId,
  }) async {
    final n = await (update(objectives)
          ..where((o) => o.characterId.equals(fromCharacterId))
          ..where((o) => o.chatId.equals(chatId)))
        .write(ObjectivesCompanion(characterId: Value(toCharacterId)));
    await bumpSyncVersion();
    return n;
  }

  /// Re-key message embeddings from one character id to another within a session
  /// (used on group->1:1 collapse so the group-era semantic memory, stored under
  /// the `group_id` RAG key, moves to the origin library id and stays
  /// retrievable in 1:1).
  Future<int> reassignEmbeddings(
    String fromCharacterId,
    String toCharacterId, {
    required String chatId,
  }) async {
    final n = await (update(messageEmbeddings)
          ..where((e) => e.characterId.equals(fromCharacterId))
          ..where((e) => e.sessionId.equals(chatId)))
        .write(MessageEmbeddingsCompanion(characterId: Value(toCharacterId)));
    await bumpSyncVersion();
    return n;
  }

  /// COPY a character's embeddings for one session under a NEW character id +
  /// session id, leaving the originals untouched (fresh row ids are assigned).
  /// Used on 1:1->group fork (`/join`): the host's prior RAG memory is duplicated
  /// into the group's shared `group_<id>` memory pool on the new group session, so
  /// the converted cast can recall pre-conversion events that scrolled out of
  /// context — while the preserved 1:1 keeps its own copy (the revert snapshot).
  /// COPY, not move, exactly like the objectives carry-on-fork; the inverse
  /// (group->1:1 collapse) re-keys in place via [reassignEmbeddings]. Returns the
  /// number of rows copied.
  Future<int> copyEmbeddingsForSession(
    String fromCharacterId,
    String fromSessionId, {
    required String toCharacterId,
    required String toSessionId,
  }) async {
    final rows = await (select(messageEmbeddings)
          ..where((e) => e.characterId.equals(fromCharacterId))
          ..where((e) => e.sessionId.equals(fromSessionId)))
        .get();
    if (rows.isEmpty) return 0;
    final copies = rows
        .map(
          (r) => MessageEmbeddingsCompanion(
            sessionId: Value(toSessionId),
            characterId: Value(toCharacterId),
            positionStart: Value(r.positionStart),
            positionEnd: Value(r.positionEnd),
            content: Value(r.content),
            embedding: Value(r.embedding),
            dimensions: Value(r.dimensions),
            memoryType: Value(r.memoryType),
            metadata: Value(r.metadata),
          ),
        )
        .toList();
    await insertEmbeddings(copies); // assigns fresh ids + batches
    await bumpSyncVersion();
    return copies.length;
  }

  Future<int> deleteObjectivesForCharacter(String characterId) => (delete(
    objectives,
  )..where((o) => o.characterId.equals(characterId))).go();

  Future<int> deleteObjectivesForChat(String chatId) =>
      (delete(objectives)..where((o) => o.chatId.equals(chatId))).go();

  // ── Story Project Queries ────────────────────────────────────────────

  Future<List<StoryProject>> getAllStoryProjects() =>
      (select(storyProjects)
            ..where((s) => s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)]))
          .get();

  Stream<List<StoryProject>> watchAllStoryProjects() =>
      (select(storyProjects)
            ..where((s) => s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)]))
          .watch();

  Future<StoryProject?> getStoryProjectById(String id) =>
      (select(storyProjects)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<String> insertStoryProject(StoryProjectsCompanion project) async {
    final id = project.id.present ? project.id.value : _uuid.v4();
    project = project.copyWith(id: Value(id));
    await into(storyProjects).insert(project);
    await bumpSyncVersion();
    return id;
  }

  Future<void> updateStoryProject(StoryProjectsCompanion project) async {
    await (update(
      storyProjects,
    )..where((s) => s.id.equals(project.id.value))).write(project);
    await bumpSyncVersion();
  }

  Future<int> deleteStoryProject(String id) async {
    final count = await (delete(
      storyProjects,
    )..where((s) => s.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  // ── Soft Delete Cleanup ─────────────────────────────────────────────

  /// Permanently remove rows soft-deleted more than 30 days ago.
  Future<void> purgeSoftDeletes() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final cutoffEpoch = cutoff.millisecondsSinceEpoch ~/ 1000;
    for (final table in [
      'messages',
      'sessions',
      'characters',
      'folders',
      'groups',
      'personas',
      'worlds',
      'story_projects',
    ]) {
      await customUpdate(
        'DELETE FROM $table WHERE deleted_at IS NOT NULL AND deleted_at < ?',
        variables: [Variable(cutoffEpoch)],
      );
    }
  }
}
