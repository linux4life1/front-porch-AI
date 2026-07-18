# Character Card Forge Integration Guide — Group Chats & Decoupled Members (Post-V30)

**Audience:** Developer of Character Card Forge + their AI coding agents.

**Purpose:** Provide the complete technical picture of Front Porch AI’s group chat architecture since schema v30 so that external tools can:
- Continue reading/writing databases safely.
- Add support for modern group features (especially Group Cards and splitting members to the library).
- Avoid breaking changes or data loss for shared users.

**Last updated:** 2026-05-30 (Rawhide) — Major expansion: full UUID contract + deep technical details on the "Separate to my library" splitting process (including exactly what state transfers and what `duplicateCharacter` does).

---

## Quick Reference (Critical Rules + Line Numbers)

| Topic                              | Must Do / Key Rule                                                                 | Detailed Section + Line |
|------------------------------------|------------------------------------------------------------------------------------|---------------------------|
| **UUIDs for `group_members.id`**   | Must be standard RFC 4122 v4 (any generator is fine). Use the **exact same UUID** as the avatar filename (`<uuid>.png`). | Section 3 (line 120) |
| **Avatar file location & format**  | Always write to `groups/<groupId>/avatars/<uuid>.png` with a valid embedded `chara` V2 chunk. | Section 4 (line 199) |
| **Group Card export (`fpa_group`)**| Populate `raw_member_data[].avatar_base64` + `_original_stable_id` (use the member UUID). | Section 5 (line 215) |
| **Group Card import**              | Create fresh UUIDs + avatar files. Remap using `_original_stable_id` → new UUID (especially for `relationships`). | Section 5 (line 215) |
| **"Separate to my library" (Split)** | Call equivalent of `duplicateCharacter()` on a reconstructed card from the group member row + its private PNG. | Section 6 (line 248) |
| **What transfers on Split**        | Core card data + creation-time `frontPorchExtensions` (seeds). **Live** realism from `sessions.group_realism_state` does **not** transfer by default. | Section 6 (line 248) |
| **Where live realism lives**       | `sessions.group_realism_state` (keyed by `group_members.id`). Only seeds travel in Group Cards / on the member row. | Section 7 (line 344) |
| **Direct SQL writes**              | Update the `columnsToEnsure` map in Front Porch if you add columns. Never bypass schema repair + backup logic. | Section 2.4 + Section 3 |
| **Stable IDs for relationships**   | Use the same UUID (or avatar basename) in `default_member_realism_state`, `baseline_realism_state`, `character_system_prompts`, and `_original_stable_id`. | Section 3 (line 120) + Section 5 |
| **fpa_group chunk structure**      | Keyword = `fpa_group`. Value = base64(UTF-8 JSON). See full example payload with `raw_member_data`, `avatar_base64`, and `_original_stable_id`. | Section 5 (after "On import") |

---

## 1. Executive Summary — The Big Architectural Change

Since schema **v30**, Front Porch AI performed a **clean-break decoupling** of group chat members from the singular character library.

### Before v30 (legacy model)
- `GroupChat.characterIds` (JSON array) stored references to rows in the main `characters` table.
- Group members were the *same* library characters.
- Avatars lived in the shared `characters/` folder.
- Realism state for groups was hidden in special checkpoint messages (`__group_state__`).

### After v30 / v33 (current model)
- Groups have **private, first-class members** stored in a new `group_members` table.
- Each group member is a **complete, independent copy** of a character at the moment it was added to the group.
- Avatars live in **private per-group storage**: `groups/<groupId>/avatars/<memberUuid>.png`
- All per-member state (realism, needs, objectives, system prompt overrides, etc.) is keyed by the member’s UUID (the `group_members.id` column).
- The *only* supported bridge from a group member back into the user’s singular library is the explicit **“Separate to my library”** (extract/split) action.
- Group Cards (`.group.png` files using a custom `fpa_group` PNG chunk) are the primary sharing and round-trip format.

**Critical for external tools:**  
Direct SQL writers (including Character Card Forge) **must stop** writing to the old `characterIds` pattern for groups and must treat `group_members` + private avatar folders as the source of truth.

---

## 2. Schema Changes Since v30 (What External Tools Must Know)

