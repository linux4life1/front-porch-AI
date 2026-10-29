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

// Physical table -> list of "col_name TYPE [NOT NULL DEFAULT 'lit']" fragments.
// These are the columns that were added (or re-added) via the old
// silent-catch ALTERs in onUpgrade — v5 onward, not just the v9-v32 window
// this comment used to name; the v5/v6/v10/v12-v19/v24 columns are on the
// same fragile pattern and are listed below for exactly that reason.
// The presence of these in the list is what guarantees 1:1 + group chat parity
// features will not produce "no such column" on real user databases.
const Map<String, List<String>> kSchemaRepairColumns = {
  'characters': [
    // Every one of these was added by a bare `try { ALTER } catch (_) {}`
    // in the ladder, so a failure (disk full, DB locked by a second
    // instance) leaves the column permanently absent — and Drift's
    // generated SELECT for `characters` names them all, so the library
    // then throws "no such column" on every read with no way back.
    "memory_sources TEXT NOT NULL DEFAULT '[]'", // v5
    "evolved_personality TEXT NOT NULL DEFAULT ''", // v10
    "evolved_scenario TEXT NOT NULL DEFAULT ''", // v10
    'evolution_count INTEGER NOT NULL DEFAULT 0', // v10
    'prime_avatar_index INTEGER NOT NULL DEFAULT 1', // v24
  ],
  'messages': [
    // v14 — same silent-catch pattern. Without these the whole transcript
    // is unreadable, not merely un-annotated.
    'metadata TEXT',
    'swipe_metadata TEXT',
  ],
  'personas': [
    // v6. Dormant since the Journal replaced auto-persona, but Drift still
    // names it in every personas SELECT.
    "learned_facts TEXT NOT NULL DEFAULT '[]'",
    // v3 (the UUID rebuild). Epoch 0 rather than "now" because SQLite
    // rejects a non-constant DEFAULT in ALTER TABLE ADD COLUMN; a 1970
    // timestamp on a row that would otherwise be unreadable is the better
    // of the two outcomes.
    'updated_at INTEGER NOT NULL DEFAULT 0',
    'deleted_at INTEGER',
    // v50 — calendar birthday. NULL = unset.
    'birthday TEXT',
  ],
  'objectives': [
    'chat_id TEXT', // v29 — the one that was actively crashing group objective loads
    'is_primary INTEGER NOT NULL DEFAULT 1', // v20
    'injection_depth INTEGER NOT NULL DEFAULT 4', // safety (was in v8 CREATE + v9 ALTER)
    // v46 — must match the Table definition and the ladder exactly:
    // nullable, no default. NULL means "this quest serves no ambition",
    // which is a real answer and the only honest one for every objective
    // that predates the column.
    'served_ambition TEXT',
    'origin TEXT', 'status TEXT', 'ended_at INTEGER', // v58
  ],
  'message_embeddings': [
    // Added to the MessageEmbeddings Table class during the Journal work
    // WITHOUT a migration: the only CREATE TABLE for this table is the
    // v4→v5 one above, which predates both columns, and no ALTER ever adds
    // them. Fresh installs get them from onCreate's createAll(), so the
    // gap is invisible on any recently-created database — but a library
    // that has simply been upgraded since before the Journal landed has
    // neither column, and Drift's generated SELECT names them, so every
    // RAG read throws "no such column: memory_type". Both are dormant, so
    // the defaults below match the Table class exactly and change nothing
    // for databases that already have them.
    "memory_type TEXT NOT NULL DEFAULT 'message'",
    'metadata TEXT',
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
    // v42 — groups foldering (nullable; null = home top level)
    'folder_id TEXT',
    // v34 — portable group stable id (Stoop update-in-place)
    'stable_id TEXT',
    // v3 (the UUID rebuild) — see the personas note on the epoch default.
    'updated_at INTEGER NOT NULL DEFAULT 0',
    'deleted_at INTEGER',
    // v62 — lore-only worlds for new chats; NULL = never split (legacy seed)
    'lore_world_ids TEXT',
  ],
  'sessions': [
    // v12–v19 Realism columns. All added with the same silent catch, and
    // all named unconditionally by Drift's generated SELECT for sessions —
    // one missing column makes every chat open and every session-list
    // query throw "no such column". Defaults match the Sessions Table
    // class; where the historical ALTER disagreed (v12 wrote
    // relationship_tier DEFAULT 2, a scale that no longer exists) the
    // Table class wins, because that is the value every fresh install has.
    // v4 — the Journal's "Where we are" recap reuses these two.
    'summary TEXT',
    'summary_last_index INTEGER',
    'affection_score INTEGER NOT NULL DEFAULT 0', // v12
    'relationship_tier INTEGER NOT NULL DEFAULT 0', // v12
    'realism_enabled INTEGER NOT NULL DEFAULT 0', // v13
    'short_term_mood INTEGER NOT NULL DEFAULT 0', // v13
    'mood_decay_counter INTEGER NOT NULL DEFAULT 0', // v13
    "character_emotion TEXT NOT NULL DEFAULT ''", // v13
    "emotion_intensity TEXT NOT NULL DEFAULT ''", // v13
    "emotion_cause TEXT NOT NULL DEFAULT ''", // v57
    'emotion_held_turns INTEGER NOT NULL DEFAULT 0', // v57
    "time_of_day TEXT NOT NULL DEFAULT 'morning'", // v13
    'day_count INTEGER NOT NULL DEFAULT 1', // v13
    'arousal_level INTEGER NOT NULL DEFAULT 0', // v15
    'long_term_score INTEGER NOT NULL DEFAULT 0', // v16
    'long_term_tier INTEGER NOT NULL DEFAULT 0', // v16
    'turns_since_long_term_check INTEGER NOT NULL DEFAULT 0', // v16
    'short_term_deltas_summary INTEGER NOT NULL DEFAULT 0', // v16
    'trust_level INTEGER NOT NULL DEFAULT 0', // v17
    "active_fixation TEXT NOT NULL DEFAULT ''", // v17
    'fixation_lifespan INTEGER NOT NULL DEFAULT 0', // v17
    "spatial_stance TEXT NOT NULL DEFAULT ''", // v17
    'trust_repair_pending INTEGER NOT NULL DEFAULT 0', // v18
    "evolved_personality TEXT NOT NULL DEFAULT ''", // v19
    "evolved_scenario TEXT NOT NULL DEFAULT ''", // v19
    'evolution_count INTEGER NOT NULL DEFAULT 0', // v19
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
    'chaos_nsfw_enabled INTEGER NOT NULL DEFAULT 0', // v56
    'generation_settings TEXT',
    'user_persona_id TEXT',
    'passage_of_time_enabled INTEGER NOT NULL DEFAULT 1',
    // v53 — one-shot leftover-PoT re-derive. DEFAULT 0: existing rows
    // are unmigrated. Must match the Table and the ladder.
    'passage_of_time_gate_migrated INTEGER NOT NULL DEFAULT 0',
    'nsfw_cooldown_enabled INTEGER NOT NULL DEFAULT 0',
    'cooldown_turns_remaining INTEGER NOT NULL DEFAULT 0',
    'cooldown_turns_total INTEGER NOT NULL DEFAULT 0',
    // v55 — the refractory in minutes. Nullable; NULL = a pre-v55 row.
    'refractory_minutes_remaining INTEGER',
    'refractory_minutes_total INTEGER',
    'refractory_opened INTEGER',
    'refractory_soft INTEGER', // v59
    'refractory_peaks TEXT', // v59
    'refractory_tail_minutes INTEGER', // v60
    'refractory_tail_total INTEGER', // v60
    'selected_look_avatar_id TEXT', // v37 gallery look
    'theme_overrides TEXT', // per-chat theme
    'context_budget_json TEXT', // v44 Context Viewer snapshot
    // v45 per-chat Objectives switch. DEFAULT 1 must match the Table
    // definition and the ladder exactly — objectives ran unconditionally
    // before v45, so 1 is the only value that preserves existing chats.
    'objectives_enabled INTEGER NOT NULL DEFAULT 1',
    // v47 — matches the Table definition and the ladder: nullable, no
    // default. NULL means nothing was recorded, which is true for every
    // chat older than the column.
    'pockets TEXT',
    // v48 — live Today side-quest row id. Nullable, no default. NULL
    // means this chat has no Today hold, which is true for every row
    // older than the column. Do not guess among secondaries.
    'today_objective_id TEXT',
    // v49 — 1:1 with-you glance. Nullable; NULL = never judged.
    'with_user INTEGER',
    // v38 Story Calendar — nullable; NULL = legacy row, synthesized on load
    'story_clock TEXT',
    'story_start_date TEXT',
    // v43 — 0 = world attachments not yet decided (lets back-fill run)
    'worlds_initialized INTEGER NOT NULL DEFAULT 0',
  ],
  'worlds': [
    // v40 Living Worlds (must match _migrateLivingWorldsV40)
    'cover_image TEXT',
    'format_version INTEGER NOT NULL DEFAULT 1',
    'source_id TEXT',
    'linked_character_id TEXT',
    'biome_id TEXT',
    'biome_json TEXT',
    'inject_description INTEGER NOT NULL DEFAULT 1',
    // v41
    'place_traits TEXT',
    // v51 — climate/weather/atmosphere/gravity plug. DEFAULT 1 so
    // existing worlds keep climate; 0 is a lorebook-only bookshelf.
    'climate_enabled INTEGER NOT NULL DEFAULT 1',
    'parent_world_id TEXT', // v61 — Locations within Worlds
  ],
  'chat_worlds': [
    // v52 — Setting vs Lore role. DEFAULT 0 (lore).
    'is_primary INTEGER NOT NULL DEFAULT 0',
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
