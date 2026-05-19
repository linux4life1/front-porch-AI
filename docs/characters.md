# Characters & Import

Everything about character cards — creation, import formats, and the V2/V2.5 specification.

---

## Table of Contents

1. [What Is a Character Card?](#what-is-a-character-card)
2. [Creating a Character from Scratch](#creating-a-character-from-scratch)
3. [Character Fields Reference](#character-fields-reference)
4. [Importing Characters](#importing-characters)
5. [V2/V2.5 Card Specification](#v2v25-card-specification)
6. [Front Porch Extensions](#front-porch-extensions)
7. [Managing Characters](#managing-characters)
8. [Troubleshooting Import Issues](#troubleshooting-import-issues)

---

## What Is a Character Card?

A **character card** is a self-contained definition of an AI personality. It includes:

- Name, physical description, personality traits, scenario, and first message
- Example dialogues (few-shot prompting)
- System prompt and post-history instructions
- Alternate greetings
- Tags, attached lorebooks, and linked worlds
- TTS voice assignment
- (In V2.5) Extensions for third-party features

**Storage formats**:
- **PNG** (most common and recommended) — the JSON data is embedded in a `chara` tEXt chunk inside the image (standard V2 spec). The PNG itself is used as the avatar.
- **JSON** — standalone card data (SillyTavern and others also support this).
- **BYAF** — Backyard AI archive format (import only; converted to V2 PNG on save).

Front Porch AI is fully compatible with the **V2 / V2.5 character card specification** used by SillyTavern, Chub.ai, RisuAI, Agnai, and most other modern frontends. Cards you create or edit here will open correctly in those apps (and vice versa), with Front Porch-specific data preserved in the `extensions.front_porch` namespace.

---

## Creating a Character from Scratch

Front Porch AI offers two powerful ways to create characters:

### 1. Manual 6-Step Wizard (`Create Character`)

Located in the sidebar or via the **+** button → **Create Character**:

- **Step 0 – Identity**: Upload avatar (PNG/JPG), name, tags, folder
- **Step 1 – Personality**: Description, personality, scenario, system prompt, post-history instructions
- **Step 2 – Dialogue**: First message, alternate greetings, message examples (few-shot)
- **Step 3 – Lorebook**: Create or attach knowledge-base entries
- **Step 4 – Realism Engine**: Set initial bond/trust, emotion, time-of-day, current task, NSFW cooldown, etc.
- **Step 5 – Review & Save**: Preview, add expression images (for future animated avatars), finalize

The wizard saves the character as a proper V2.5 PNG card (with embedded data) plus any extra avatar images.

### 2. AI-Powered Character Creator

**Character Creator** (also in sidebar) uses the LLM to generate complete cards from your concept:

- **Automated mode**: Just give a name + short concept; it expands everything.
- **Quick mode**: More control over tone, greeting length, relationships.
- **Guided mode**: Detailed prompts for appearance, personality, backstory, kinks, etc.

You can generate lorebooks, multiple alternate greetings, and even pull lore from URLs or local files. After generation you can review/edit every field before saving.

Both methods produce fully editable, standards-compliant cards.

---

## Character Fields Reference

| Field                        | Purpose                                                                 | Tips / Best Practices |
|-----------------------------|-------------------------------------------------------------------------|-----------------------|
| **Name**                    | The character's display name                                            | Used in all `{{char}}` replacements |
| **Description**             | Physical appearance, clothing, mannerisms, voice                        | Be vivid and specific; supports `{{user}}` / `{{char}}` placeholders |
| **Personality**             | Core personality traits, speech patterns, likes/dislikes                | Combine with Description for best results |
| **Scenario**                | Current situation, location, relationship to user                       | Sets the initial context for every new chat |
| **First Message**           | The very first line the character sends                                 | Can be long and atmospheric |
| **Message Examples**        | Few-shot dialogue samples (`{{char}}: ...` / `{{user}}: ...`)           | **Extremely important** for consistent voice, style, and formatting. 4–10 exchanges recommended |
| **System Prompt**           | Hidden instructions prepended to the model                              | Overrides or augments the global system prompt |
| **Post-History Instructions**| Author's note appended after recent chat history                       | Good for "remember this" style guidance |
| **Alternate Greetings**     | Additional possible opening messages                                    | User can swipe or pick on first message |
| **Tags**                    | Free-form labels for filtering/search                                   | Used in the character grid and search |
| **Lorebook**                | Attached knowledge base (entries triggered by keywords)                 | See user-guide for entry syntax (`{{random:}}`, etc.) |
| **Linked Worlds**           | One or more World containers (global lore)                              | Useful for shared settings across many characters |
| **TTS Voice**               | Specific voice to use for this character                                | Overrides the global TTS engine/voice selection |
| **Avatar Images**           | Multiple images (primary + expressions)                                 | Managed in the Avatars dialog; used by future animated features |

All standard fields are serialized exactly according to the V2 spec so other frontends understand them.

---

## Importing Characters

Front Porch AI supports several easy import methods:

- **Drag & Drop** — Drop any `.png` (V2 card), `.json`, or `.byaf` file directly onto the character grid in the Home page.
- **File Picker** — Click **Import** (or the folder icon) → select one or more PNG/JSON files. Bulk import shows a progress dialog.
- **Chub.ai Browser** — Click the Chub.ai button in the toolbar. An embedded browser lets you browse and download cards directly; they are auto-saved as PNGs and imported. (On Linux without wpewebkit it falls back to opening your regular browser.)
- **BYAF Import** — Special importer for Backyard AI `.byaf` archives (extracts image + card data and converts to V2 PNG).
- **Folder Import** — Import an entire folder of cards at once.

**Compatibility**:
- Full support for SillyTavern V1, V2, and V2.5 cards (both PNG `chara` chunk and JSON).
- RisuAI, Agnai, and most other V2-compliant exporters work out of the box.
- After import you are prompted to assign tags via the Tag Dialog.
- All third-party extensions are preserved; Front Porch `front_porch` extensions are read and used for Realism defaults.

Imported characters appear in the grid immediately and can be edited like any native card.

---

## V2/V2.5 Card Specification

Front Porch AI implements the standard **V2 / V2.5** character card format used across the SillyTavern ecosystem.

### Core JSON Structure (inside the `chara` chunk)

```json
{
  "name": "Alice",
  "description": "...",
  "personality": "...",
  "scenario": "...",
  "first_mes": "...",
  "mes_example": "...",
  "system_prompt": "...",
  "post_history_instructions": "...",
  "alternate_greetings": ["...", "..."],
  "tags": ["fantasy", "elf"],
  "character_book": { /* Lorebook JSON */ },
  "world_names": ["MyWorld"],
  "tts_voice": "kokoro/en_female_1",
  "extensions": { ... }
}
```

**Key field name mappings** (for compatibility):
- `first_mes` = First Message
- `mes_example` = Message Examples
- `character_book` = Lorebook
- `world_names` = Linked Worlds

### PNG Storage

The entire JSON object is **Base64-encoded** and stored in a PNG `tEXt` chunk with the keyword **`chara`**. 

The `V2CardService` in the app also manually parses `tEXt` and `iTXt` chunks for maximum compatibility with cards created by other tools (the `image` package alone is sometimes insufficient).

### V2 vs V2.5

- **V2**: The basic fields above + optional `extensions`.
- **V2.5**: Adds the standardized `extensions` object. Front Porch AI stores its data under the `extensions.front_porch` key (see next section). Unknown extension keys from other apps are preserved verbatim (`rawExtensions`) so round-tripping never loses data.

The `toJson()` / `readCard()` methods in `V2CardService` and `CharacterCard` handle both the nested `data` wrapper (some exporters use it) and top-level fields.

---

## Front Porch Extensions

Front Porch AI stores its unique features inside the standard V2.5 `extensions.front_porch` namespace. This data is **only** read/written by Front Porch AI but never interferes with other frontends.

### Realism Engine Defaults (`realism_engine` sub-object)

When you start a **new chat** with a character, these values seed the initial state:

- `enabled`
- `short_term_bond`, `long_term_bond` (-300…+300)
- `trust_level` (-100…+100)
- `day_count`, `time_of_day`
- `character_emotion`, `emotion_intensity`
- `nsfw_cooldown_enabled`, `passage_of_time_enabled`, `chaos_mode_enabled`
- `current_task` (initial quest / objective)

These are edited in the **Realism** tab of the character editor (CreateCharacterPage or EditCharacterDialog) and saved into the PNG.

### Visual & Appearance Extensions

- Per-character chat bubble and text colors (`user_bubble_color`, `ai_bubble_color`, etc.)
- Custom `chat_font_family`
- Multiple avatar images + prime avatar index (stored in DB, referenced from the card)

### Raw Third-Party Extensions

Any keys other than `front_porch` inside `extensions` are kept in `rawExtensions` and written back on export. This guarantees perfect round-trip compatibility with cards that contain Tavern, Risu, or Agnai extensions.

The `CharacterRepository` always re-reads the PNG extensions on load (via `V2CardService.readCard`) to ensure the latest values from the file are used.

---

## Managing Characters

All management happens from the main character grid on the Home page and via right-click / context menus.

### Editing

- Click any character → **Edit** opens `EditCharacterDialog` (or the full `CreateCharacterPage` wizard in edit mode).
- All fields, lorebook, Realism defaults, colors, and avatars are editable.
- Changes are saved both to the database **and** re-embedded into the PNG via `V2CardService.saveCardAsPng`.
- The `CharacterRepository` reloads PNG extensions on every load to prevent stale data.

### Duplicating

Right-click → **Duplicate** (or menu). Creates a copy with "(duplicate)" appended to the name, deep-copies lorebook + Realism extensions, and saves a new PNG + DB entry via `duplicateCharacter()`.

### Exporting

Right-click → **Export** → saves as a standard V2.5 PNG (using the same `saveCardAsPng` logic as creation). The exported file is fully portable to SillyTavern, Chub, etc.

### Deleting

Right-click → **Delete**. Removes from DB and (optionally) deletes the local PNG file. Cloud sync will propagate the deletion on next sync.

### Organization Features

- **Folders**: Characters can be assigned to folders (UI supports creation/renaming).
- **Tags**: Free-text tags with autocomplete. Filter the grid by tag chips or the tag dialog. `CharacterRepository.allTags` provides the global list.
- **Search**: Instant search by name, description, tags, or scenario.
- **Sorting & Filters**: By name, date added, folder, etc.
- **Bulk operations**: Multi-select for import tagging, moving, etc.

`CharacterRepository` (a `ChangeNotifier`) is the single source of truth; the UI (Home page, sidebar, chat header) listens to it for live updates.

---

## Troubleshooting Import Issues

### Common Problems & Solutions

- **"Import failed" or blank character after PNG import**
  - The PNG may not contain a valid `chara` tEXt chunk. Try opening it in SillyTavern first, then re-exporting as PNG.
  - Use the manual `V2CardService.readCard` path (the app already falls back to manual chunk parsing).

- **Avatar image missing or shows as gray square**
  - The image path in the DB was stored as an absolute path on another machine. The `CharacterRepository` automatically normalizes paths to basenames and resolves them from the local `Characters/` folder.
  - Re-import the card or use the **Avatars** dialog to re-assign an image.

- **Chub.ai browser does nothing or crashes on Linux**
  - Linux builds require `wpewebkit` (or use the official AppImage which bundles it). The app detects this and offers a fallback "Open in browser" dialog that still lets you copy the direct `.png` download URL.

- **BYAF import fails**
  - Make sure the `.byaf` archive is a valid Backyard AI export. The dedicated `ByafService` extracts the card JSON and any embedded image.

- **JSON import produces garbled text**
  - The file must be UTF-8 encoded. Re-save the JSON with UTF-8 encoding from your text editor.

- **Lost third-party extensions or Realism data after round-trip**
  - This should never happen. `V2CardService` explicitly preserves all non-`front_porch` extension keys (`rawExtensions`) and always re-reads the PNG on load.

- **Card works in SillyTavern but not here (or vice versa)**
  - Front Porch AI supports both the `data` wrapper and top-level fields. If a card still fails, open an issue with the card (sanitized) attached.

When in doubt, the **Test Card** flow in the character editor or simply starting a new chat usually reveals whether the data was read correctly. All imported cards are immediately usable and can be edited/saved to "normalize" them into Front Porch's preferred V2.5 PNG layout.

---

*This document is kept in sync with the implementation in `lib/services/v2_card_service.dart`, `lib/services/character_repository.dart`, `lib/ui/dialogs/edit_character_dialog.dart`, `lib/ui/pages/create_character_page.dart`, and `lib/ui/pages/home_page.dart` (import/export flows).*