### 2.1 New Table: `group_members` (v33+ contract)

Full definition (from `GroupMembers` Drift table + the repair-path `CREATE TABLE`):

```sql
CREATE TABLE IF NOT EXISTS group_members (
    id TEXT NOT NULL PRIMARY KEY,                    -- UUID v4, stable only inside this group
    group_id TEXT NOT NULL,                          -- references groups.id

    -- Full character card data as typed columns (no blobs for the core card)
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    personality TEXT NOT NULL DEFAULT '',
    scenario TEXT NOT NULL DEFAULT '',
    first_message TEXT NOT NULL DEFAULT '',
    mes_example TEXT NOT NULL DEFAULT '',
    system_prompt TEXT NOT NULL DEFAULT '',
    post_history_instructions TEXT NOT NULL DEFAULT '',
    alternate_greetings TEXT NOT NULL DEFAULT '[]',  -- JSON array
    tags TEXT NOT NULL DEFAULT '[]',                 -- JSON array

    avatar_filename TEXT,                            -- basename only
    tts_voice TEXT,
    lorebook TEXT,                                   -- JSON (same shape as characters.lorebook)
    world_names TEXT NOT NULL DEFAULT '[]',

    front_porch_extensions TEXT,                     -- JSON (FrontPorchExtensions)
    raw_extensions TEXT,                             -- any third-party extensions
    member_state TEXT NOT NULL DEFAULT '{}',         -- small group-scoped per-member JSON

    created_at INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT 0
);
```

**Key rules for external writers:**
- `id` is a **UUID** (never an int, never a character library ID).
- `avatar_filename` is the basename of a PNG that **must** exist at `groups/<group_id>/avatars/<id>.png` (or the member will be invisible or dropped in some paths).
- All realism/needs/objective/prompt keys that belong to this member use this UUID.
- Multi-avatar / expression lists are **not supported** for group members.

### 2.2 Important New/Changed Columns on `groups` table

| Column                        | Type     | Added | Purpose |
|-------------------------------|----------|-------|---------|
| `default_member_realism_state` | TEXT     | v30   | Portable per-member realism + needs + relationships (the rich blob used for new sessions and splitting). JSON. |
| `baseline_realism_state`       | TEXT     | v31   | **Immutable** creation-time seed (what Group Cards export). Separate from the mutable default. |
| `character_system_prompts`     | TEXT     | v32   | Per-character system prompt overrides scoped to this group (`{"uuid": "You are Alice in this scene..."}`). |
| `chaos_mode_enabled`           | INTEGER  | v31   | Group-level Chaos Mode toggle |
| `chaos_nsfw_enabled`           | INTEGER  | v31   | NSFW variant of Chaos |
| `group_lorebook`               | TEXT     | v31   | Group-level lorebook (JSON) |
| `world_ids`                    | TEXT     | v31   | JSON array of world IDs attached to the group |
| `inherit_character_lorebooks`  | INTEGER  | v31   | Whether member characters’ own lorebooks are active inside the group |

### 2.3 Important Columns on `sessions` (group chats)

- `group_realism_state` (TEXT, v30) — The **live, evolving** per-member realism + needs + fixation + relationships state for an active group conversation. Keyed by the `group_members.id` UUIDs.
- `needs_sim_enabled`, `needs_vector`, `start_day_of_week`, chaos pressure fields, etc. — per-session group chat state.

### 2.4 Schema Repair Behavior (Very Important for Long-Lived DBs)

Front Porch runs an automatic repair on every launch (`_repairMissingSchemaColumns`).

---

## 3. UUID Requirements for `group_members.id` (Full Contract for External Tools)

This section exists because **incorrect UUID handling is one of the easiest ways for an external tool to produce broken or non-interoperable groups**.

### 3.1 How Front Porch Generates UUIDs for Group Members

- Package: `uuid: ^4.5.3`
- Call site (used in **every** code path that creates a group member):
  ```dart
  final memberId = const Uuid().v4();
  ```
- This is a **standard RFC 4122 version 4 (random) UUID**.
- Format produced: 36 characters, lowercase hexadecimal, with hyphens, version 4 variant.
  - Example: `a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d`
- No options, no namespace, no timestamp component, no custom version — pure random v4.
- The **exact same string** is used for two things:
  1. `group_members.id` (primary key column).
  2. The filename of the member's avatar PNG: `<uuid>.png` stored at `groups/<group_id>/avatars/<uuid>.png`.

This pattern is identical in:
- Group creation wizard (`create_group_chat_page.dart`)
- Live "Add character to active group" (`chat_service.dart`)
- Group Card import (`home_page.dart`)
- Web server / remote group member addition paths

### 3.2 Can Character Card Forge Generate Compatible UUIDs?

**Yes — any correct UUID v4 generator is fully compatible.**

Front Porch performs **zero validation** that the UUID came from the Dart `uuid` package. The `id` column is a plain `TEXT PRIMARY KEY`.

Recommended generators for Forge:
- JavaScript / TypeScript: `crypto.randomUUID()` (preferred) or `uuid` npm package v9+.
- Python: `import uuid; str(uuid.uuid4())`
- C#: `Guid.NewGuid().ToString("D")` (lowercase)
- Rust: `uuid::Uuid::new_v4()`
- Any other language's cryptographically secure random UUID v4 implementation.

**Output format requirement**: Use the standard 36-character hyphenated form (lowercase is conventional but not strictly required by SQLite).

### 3.3 Full Requirements When Forge Creates or Writes `group_members` Rows Directly

If Character Card Forge ever writes directly to `group_members` (via raw SQL or its own database layer), it **must** satisfy all of the following:

1. **Generate a proper random UUID v4** for the `id` column.
2. **Create the avatar PNG** at exactly this path:
   ```
   <root>/groups/<group_id>/avatars/<the-exact-uuid>.png
   ```
   The PNG **must** contain a valid embedded `chara` tEXt chunk with the full V2 character data for that member (otherwise many runtime paths will treat the member as broken or invisible).

3. **Use the exact same UUID string** as the key in these group-level JSON blobs (when present):
   - `groups.default_member_realism_state`
   - `groups.baseline_realism_state`
   - `groups.character_system_prompts`
   - `group_members.member_state` (if used)
   - `objectives.character_id` (for any objectives attached to this group member)

4. **When exporting a Group Card** from Forge:
   - Put the UUID (or the avatar filename basename without `.png`) into the `_original_stable_id` field on the corresponding entry inside `raw_member_data`.
   - This enables correct remapping of Group Dynamics `relationships` and other per-member keyed data when the card is later imported into Front Porch or another instance of Forge.

5. **Uniqueness**:
   - The UUID must be unique among all `group_members.id` values that share the same `group_id`.
   - Globally unique UUIDs are strongly recommended (standard v4 practice).

6. **What Front Porch does NOT care about**:
   - It does **not** require the UUID to have been generated by Dart.
   - It does **not** store any generation metadata.
   - It treats the value as an opaque stable identifier for that membership inside that group.

### 3.4 Why This Matters for Splitting ("Separate to my library")

When a user splits a group member into a standalone library character, the UUID that was used in the group is **not** carried over into the new library character (the library character gets its own independent ID). However, the **data** that was keyed by that UUID (especially realism seeds in `default_member_realism_state` and the embedded extensions in the PNG) **is** what gets transferred to the new library character via `duplicateCharacter`.

If Forge uses inconsistent or colliding UUIDs, realism relationships, per-character system prompts, and objectives will be lost or mis-attached after import + split.

---

## 4. Storage Layout on Disk

```
<user documents>/FrontPorchAI/KoboldManager/
├── front_porch.db
└── groups/
    └── <groupId>/               # e.g. group_1748...
        ├── avatars/
        │   └── <memberUuid>.png   # Single primary avatar per member (with embedded V2 chara chunk)
        └── (future group-scoped assets)
```

Library characters still live under the old `characters/` structure. Group members **never** share files with the library after addition.

---

## 5. The Group Card Format (`fpa_group`) — Primary Interchange Format

Groups are exported as ordinary PNG files with a custom text chunk:

- Chunk keyword: `fpa_group`
- Contents: base64-encoded JSON of a `GroupCard` object

### What a modern Group Card contains (v1.0)

- `name`, `turn_order`, `auto_advance`, `director_mode`, `first_message`, `scenario`, `system_prompt`
- `members`: minimal CharacterCard list (for display/collage)
- `raw_member_data`: **High-fidelity array** (the important one). Each entry is a full V2 character JSON + these extra keys:
  - `avatar_base64`: Complete PNG bytes of the member’s avatar **with the V2 `chara` chunk already embedded**. This is what enables 100% fidelity even for characters that had no avatar at export time.
  - `_original_stable_id`: The key that was used for this member in `baseline_realism_state` / `default_member_realism_state` / `character_system_prompts` / `member_objectives` at export time. Usually the UUID or the basename of the avatar file. (This is the **export instance id**, used only for ID remapping — see "On import" below.)
  - `_origin_library_stable_id` *(optional, additive in `spec_version` 1.0 — no version bump)*: The **source library character's** `stableGroupId` (avatar basename without extension, or sanitized name) that this member was originally copied from. **Distinct from `_original_stable_id`**: this identifies the *real* character behind the member so an importer can reconnect it to a local library character (Front Porch stamps it into the private `group_members.memberState` on import and resolves it via name/stableGroupId at reconnect time). Omit it for members with no resolvable origin — importers must treat it as optional and ignore it when absent. Do **not** emit `originLibraryDbId`: it is a machine-local DB id, meaningless on another device.
- `baseline_realism_state` — Immutable seed captured at creation/import time.
- `default_member_realism_state` — The richer, updatable per-member state (includes needs vectors, Group Dynamics `relationships` maps, etc.).
- `character_system_prompts`
- `member_objectives`
- `group_lorebook`, `world_ids`, `inherit_character_lorebooks`
- `chaos_mode_enabled`, `chaos_nsfw_enabled`
- `extensions` (future-proofing)

**On import**, Front Porch:
1. Creates a new private group directory.
2. For every entry in `raw_member_data`, materializes a real PNG in `groups/<newGroupId>/avatars/<newUuid>.png` (re-embedding the chara data).
3. Inserts rows into `group_members` using fresh UUIDs.
4. Builds a mapping from `_original_stable_id` → new UUID.
5. Rewrites all the realism blobs, objectives, and prompt overrides using that mapping (including nested `relationships` inside Group Dynamics).

This remapping is what makes “export → send to friend → friend splits members to their library” produce characters that kept the relationships they developed inside the group.

### Example `fpa_group` tEXt Chunk Content

When Front Porch exports a group, it creates a standard PNG `tEXt` chunk with:

- **Keyword**: `fpa_group`
- **Value**: Base64-encoded UTF-8 JSON string

The raw chunk inside the PNG looks like this (conceptually):

```
tEXt
fpa_group\0<base64 data here>
```

#### Decoded JSON Payload (what you get after base64 decoding)

Here is a realistic example of the JSON structure that ends up inside the `fpa_group` chunk (after `base64Decode` + `utf8.decode`):

```json
{
  "spec": "front_porch_group_card",
  "spec_version": "1.0",
  "name": "The Night Watch",
  "members": [
    { "name": "Captain Elara", "description": "...", ... },   // minimal for UI/collage
    { "name": "Scout Thorne", "description": "...", ... }
  ],
  "turn_order": "roundRobin",
  "auto_advance": true,
  "director_mode": false,
  "first_message": "The fog rolls in over the ruined bridge...",
  "scenario": "The three of you are the last patrol before the city falls.",
  "system_prompt": "You are running a tense, grounded military fantasy group.",
  "character_system_prompts": {
    "uuid-of-elara": "You speak with quiet authority and never raise your voice.",
    "uuid-of-thorne": "You are cynical and use dark humor under pressure."
  },
  "group_lorebook": "{\"entries\": [...]}",
  "world_ids": ["world-uuid-1"],
  "inherit_character_lorebooks": true,
  "chaos_mode_enabled": true,
  "chaos_nsfw_enabled": false,
  "baseline_realism_state": "{\"perChar\":{\"old-stable-1\":{\"bond\":45,\"trust\":30,\"relationships\":{\"old-stable-2\":{\"affection\":12}}}}}",
  "default_member_realism_state": "{\"old-stable-1\":{\"bond\":50,\"needs\":{\"energy\":70},\"relationships\":{\"old-stable-2\":{\"trust\":8}}}}",
  "member_objectives": {
    "old-stable-1": [
      {"objective": "Protect the bridge", "tasks": [...], "isPrimary": true, ...}
    ]
  },
  "raw_member_data": [
    {
      "name": "Captain Elara",
      "description": "Veteran officer with a prosthetic arm...",
      // ... all normal V2 character fields ...
      "avatar_base64": "iVBORw0KGgoAAAANSUhEUgAA... (full PNG bytes with embedded chara chunk)",
      "_original_stable_id": "old-stable-1"
    },
    {
      "name": "Scout Thorne",
      "description": "...",
      "avatar_base64": "iVBORw0KGgoAAAANSUhEUgAA... (full PNG bytes)",
      "_original_stable_id": "old-stable-2"
    }
  ],
  "extensions": { ... }
}
```

**Critical fields for integrators to handle correctly:**

- `raw_member_data` is the high-fidelity source of truth (preferred over the `members` array).
- Every entry in `raw_member_data` should contain:
  - Full V2 character data
  - `avatar_base64` — a complete, valid PNG (with `chara` chunk already embedded)
  - `_original_stable_id` — the key used in all the realism / prompt / objective blobs
- `baseline_realism_state` and `default_member_realism_state` use the `_original_stable_id` values as keys.
- The `relationships` objects inside realism blobs also use these stable IDs as targets (this is what the remapper in `_importGroupCard` rewrites).

When writing Group Cards from an external tool, you should produce this exact shape (especially populating `raw_member_data` with `avatar_base64` and `_original_stable_id`).

---

### How to Extract the Chunk (Code Example)

Any PNG library that can read tEXt chunks can extract it:

```python
# Pseudocode
data = extract_text_chunk(png_bytes, keyword="fpa_group")
json_text = base64.b64decode(data).decode("utf-8")
group_card = json.loads(json_text)
```

Front Porch uses `PngMetadataUtils.extractTextChunk(bytes, 'fpa_group')` for robust extraction that handles both `tEXt` and `iTXt`.

---

## 6. “Separate to my library” / Group Splitting Feature — Full Technical Details (Highlight This)

This is the most important user-facing capability enabled by the decoupled architecture, and the one external tools should prioritize implementing.

### 6.1 What “Separate to my library” Actually Does

When the user triggers splitting on a group (home grid context menu or after importing a Group Card):

1. Front Porch calls `GroupChatRepository.getMembersForGroup(group.id)`.
2. This returns `List<GroupMember>` by reading the `group_members` table via `GroupMember.fromRow`.
3. For each member it does:
   ```dart
   final resolvedPath = m.avatarFilename != null
       ? path.join(storage.groupsDir.path, group.id, 'avatars', m.avatarFilename!)
       : null;

   if (resolvedPath == null || !await File(resolvedPath).exists())
       continue;   // ← Current defensive skip

   final card = m.toCharacterCard(resolvedImagePath: resolvedPath);
   await charRepo.duplicateCharacter(card);   // normal library path
   ```
4. `GroupMember.toCharacterCard(resolvedImagePath)` constructs a transient `CharacterCard` containing:
   - All the typed text fields from the row.
   - `lorebook`, `frontPorchExtensions` (realism seeds), `rawExtensions`.
   - `imagePath` set to the **fully resolved private path** on disk.
   - `avatarImages = null`, `primeAvatarIndex = 1` (groups never support multi-avatar).

5. `duplicateCharacter(card)` (called with no overrides) performs a full library duplication:
   - Creates a new name with “ (duplicate)” suffix.
   - Deep-copies all card data + `frontPorchExtensions`.
   - Copies the source PNG (the private group avatar) into the normal library `characters/` structure.
   - **Always** calls `V2CardService.saveCardAsPng(clonedCard, destPath, destPath)` to re-embed the complete V2 metadata (including current FrontPorchExtensions / realism seeds) into the new library PNG.
   - Inserts a new row into the main `characters` table.
   - The new library character is now a completely independent entity.

### 6.2 What State Actually Transfers During a Split

| Data | Source | Does it transfer to the new library character? | Notes |
|------|--------|------------------------------------------------|-------|
| Core card fields (name, description, personality, scenario, firstMessage, etc.) | `group_members` row | Yes | Via `toCharacterCard` → `duplicateCharacter` |
| Lorebook | `group_members.lorebook` | Yes | |
| Alternate greetings, tags, TTS voice | `group_members` row | Yes | |
| FrontPorchExtensions (realism seeds at copy time) | `group_members.front_porch_extensions` | Yes | This is the creation-time / baseline seed for that membership |
| Avatar image + embedded V2 metadata | Private `groups/<gid>/avatars/<uuid>.png` | Yes | Re-embedded during `duplicateCharacter` |
| Evolved live realism state (current Bond/Trust/Emotion from chatting) | `sessions.group_realism_state` | **No** (current behavior) | Only the seeds that were stored on the `GroupMember` row or in the PNG travel. Live session state stays with the group chat. |
| Group-level `default_member_realism_state` / `baseline_realism_state` entries for this member | `groups` table (JSON) | Partially | Only the seeds that were captured into the member's `frontPorchExtensions` or the PNG at materialization time. |
| Per-member objectives | `objectives` table (scoped to the group member's UUID) | **No** (current behavior) | Objectives are group-chat scoped and do not automatically migrate to the library character. |
| Group Dynamics `relationships` | Inside realism JSON blobs | Only the creation-time ones that were stored on the member | Live evolved relationships do not transfer on split today. |

**Key point for Forge implementers:**  
If you want “Split” in Forge to preserve as much evolved state as possible, you will need to read the live `sessions.group_realism_state` for the most recent (or currently open) session of that group and merge/apply the latest values for that member’s UUID when creating the new library character.

### 6.3 The `duplicateCharacter` Safety Net (Important for Compatibility)

Inside `duplicateCharacter`, after the normal copy logic, there is an explicit fallback:

```dart
if (clonedCard.imagePath == null) {
    // ... generate placeholder using V2CardService.saveCardAsPng(clonedCard, destPath, null)
}
```

This is the same mechanism used during Group Card import for avatar-less members. It guarantees that even a group member that somehow has no avatar file will still produce a usable library character with a placeholder PNG containing full embedded V2 data.

When Forge implements splitting, it should apply equivalent logic: **never produce a library character that has a DB row but a missing or corrupt avatar file**.

### 6.4 Current Limitations in Front Porch’s Split Implementation (as of latest)

- The extract loop silently `continue`s if the avatar file is missing on disk. After the 100% fidelity export/import work this should rarely happen for properly imported groups, but it is still a guard.
- No user-visible progress or per-member success/failure reporting during split (just a final count snackbar).
- Evolved session realism and objectives are **not** migrated (as noted in the table above).

### 6.5 Recommended Implementation for Character Card Forge

If you want to offer a high-quality “Split selected members to library” feature:

1. Read the `group_members` rows for the group.
2. For each selected member, resolve its avatar PNG from `groups/<groupId>/avatars/<id>.png`.
3. Reconstruct the full character data (the row already contains almost everything; the PNG gives you the visual + any extra embedded extensions).
4. Create a new independent library character record (whatever Forge’s equivalent of the `characters` table is).
5. Copy + re-embed the avatar as a normal library character PNG (with full V2 `chara` chunk).
6. **Optional but high value**: Also read the latest `sessions.group_realism_state` for the group and apply the current evolved values (Bond, Trust, Emotion, Needs, Fixation, Relationships) to the new character’s realism extensions.
7. Surface the result as normal standalone characters in Forge’s library.

Doing the above (especially step 6) would give Forge users a splitting experience that feels on par with or better than Front Porch’s current native one.

### 6.6 Files to Study for Splitting Logic

- `lib/ui/pages/home_page.dart` → `_extractCharactersFromGroup`
- `lib/services/character_repository.dart` → `duplicateCharacter` (the three-parameter generalized version and the safety fallback)
- `lib/models/group_member.dart` → `fromRow` + `toCharacterCard`
- `lib/services/group_chat_repository.dart` → `getMembersForGroup`

---

## 7. Realism, Needs, Group Dynamics, and Per-Member State

There are three layers of per-member state you must understand:

1. **Group definition level** (travels in Group Cards)
   - `groups.baseline_realism_state` — frozen at creation/import
   - `groups.default_member_realism_state` — the “template” used when starting a new chat or splitting a member out
   - `groups.character_system_prompts`
   - `group_members.member_state` (small)

2. **Live session level** (does **not** travel in Group Cards)
   - `sessions.group_realism_state` — the actual evolving Bond/Trust/Emotion/Arousal/Fixation/Needs/Relationships for an active conversation. Keyed by the same member UUIDs.

3. **Objectives**
   - Stored in the `objectives` table, now scoped by `character_id` that can be a `group_members` UUID when the objective belongs to a group member.

**Group Dynamics relationships** live inside the realism JSON under a `relationships` sub-object (targeting other member UUIDs). The import remapper rewrites both sides of these relationships.

---

## 8. Practical Recommendations for Character Card Forge

1. **Stop assuming** `groups.character_ids` contains anything meaningful for new groups. Treat it as legacy/dead for group member identity.

2. **Add first-class support for the `group_members` table** when the user has a group selected.

3. **Implement Group Card read/write** (the `fpa_group` chunk). This is the future-proof way users will move groups between machines and between apps.

4. **Support the “Split to library” workflow** — at minimum, be able to take the members of a group the user is editing and emit normal V2 character cards (with proper avatars) that can be imported into Front Porch’s library.

5. **Handle the ID remapping contract** if you ever write Group Cards:
   - When exporting, decide on stable IDs for the members (the avatar filename basename or the `group_members.id` UUID both work).
   - Put those IDs into `_original_stable_id` on the raw member objects.
   - Put the corresponding keys into `baseline_realism_state`, `default_member_realism_state`, `character_system_prompts`, and `member_objectives`.

6. **Respect the private avatar contract**:
   - When creating group members via direct SQL, also write the PNG to the correct `groups/<groupId>/avatars/` location with a proper embedded `chara` chunk (or use Front Porch’s placeholder generator logic).

7. **Schema repair awareness**:
   - If Forge ever adds columns, coordinate so the repair map in Front Porch is also updated.

---

## 9. Recommended Source Files to Study (for AI agents)

- `lib/database/database.dart` — `GroupMembers` class + `_repairMissingSchemaColumns` + the `CREATE TABLE` for `group_members` + all the v30–v32 migration comments.
- `lib/models/group_member.dart` — the in-memory model and `toCharacterCard` adapter.
- `lib/models/group_card.dart` — the portable interchange object (especially `rawMemberData` and `_original_stable_id` handling).
- `lib/services/group_card_service.dart` — PNG chunk reading/writing.
- `lib/ui/pages/home_page.dart` — `_importGroupCard`, `_exportGroup`, `_extractCharactersFromGroup`, and the ID remapping logic (`_remapIdsInJson`).
- `lib/services/group_chat_repository.dart` — how members are loaded and materialized.
- `lib/services/character_repository.dart` — `duplicateCharacter` (especially the `targetDirOverride` / `forcedBasename` / `skipLibraryInsert` path and the no-avatar safety fallback).
- `lib/models/group_member.dart` — `fromRow` + `toCharacterCard` (the bridge used during splitting).

---

## 10. Contact / Next Steps

Once this document is reviewed and stable, the Front Porch maintainer will coordinate a formal hand-off with the Character Card Forge maintainer so both sides have the same mental model.

If you (or your AI agent) have questions about any of the realism JSON shapes, the exact structure of `default_member_realism_state`, how Group Dynamics relationships are stored, or the exact avatar embedding rules, open an issue or ask in the Front Porch Discord.

---

**Thank you** for keeping Character Card Forge compatible with the evolving Front Porch ecosystem. The group chat + Group Card + splitting features are some of the most exciting new capabilities, and external tool support will make them dramatically more powerful for users.

---

**Document Authorship**

This guide was researched, written, and maintained by **Grok** (built by xAI) in May 2026 through direct analysis of the Front Porch AI codebase, with iterative refinements based on maintainer feedback.

Primary sources: `lib/database/database.dart`, `lib/models/group_member.dart`, `lib/services/character_repository.dart`, `lib/ui/pages/home_page.dart`, and related group handling code.