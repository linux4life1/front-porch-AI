# User Guide

**Complete feature reference for Front Porch AI** — the private, offline-first desktop app for rich AI character chat, evolving relationships via the Realism Engine, voice interaction, story generation, and more.

This document assumes you have the app installed and at least one backend (local KoboldCpp or remote API) configured. If you're just getting started, see the [Getting Started Guide](getting-started.md) and [Installation Guide](install.md).

> **Tip**: Many actions have keyboard shortcuts. See the full [Keyboard Shortcuts](keyboard-shortcuts.md) reference.

---

## Table of Contents

### Core Features
- [Chat](#chat)
  - Sending Messages
  - Regenerating & Swipes
  - Director Mode (Auto-Play)
  - Action Suggestions
  - Message Editing
- [Characters](#characters)
  - Creating Characters
  - Editing Character Fields
  - Character Folders
  - Tags & Search
- [Lorebooks & Worlds](#lorebooks--worlds)
  - What Are Lorebooks?
  - Creating Lorebook Entries
  - Attaching Lorebooks to Characters
  - World Containers
- [Group Chats](#group-chats)
  - Creating a Group Chat
  - Turn Order
  - Group Settings

### AI & Generation
- [Generation Settings](#generation-settings)
  - Temperature, Top-P, Min-P
  - Repetition Penalty
  - Max/Min Length
  - Stop Sequences
  - Dynamic Temperature & XTC Sampling
- [System Prompts & Author's Note](#system-prompts--authors-note)
- [Memory / RAG](#memory--rag)
  - How Memory Works
  - Configuring Memory
  - Viewing Stored Memories

### Voice Features
- [Text-to-Speech (TTS)](#text-to-speech-tts)
  - Engine Selection (Kokoro, OpenAI, ElevenLabs, Piper)
  - Per-Character Voice Assignment
  - TTS Settings
- [Speech-to-Text (STT)](#speech-to-text-stt)
  - Push-to-Talk
  - Voice Call Mode
  - Whisper Model Selection

### Advanced Features
- [Realism Engine](#realism-engine)
  - Bond & Trust Tracking
  - Emotion States
  - Passage of Time
  - Chaos Mode (Chance Time)
  - Character Evolution
  - Fixation Engine
- [Story Generator (Porch Stories)](#story-generator)
  - Creating a Story Project
  - Prompt Complexity Tiers
  - Story Settings
- [Image Generation](#image-generation)
  - Backend Options
  - Generation Parameters
- [Cloud Sync](#cloud-sync)
  - Google Drive Setup
  - WebDAV Setup
  - Sync Conflicts
- [Web Server](#web-server)
  - Enabling Remote Access
  - Authentication
  - API Endpoints

### App Settings
- [Display & Theme](#display--theme)
- [Backend Configuration](#backend-configuration)
- [Updates](#updates)
- [Backups](#backups)

---

## Chat

### Sending Messages

The heart of Front Porch AI is its beautiful, fully-featured chat interface. Selecting any character from the **Home** grid (or creating a new group chat) opens a dedicated chat session.

#### The Chat Interface Layout

- **App Bar (Top)**: Displays the active character's circular avatar (pulled from their card or multi-avatar folder), name, and a truncated description. A back arrow returns you to the character browser. A sidebar toggle (chevron icons) expands or collapses the powerful right-hand panel containing Lorebooks, Author's Note, Summary, Memory browser, and more.

- **Main Chat Area**: A scrollable, reversed list of message bubbles on top of beautiful themed backgrounds (cyberpunk bedroom, cozy library, rainy Japan, anime cherry blossom, space station, beach waves, EDM rave, and many others). You can also upload completely custom backgrounds.

  Character messages can dynamically change the displayed portrait using the **Expression System** (when enabled in Settings) — the avatar updates to match the current emotional state tracked by the Realism Engine.

- **Input Bar (Bottom)**: A sleek, resizable text field (drag the top grip to grow it from 1–8 lines). 
  - Placeholder reads **"Type a message..."** normally or **"Direct the scene..."** in Director Mode.
  - **Send** button (blue paper plane icon, or amber movie-clapper icon in Director Mode).
  - **Impersonate** (magic-wand icon): The AI writes your next reply for you. Optionally type a prefix first.
  - **Microphone** (when STT enabled): Push-to-talk voice input using your chosen Whisper model.

#### Sending a Message

1. Type in the input box.
2. Press **Enter** (or click the Send icon). **Shift + Enter** creates a new line.
3. The message is added to history and sent to the active LLM backend (local KoboldCpp or remote API).

The model immediately begins generating. Tokens appear **in real time** (streaming) — you see the response building character-by-character.

#### Generation Feedback & Reasoning Models

- A prominent **Stop** button (red stop-circle) replaces the send button while generation is active. Click it to halt output instantly.
- **Reasoning / Thinking Models** (Qwen3, DeepSeek-R1, etc.): Any `<think>…</think>` or `<reasoning>…</reasoning>` blocks are automatically extracted into a clean, collapsible "Thought" chip above the visible response. Tap the chip to expand and read the model's internal chain-of-thought.
- Subtle status text may appear during context preparation, Realism Engine evaluation, or post-processing.

#### Practical Tips

- The input height preference is saved automatically.
- Long presses or right-clicks on messages open context menus (copy, edit, delete, etc.).
- You can switch models, adjust temperature, or enable Director Mode without leaving the chat.
- For the most immersive experience, enable **TTS Auto-Play** and the **Expression System** together.

See also: [Keyboard Shortcuts](keyboard-shortcuts.md) • [Chat Settings Dialog](#generation-settings) • [Director Mode](#director-mode-auto-play)

![Chat interface screenshot placeholder](screenshots/chat_interface.png)

### Regenerating & Swipes

Front Porch AI makes it easy to explore different versions of the AI's replies without losing conversation history.

#### Regenerate Last Response

After any character message, look for the action row that appears below the **last bot message** (only when generation is idle):

- **Regenerate** (orange refresh icon) — Discards the current response and asks the model to generate a fresh one using the exact same context and settings. Great when the model went off-track or you want variety.
- **Continue Generation** (blue downward arrow) — Useful if the previous generation was cut off early (e.g., you hit Stop). The model picks up where it left off.

Both buttons only appear for the most recent character message.

#### The Swipe System (Alternate Responses)

Every character message supports **multiple swipes** — independent alternative generations for that exact turn.

- When you regenerate, the old response is kept as a "swipe" and the new one becomes the active version.
- A pair of **chevron arrows** (◀ ▶) appears when a message has more than one swipe.
- Tap left/right arrows to instantly switch between saved versions.
- The active swipe is highlighted; all previous swipes remain stored in the chat database.

**Deleting Swipes / Messages**: There is no per-swipe delete for individual alternate responses in the current implementation. The trash icon (seen in message headers and long-press context menus in `chat_page.dart`) deletes the **entire message turn** (all swipes for that turn) via `ChatService.deleteMessage(index)`. Swipes are only switched via the chevron arrows or `swipeMessage()`; the entire set of swipes for a turn is stored together in the `ChatMessage.swipes` List and persisted in the DB.

#### Why Swipes Matter

- Perfect for "what if" exploration.
- Lets you keep the best version while experimenting.
- Works beautifully with the Realism Engine — each swipe can produce different bond/trust/emotion updates.
- Swipes are persisted across app restarts and cloud sync.

**Tip**: Combine swipes with Director Mode for rich "what if" storytelling sessions.

![Regenerate and swipe controls placeholder](screenshots/swipe_regen.png)

### Director Mode (Auto-Play / Observer Mode)

**Director Mode** (UI label and `ChatService._observerMode` / `setObserverMode()`) turns the characters into autonomous actors. You become the invisible "director." 

**Terminology note**: Internally the flag is `_observerMode`; the special `observerModeSystemPrompt` (defined in `chat_service.dart`) is used when the user is **not** a participant in the story. The toggle in the UI and group creation dialog is always labeled "Director Mode". "Observer" refers to the invisible-director scenario (especially in groups).

#### How It Works

- Toggle **Director Mode** via the collapsible sidebar in any chat (movie-clapper icon / `chat_settings_dialog.dart` and `chat_page.dart`).
- When enabled:
  - Characters respond to each other automatically (or per turn order in groups).
  - The input box changes to **"Direct the scene..."** — anything you type is sent as a **Director Note** (prefixed internally and injected via `sendDirectorNote()`).
  - A **Response Delay** slider (`directorDelaySec`, default 15.0s from `StorageService`, range 0.5–60s) controls pacing. Stored as `director_delay`.
- In **Group Chats** with Director Mode + `autoAdvance`, an additional play/pause button appears for hands-free operation (`chat_page.dart` around line 2534).

See `chat_service.dart` lines 338–341, 1651, 3187–3199, and the two static system prompts (`defaultGroupSystemPrompt` vs `observerModeSystemPrompt`).

#### Starting & Stopping

- Flip the Director Mode switch in the sidebar.
- In group observer mode, use the floating play/pause button in the app bar area.
- The global stop button (red) always halts both generation and auto-play.
- Director Mode can be toggled per-chat and is remembered.

#### Best Use Cases

- **Background entertainment** — Let two or more characters have a long conversation while you do other things.
- **Character testing** — Observe how personalities interact without constant prompting.
- **Story seeding** — Drop in director notes like "Suddenly the power goes out" or "Time skip to the next morning" to steer the narrative.
- **Relaxing ambient roleplay** — Pair with TTS auto-play and a nice background for a living diorama.

**Note**: Director Mode works with both single-character (they'll monologue or wait for you) and multi-character setups. Realism Engine evaluations still run after each turn.

See: [Group Chats](#group-chats) • Chat Settings Dialog • [StorageService directorDelay](https://github.com/linux4life1/front-porch-AI)

![Director Mode sidebar placeholder](screenshots/director_mode.png)

### Action Suggestions

After the last character message (when idle), you'll see a small **"Suggest actions"** button with a lightbulb icon.

Clicking it asks the LLM to analyze the recent conversation (last ~6 messages) and generate **4 short, clickable action labels** (5–10 words each) describing what *you* (the user) could do next.

Examples of good suggestions:
- "Kiss her and pull her closer"
- "Ask about her day at work"
- "Tease her by pulling away"
- "Suggest moving somewhere private"

#### Using Suggestions

- Once generated, colorful pill-shaped buttons appear below the message.
- **Click any pill** — it is instantly sent as your message (exactly like typing it).
- The suggestions are cleared automatically when you send any message (manual or suggested).

#### Generation Details

- Powered by a lightweight prompt to your active model.
- Works with both local and remote backends.
- Generation is fast (usually < 3 seconds) and shown with a tiny spinner + "Thinking..." label.
- You can regenerate suggestions by clicking the button again.

This feature is always available (no toggle needed) and is a fantastic way to keep momentum during roleplay without breaking immersion or typing long replies.

**Tip**: Great for mobile-like quick interaction even on desktop, or when you're unsure what to say next.

![Action suggestions pills placeholder](screenshots/action_suggestions.png)

### Message Editing

You can edit almost any message in the conversation history — both your own messages and the character's replies.

#### How to Edit

1. Hover or tap the message bubble.
2. Click the small **edit** (pencil) icon that appears in the top-right of the bubble.
3. A dialog opens with a multi-line text editor pre-filled with the current content.
4. Make your changes and hit **Save**.

#### Effects of Editing

- The edited text immediately replaces the displayed message.
- **Conversation history** is updated in the database — future generations will see the new text.
- **Memory / RAG** system: Editing triggers a background re-embedding of the affected message window so long-term memory stays accurate.
- **Realism Engine**: If the edit occurs on a recent turn, the next Realism evaluation will re-compute bond, trust, and emotions based on the revised content.
- Swipes: Editing affects the *currently active swipe*. Other swipes for that turn remain unchanged.

#### Limitations & Best Practices

- System messages (lorebook injections, time skips, director notes) have limited or no editing.
- Very old messages can still be edited, but large changes far in the past may feel inconsistent to the character.
- Deleting a message removes it and all subsequent messages (standard branch pruning behavior).

**Pro Tip**: Use editing + swipes together to "retcon" small details ("I actually said X instead") without restarting the whole chat. The RAG system keeps up beautifully.

![Edit message dialog placeholder](screenshots/edit_message.png)

---

## Characters

Front Porch AI uses the industry-standard **V2 / V2.5 character card format** (PNG with embedded JSON or standalone JSON), fully compatible with SillyTavern, Agnai, and other frontends. See the dedicated [Characters & Import](characters.md) guide for the complete spec and import troubleshooting.

### Creating Characters

There are multiple ways to bring characters into the app:

#### 1. Character Creator (Full Guided Experience)
From the sidebar, click **"Create Character"** (amber-highlighted item with brain icon). This opens a powerful multi-step wizard:

- **Basic Info**: Name, short description, personality, scenario.
- **Opening Lines**: First Message + multiple **Alternate Greetings** (the model randomly picks one on new chat start).
- **Dialogue Examples** (Message Examples / few-shot): Critical for teaching the character’s voice, speech patterns, and formatting. Highly recommended.
- **Advanced Prompting**: 
  - System Prompt (hidden instructions prepended to every context)
  - Post-History Instructions (appended after recent messages)
- **Avatar**: Upload PNG/JPG, crop, or use the built-in AI avatar generator.
- **Realism Engine Defaults** ("Front Porch Extensions"): Set initial bond, trust, fixation, and personality evolution parameters that the character starts with.
- **Tags, Lorebooks, Worlds**: Attach knowledge bases and categorize immediately.
- **TTS Voice**: Assign a specific voice from any supported engine right at creation time.

The creator also offers **AI-assisted generation** with many guided templates (backstory origins, personality sliders, kink lists, dominance, experience level, etc.) so you can generate a rich card from a short concept.

#### 2. Quick Create / Import
- Drag & drop PNG or JSON files directly onto the Home grid.
- Use the **Import** button or Chub.ai browser integration.
- Paste a character JSON.

#### 3. From Existing Chats
New chats can be started from any character; duplicate chats or fork sessions are also supported.

After creation, the character appears in the Home grid and can be opened instantly.

### Editing Character Fields

Open the character card (long-press or click the edit icon on the grid) to reach the full editor. Every standard V2 field is editable:

| Field                    | Purpose                                                                 | Tips |
|--------------------------|-------------------------------------------------------------------------|------|
| Name                     | Display name                                                            | Used everywhere |
| Description              | Physical appearance, mannerisms, clothing                              | Shown in app bar |
| Personality              | Core traits and behavioral guidelines                                   | Most important for consistency |
| Scenario                 | Current situation / starting context                                    | Sets the scene |
| First Message            | The very first line the character says on new chat                      | Sets tone |
| Alternate Greetings      | Multiple opening lines; one chosen at random                            | Great for replayability |
| Message Examples         | Few-shot dialogue samples (user/character pairs)                        | **Strongly affects voice quality** |
| System Prompt            | Hidden instructions always present in context                           | For strict rules or style |
| Post-History Instructions| Text appended after the last user message                               | "Stay in character", formatting rules |
| Tags                     | Free-form labels for filtering                                          | Use liberally |
| Avatar / Multi-avatar    | Main image + optional expression-specific images                        | Supports subfolders for expressions |
| Attached Lorebooks       | Knowledge injected on keyword triggers                                  | See Lorebooks section |
| Linked Worlds            | Broader world containers                                                | See Worlds |
| TTS Voice Assignment     | Specific voice/engine settings for this character                       | Per-character |
| Realism Engine Settings  | Initial bond/trust, evolution rate, fixation targets, NSFW cooldown     | Per-character defaults |

All changes are saved automatically and affect new chats immediately. Existing chats keep their own snapshot of the card at the time the chat was created (you can "refresh" from card in chat settings).

### Character Folders

Organize large libraries with a hierarchical folder system:

- Click the **folder icon** in the Home toolbar to enter **Organize mode**.
- Select one or more characters (checkboxes appear).
- Choose **"Move to Folder"** or create a **New Folder**.
- Folders support nesting; a breadcrumb trail appears at the top when you're inside a subfolder.
- **Back** button / breadcrumb clicks navigate up the tree.
- Folders have names and can be color-coded in future updates (currently named organization).

Folders are stored in the local database and sync via Cloud Sync.

### Tags & Search

Every character supports unlimited free-form **tags**.

- Add/edit tags via the tag icon on a card or in the editor (opens the Tag Dialog).
- In the Home grid, a powerful search bar supports:
  - Plain text search (name, description, personality)
  - Tag filtering (`#fantasy`, `#romance`)
  - Scope selector: **Current folder**, **Folder + subfolders**, or **All characters**
- Sorting options: Name, Recent activity, Import date, Message count.
- Grid zoom slider for comfortable browsing of large collections.

**Pro Tip**: Combine folders + tags + search scopes for professional-grade libraries (e.g., "All Fantasy Characters" folder with tags like `elf`, `mage`, `dark`).

See the full [Characters & Import](characters.md) document for V2.5 spec details, Front Porch Extensions JSON schema, import from BYAF/Chub/SillyTavern, and troubleshooting PNG embedding issues.

![Home character grid with folders and tags placeholder](screenshots/character_grid.png)

---

## Lorebooks & Worlds

Lorebooks provide **dynamic, keyword-triggered knowledge injection** — the most powerful tool in Front Porch AI for maintaining consistency, world-building, and giving characters deep background knowledge without bloating every prompt.

### What Are Lorebooks?

A lorebook is a collection of **entries**. Each entry contains:

- Trigger keywords (comma-separated)
- Rich content (the "memory" or fact to inject)
- Advanced controls (constant, sticky depth)

**How they work**:
1. After every message, the app scans the **recent chat history** for any of the trigger keywords.
2. When a match is found, the corresponding content is **automatically inserted** into the model's context at the optimal position.
3. "Constant" entries are always present.
4. "Sticky" entries remain active for a configurable number of additional turns after their last trigger.

**Use Cases**:
- Character backstories and relationships that must never be forgotten
- World lore, geography, magic systems, technology rules
- Faction information, important NPCs
- Consistent formatting or behavioral rules ("Always speak in third person")
- NSFW safety boundaries or tone guidelines

Unlike RAG memory (which is learned from *your* conversations), lorebooks are **authoritative, curated knowledge** you control.

### Creating Lorebook Entries

Lorebooks live in the right sidebar of any chat (or in the World Management page).

To add an entry:

1. Open any chat → expand the **Lorebook Triggers** section in the right sidebar.
2. Click the **+** or "Add Entry" button.
3. Fill in:
   - **Name**: Human-readable label (e.g., "Elven Kingdom History")
   - **Trigger Keys**: Comma-separated words/phrases that activate it (`elf, elven, Lórien, forest kingdom`)
   - **Content**: The actual text injected into the prompt (can be several paragraphs)
   - **Enabled**: Toggle to temporarily disable without deleting
   - **Constant**: When checked, this entry is *always* injected regardless of triggers
   - **Sticky Depth**: After the last trigger, the entry stays active for this many additional messages (default 1; higher = more persistent)

Entries can be reordered by drag-and-drop in the list. Triggered entries highlight in real time during chat.

### Attaching Lorebooks to Characters

- In the **Character Editor** (or during creation), find the "Lorebook" or "Attached Lorebook" section.
- You can attach an entire lorebook or individual entries.
- Once attached, the lorebook is active for **every chat** started with that character.
- Multiple lorebooks can be attached; they merge intelligently.

You can also manage attachments globally from the **World Management** page.

### World Containers

**Worlds** are higher-level containers that bundle multiple lorebooks + a world-level description. They are perfect for:

- Large shared universes used across many characters
- Campaign settings
- Import from SillyTavern "World Info" or "Lorebook" JSON files

Access **World Management** from the main sidebar (globe/world icon).

Features:
- Create new worlds with rich descriptions
- Add multiple lorebooks to a world
- Color-code worlds for easy visual identification
- Attach worlds to characters (all lorebooks inside become available)
- Import/Export compatible with SillyTavern world format

In chat, worlds appear alongside character-attached lorebooks in the sidebar. Triggered world knowledge is highlighted so you always know what context the model is seeing.

**Best Practice**: Keep core character-specific facts in the character's own lorebook. Put shared world lore in a World container and link it to many characters.

See also the World Management page and [characters.md](characters.md) for attachment details.

![Lorebook sidebar and world management placeholder](screenshots/lorebook_world.png)

---

## Group Chats

Group chats let multiple characters converse together in one session — with full support for Director Mode, Realism Engine, TTS voices per character, and advanced turn management.

### Creating a Group Chat

1. On the **Home** screen, click the **multi-select** icon (checkbox grid) in the toolbar.
2. Select 2 or more characters (they can be from different folders).
3. Click the purple **"Create Group"** button that appears.
4. In the creation dialog:
   - Give the group a name
   - Set an optional opening **First Message** or **Scenario**
   - Choose **Turn Order** (see below)
   - Enable **Auto-Advance** (characters speak in sequence automatically)
   - Enable **Director Mode** by default for this group
   - Optionally provide a group-level **System Prompt**
   - Assign per-character **TTS voices** for the session
5. Confirm — the group appears in your Home grid (distinguished by stacked avatars) and opens directly into chat.

You can also convert an existing single-character chat into a group later via Chat Settings.

### Forking a 1:1 Chat into a Group (with custom entrances)

From a single-character chat, the chat menu's **Fork to Group Chat** opens a
short step-by-step wizard:

1. **Characters** — pick who joins. Drag to reorder; the order is the order they
   enter the scene.
2. **Setup** — group name, optional scenario, and turn order.
3. **Entrance (one step per added character)** — *optional* per character.
   Decide how each newcomer arrives:
   - **Opening line** — your text is used as the character's entrance exactly as
     written (no AI generation).
   - **Direction** — the AI writes the entrance in the character's own voice,
     guided by your text (the direction never appears as a message).
   - **Leave it blank** — the character is simply inserted into the turn order
     with no special entrance.
4. **Review** — confirm the roster, settings, and who gets an entrance, then
   **Fork to Group**.

Each character with an entrance takes a one-off turn to make it, in the order
you arranged them. The group's rotation order becomes: the original
participant(s), then the arrivals **with** an entrance (in the order added),
then the arrivals **without** an entrance at the end. In **Round Robin**, once
all the entrances are done, the **next turn goes to whoever falls right after
the last entrant** in that order — i.e. the first silent arrival, or wrapping
back to the original if there were none. In **Random** mode the next speaker is
random as usual.

> The web UI's fork is single-step (no per-character entrances) for now; the
> stepped wizard is in the desktop app.

### Turn Order

The **Turn Order** setting (editable in group creation and chat settings) controls who speaks when:

- **Round Robin**: Characters take turns in the fixed order you selected them.
- **Random**: Any character (except the last speaker) may speak next.
- **Smart / Weighted**: (future) Characters with higher "initiative" or recent relevance speak more often.

In the chat interface (when not in full auto-play):
- A **"Next Character"** (group icon) button appears in the toolbar.
- It shows who is queued next.
- Clicking it manually triggers the next character to respond.
- In **Director Mode + Auto-Play**, the system respects the turn order while characters converse autonomously.

The currently active speaker is highlighted in the participant list in the group app bar (stacked avatars with purple accent for the next speaker).

### Group Settings

Open the group chat and expand the sidebar or use the **Chat Settings** dialog (gear) for group-specific options:

- Edit group name, scenario, first message
- Reorder or remove participants
- Change turn order and auto-advance behavior
- Per-character voice overrides (different from their individual card TTS settings)
- Group-level Director Mode toggle + delay
- Shared system prompt that applies to the entire group
- Observer mode system prompt (for autonomous group storytelling)

**Special Group Behaviors**:
- Each character keeps their own attached lorebooks and Realism Engine state.
- Expressions update independently per character.
- TTS can speak different voices in sequence or overlapping (configurable concurrency).
- When using Director Mode + Auto-Play, groups become living scenes — perfect for tavern roleplay, parties, or complex story ensembles.

**Tip**: Combine Group Chats + Director Mode + custom backgrounds + TTS Auto-Play for incredibly immersive "ambient theater" experiences. You only need to drop in occasional director notes to steer the story.

Group chats fully support swipes, editing, memory/RAG, image generation, and cloud sync.

![Group chat creation and interface placeholder](screenshots/group_chat.png)

---

## Generation Settings

All generation parameters live in two places:
- **Chat Settings** dialog (gear icon or sidebar) — per-chat overrides
- **Model Settings** dialog — global model + context + hardware settings

When a `.kcpps` preset is active (from your `bin` folder), many of these controls are disabled and the preset takes precedence (a helpful warning banner appears).

### Temperature, Top-P, Min-P

**Temperature** (0.1 – 2.0)
- Controls randomness/creativity.
- **Low** (0.4–0.7): Focused, consistent, "safe" replies.
- **Medium** (0.75–0.95): Balanced and natural (recommended starting point).
- **High** (1.0–1.3): Creative, unpredictable, more likely to go off the rails.
- 0.8 is a very popular default for roleplay.

**Min-P** (0.0 – 1.0)
- Modern alternative (or complement) to Top-P. Filters out tokens below a minimum probability mass.
- Higher values = more focused sampling. Many users prefer Min-P 0.05–0.1 over classic Top-P.

**Top-P** (nucleus sampling)
- Keeps only the smallest set of tokens whose cumulative probability exceeds the threshold.
- 0.9–0.95 is typical. Lower = more conservative.

Front Porch AI exposes **Min-P** prominently because it often produces better results than Top-P alone on modern models.

### Repetition Penalty

**Repetition Penalty** (1.0 – 2.0)
- Penalizes tokens that have already appeared.
- 1.0 = no penalty (model can repeat freely).
- **1.05–1.15** is usually ideal for roleplay — enough to reduce loops without making the character "forget" its own words.
- Higher values (1.2+) can make speech feel stilted.

**Repetition Penalty Range**
- How many recent tokens the penalty looks back at.
- 1024–2048 is a good range for most chats. Larger = more history considered (prevents long-term loops).

A tooltip in the UI explains: "Discourages the AI from repeating the same words. Higher = less repetition."

### Max / Min Length

- **Max Response Length** (tokens): Hard cap on how long a single reply can be. 200–400 is typical for chat; 600+ for long-form narrative.
- **Min Length** (less common): Forces the model to generate at least this many tokens before it can stop.

These interact with the model's native context size and any `.kcpps` preset limits.

### Stop Sequences

Custom strings that immediately halt generation when the model tries to output them.

Common examples:
- `\n\n` (double newline — ends most replies cleanly)
- `User:`, `You:`, character name (prevents the model from speaking for you)
- `###`, `---` (common separators)

Add them comma or newline separated in the Chat Settings dialog. The model "backtracks" if a stop sequence appears mid-generation.

### Dynamic Temperature & XTC Sampling

**Dynamic Temperature**
- Automatically adjusts temperature during generation based on the model's confidence.
- Useful for models that sometimes become too repetitive or too chaotic.

**XTC (Exclude Top Choices) Sampling**
- An advanced technique that occasionally excludes the very highest-probability tokens to increase diversity without raising temperature.
- **XTC Threshold** + **XTC Probability** controls:
  - Threshold: how "top" a token must be before it can be excluded.
  - Probability: how often XTC activates (0.5 is a good starting value).
- Great for creative writing and reducing "safe but boring" outputs on strong models.

These advanced samplers are exposed with helpful tooltips and are safe to experiment with — the defaults are conservative.

**Recommendation**: Start with Temperature 0.8–0.9, Min-P 0.08, Repetition 1.08, Max Length 350. Tweak one variable at a time and use swipes to compare results instantly.

See the Chat Settings and Model Settings dialogs for live sliders and preset warnings.

---

## System Prompts & Author's Note

These two powerful features let you steer the model without the character "seeing" the instructions.

### System Prompt

- A **hidden** block of instructions prepended to every prompt the model receives.
- Perfect for:
  - Strict formatting rules ("Always respond in third person *italic actions*")
  - Safety boundaries
  - Tone enforcement ("Stay playful and teasing even when serious topics arise")
  - World rules that must never be violated
- Editable per-character (in the creator/editor) and per-chat (in Chat Settings).
- Group chats support a shared group-level system prompt.

### Author's Note

- In-context guidance that is **appended after the recent message history** but before the model's reply.
- The character "experiences" it as part of the current situation.
- Excellent for:
  - Temporary mood or environmental cues ("It is raining heavily and thunder is rumbling")
  - Current emotional state reminders
  - "Remember you are currently in the middle of a sword fight"
  - Story direction ("The group has just arrived at the festival")
- In the UI it appears in its own collapsible sidebar section with a text area. Changes take effect on the next generation.

Both features support **live editing** during a chat — perfect for mid-session course corrections.

**Pro Tip**: Use System Prompt for permanent rules, Author's Note for temporary scene direction. Combine with Director Notes for maximum control.

---

## Memory / RAG

Front Porch AI includes a sophisticated **local Retrieval-Augmented Generation (RAG)** system powered by ONNX embeddings running in a Rust sidecar process (`embed_server`). This gives characters genuine long-term memory of your conversations — even across weeks of chatting.

### How Memory Works

1. **Window Embedding**: Every few messages, a sliding window of recent conversation is sent to the embedding model. A dense vector (semantic fingerprint) is created and stored in the local database.
2. **Similarity Search**: When generating a reply, the system queries the vector store for the most semantically similar past memory chunks.
3. **Automatic Injection**: The top relevant memories are inserted into the prompt (usually near the top of context or in a dedicated "Memories" section) so the character can reference them naturally.
4. **Smart Deduplication**: The system avoids injecting duplicate or very recent memories.

The result: characters remember specific events, inside jokes, promises, emotional turning points, and details from dozens or hundreds of turns ago — without you having to repeat everything.

### Configuring Memory

Settings are in **Chat Settings** (or global defaults in Settings page):

- **Enable Memory** (per-chat toggle)
- **Retrieval Count**: How many memory chunks to pull (2–8 typical). More = richer recall but uses more context.
- **Window Size** (`ragWindowSize`, default 5 in `StorageService`): Number of consecutive messages grouped into one embedding chunk. The embedding loop in `MemoryService.embedMessageWindow` steps by this size (non-overlapping windows: i, i+windowSize, ...). Larger = coarser but fewer vectors; smaller = finer recall at cost of more embeddings and context.
- **Embedding Model**: Choice of local ONNX models (smaller = faster/lower VRAM, larger = more accurate semantics). The app will prompt you to download the first time you enable RAG.
- **Background Embedding**: New windows are embedded automatically in the background while you chat.

Memory works with both local KoboldCpp and remote APIs. The embedding sidecar runs independently and is very lightweight.

### Viewing Stored Memories

In the right sidebar of any chat, expand the **Memory** section:

- Browse all embedded memory windows for the current session.
- See the actual text that was embedded and its relevance score.
- Manually trigger re-embedding of the current window if you just edited important history.
- Context Viewer dialog (available from menu) shows the *full* assembled prompt the model actually received, including injected memories, lorebooks, and Realism state.

**Pro Tip**: If a character forgets something important, open Context Viewer, then edit the relevant older messages and force a re-embed. The character will "remember" on the next turn.

Performance note: First-time embedding of a long chat can take 10–30 seconds depending on your CPU/GPU and chosen embedding model. After that it's nearly instant.

See also the dedicated Memory section in the chat sidebar and the ONNX download overlay.

---

## Text-to-Speech (TTS)

Front Porch AI features a modern multi-engine TTS system with per-character voice assignment and seamless integration with chat, Director Mode, and group conversations.

### Engine Selection

Four engines are supported (selectable globally or per-character):

| Engine       | Type     | Quality     | Speed | Cost     | Notes |
|--------------|----------|-------------|-------|----------|-------|
| **Kokoro**   | Local    | Excellent   | Very fast | Free | Default, recommended. High-quality neural voices, runs locally. |
| **OpenAI TTS** | Cloud | Very good   | Fast  | Paid (API key) | Natural voices, requires OpenAI key. |
| **ElevenLabs** | Cloud | Outstanding | Fast  | Paid (API key) | Best prosody & emotion. Requires ElevenLabs key. |
| **Piper**    | Local    | Good        | Fast  | Free | Legacy local engine (still supported for compatibility). |

Switch engines in **TTS Settings** dialog (speaker icon) or per-character in the character editor / chat sidebar.

### Per-Character Voice Assignment

Each character can have its own dedicated voice:

- In the character editor or during chat, open the **Voice Browser** or TTS assignment panel.
- Choose engine + specific voice ID (Kokoro has dozens of high-quality voices; cloud engines have their own catalogs).
- Voices are remembered per character and persist across chats and sessions.
- In **Group Chats**, each participant can speak with a completely different voice — perfect for immersive ensemble scenes.

Voice assignments are also stored in the character's card metadata (Front Porch Extensions).

### TTS Settings

Open the TTS Settings dialog for fine control:

- **Speech Rate / Speed**: Global playback speed multiplier.
- **Auto-Play**: When enabled, the app automatically speaks every new character message (and director notes if desired). Works beautifully with Director Mode.
- **Narrate Quoted Text Only**: Only reads text inside quotes (great for "character voice" vs. narration).
- **Ignore Asterisks / Actions**: Strips *action text* so only spoken dialogue is voiced.
- **Concurrency**: How many simultaneous TTS streams are allowed (useful in lively group chats).
- **Engine-specific options**: API keys for cloud engines, model selection for Kokoro, output device, etc.
- **Voice Browser**: Browse, preview, and download additional Kokoro voices.

TTS works in the background, queues intelligently, and shows progress in the UI. A small speaker icon on message bubbles lets you manually replay any line.

**Pro Tip**: Enable TTS Auto-Play + Director Mode + a nice background image + Expression System for the ultimate "living portrait" experience — characters literally talk to each other while their portraits change with their emotions.

See the [TTS Settings Dialog](lib/ui/dialogs/tts_settings_dialog.dart) and Voice Browser for full options.

---

## Speech-to-Text (STT)

Voice input is powered by **OpenAI Whisper** models running locally (via a sidecar or integrated engine). No cloud required for transcription.

### Push-to-Talk

- When STT is enabled in Settings, a **microphone icon** appears next to the chat input.
- **Click and hold** to record. Release to transcribe and insert the text into the input box (or auto-send, depending on your preference).
- Works in both normal chat and Director Mode.
- A waveform animation shows while recording.
- The transcribed text can be edited before sending.

A "Start voice call" button (green phone icon) is also available when STT is usable and you're not in a group chat.

### Voice Call Mode (Hands-Free)

For the ultimate immersive experience, tap the **Call** button to enter full-duplex voice conversation:

- The app listens continuously.
- When you stop speaking (silence detection), it transcribes and **automatically sends** the message as your input.
- The character responds (with TTS if enabled), and the cycle continues.
- You can interrupt at any time by speaking again or tapping the end-call button.
- A floating **Call Overlay** shows the current transcription and status.

Perfect for lying back and having a real conversation with your character.

Configuration options (in STT settings or the call overlay):
- Silence threshold / timeout before auto-send
- Auto-send on silence vs. manual confirm
- Whisper model choice
- Optional system prompt specifically for voice mode (e.g., "Transcribe natural spoken English, fix grammar lightly")

### Whisper Model Selection

You can choose different Whisper model sizes (downloaded automatically the first time):

- **tiny / base**: Fastest, lowest VRAM/CPU, acceptable accuracy for casual use.
- **small / medium**: Excellent balance — recommended for most users.
- **large / large-v3**: Highest accuracy, slower, more resource intensive.

Trade-off is clear: larger models are noticeably more accurate with accents, proper names, and complex sentences, but take longer to transcribe and use more resources.

STT status, model download progress, and mic permission checks are handled gracefully with clear dialogs.

**Tip**: Combine Voice Call Mode + TTS Auto-Play + Director Mode for completely hands-free, voice-only storytelling sessions. Many users run this while doing chores or driving (with appropriate safety, of course).

See STT Settings and the Call Overlay widget for controls.

---

## Realism Engine

The **Realism Engine** is Front Porch AI's signature feature that makes characters feel truly alive. Instead of stateless conversations, it continuously tracks how the character feels about *you* and how the relationship evolves over time.

See the dedicated **[Realism Engine](realism-engine.md)** guide for the complete deep dive.

### Quick Overview of What It Tracks

**Implementation reality** (see `chat_service.dart` state variables and `_evaluate*Call` methods):

- **Short-term Bond** (`_affectionScore`, clamped -300..+300): Volatile "current closeness". Decays every 10 turns.
- **Long-term Bond** (`_longTermScore`, -300..+300): Stable accumulated relationship.
- **Trust** (`_trustLevel`, -100..+100): Separate reliability axis. Severe drops (>=20) arm a one-shot "trust repair" eval on the next user message.
- **Emotion** (`_characterEmotion`, `_emotionIntensity`): Primary + intensity. Also drives ONNX or LLM `ExpressionClassifierService` for avatar switching (see `expression_classifier.dart`).
- **Fixation** (`_activeFixation`, `_fixationLifespan`): Temporary obsessive personality trait that can be acquired.
- **Arousal / NSFW Cooldown** (`_arousalLevel`, `_cooldownTurnsRemaining`): Tiered system (Feverish...Neutral...Repelled) with phased prompt injection.
- **Passage of Time** (`_timeOfDay`, `_dayCount`, `_turnsSinceLastTimeAdvance`, `_turnsPerTimePeriod = 6`): Automatic deterministic time advancement.
- **Chaos / Chance Time** (`_chaosModeEnabled`, `_chaosPressure`, `_chaosBaseChance=5`, growth +5/turn, cap 100, `_pendingChaosInjection`): Pressure builds until a random "Chance Time" event is injected.
- **One-Shot Eval** (`_storageService.realismOneShotEval`): When true (and for local Kobold), collapses the four separate evals (relationship, emotional, physical, narrative) into a single `_evaluateOneShotCall` using GBNF JSON grammar (`_kGbnfJsonObject`).
- For local backends the evals are sequential (Kobold is single-threaded); for remote they run in `Future.wait`.

All state is captured in `_captureRealismState()` and injected into subsequent prompts. A file-scope `_realismEvalCancelled` flag allows mid-eval abortion. 

The dedicated `realism-engine.md` is the authoritative deep dive; the quick list above is the actual internal model.

### Where to Control It

- **Global default** — Settings page
- **Per-character default** — Character editor (Front Porch Extensions section)
- **Per-chat override** — Chat Settings dialog (gear)

You can enable/disable the entire engine or individual sub-features at any granularity. When active, after every turn an LLM evaluation (often using a fast grammar-constrained JSON call) updates the internal state, which then subtly (or dramatically) influences the next reply.

The current emotional state and bond level are visible in the chat UI (expression avatars update, subtle status chips, and full details in the Context Viewer).

This is what transforms "chatbot" interactions into genuine, evolving relationships.

**Highly recommended** for serious roleplay. Many users leave it on for every chat.

---

## Story Generator (Porch Stories)

**Porch Stories** is Front Porch AI's ambitious multi-agent novel-writing studio. It uses a sophisticated pipeline of specialized LLM agents to plan and write complete, publishable stories — from a simple concept all the way to formatted prose (or even EPUB/audiobook).

Access it from the Home screen by toggling **"Show Stories"** or via the dedicated story pages in the navigation.

### The Pipeline (Multi-Agent Architecture)

The StoryPipelineService orchestrates several distinct stages:

1. **Story Architect** — Takes your high-level concept and generates a rich **Story Bible** (characters, world, themes, tone bible, major plot points).
2. **Act Structurer** — Breaks the story into acts and high-level chapter beats.
3. **Full Act Generation** — For each act, plans scenes, writes prose beat-by-beat, maintains continuity, and handles revisions.
4. **Post-processing** — Chapter summaries, character arc tracking, consistency checks.

The pipeline supports **three model capability tiers** (defined in `models/story_project.dart` as `PromptTier`) so it runs well on everything from 7B local models to powerful remote APIs:

- **Frontier API Models** (cloud): Full complex JSON reasoning for highest quality (GPT-4 class, Claude, etc.).
- **Large Local Models (70B+)**: Simplified but capable JSON output.
- **Small/Mid Local Models (7-34B)**: Minimal JSON, includes quality warnings; fastest on weak hardware.

See `lib/ui/pages/story_setup_page.dart` `_buildTierSelector()` and `_tierName()` for the exact UI labels and descriptions.

### Story Project Settings

When creating a new story project (in Story Setup page) you define:

- **Model Tier** (see above) — selected via `PromptTier` enum; controls prompt complexity and JSON expectations per agent stage.
- **POV**: First person, Third person limited, Third person omniscient, etc. (hardcoded options in story_setup_page.dart).
- **Genre, Mood, Style** (multi-select chips + free text writing guide)
- **Prose Length**, **Narrative Pace**, **Dialogue Density**, **Maturity Rating**
- Characters from your library that should appear (with role assignment: Protagonist, Antagonist, etc.)
- Optional world/lorebook attachments and chat history import for continuity
- `useChatHistory` + `parallelGeneration` flags

The actual agent stages (Story Architect, Act Structurer, scene writing, etc.) are orchestrated by `StoryPipelineService` in `lib/services/story_pipeline_service.dart`. It re-uses `MemoryService` for grounding and `LLMService` for calls. There is **no** "Autopilot" or "Step-by-Step" named mode in the current UI — the dashboard and writer pages let you run the full pipeline or advance stages manually via buttons in `story_dashboard_page.dart` / `story_writer_page.dart`.

Additional tools (export, EPUB, audiobook via `audiobook_generator_service.dart`, token counting) are present.

Porch Stories reuses your existing characters (including Realism state via chat history import), voices, and lorebooks.

Additional tools:
- Export to plain text, Markdown, or EPUB
- Audiobook generation (via TTS)
- Real-time token counting and cost estimation for remote models

Porch Stories is one of the most advanced local novel-writing tools available. It reuses your existing characters, voices, Realism Engine knowledge, and lorebooks for unparalleled continuity.

See the Story Dashboard, Setup, Structure, and Writer pages for the full creative experience.

![Porch Stories dashboard placeholder](screenshots/porch_stories.png)

---

## Image Generation

Front Porch AI includes a built-in image generation system accessible from the chat toolbar (palette/brush icon) and dedicated dialogs.

### Backend Options

- **Remote / Cloud** (default easy option)
- **Automatic1111 (A1111)** — Local Stable Diffusion WebUI
- **DrawThings** — macOS/iOS focused local generator (great on Apple Silicon)

You configure the active backend in Settings → Image Generation.

### Generation Parameters (in the Image Gen Dialog)

- **Prompt** (positive) — Main description. Can be pre-filled from recent chat context or custom.
- **Negative Prompt** — What to avoid.
- **Model** — Choose from your installed Stable Diffusion models (for local backends).
- **Size / Aspect Ratio** — Common presets + custom resolution.
- **Style** — Artistic styles, LoRAs, embeddings.
- **Steps, CFG Scale, Sampler, Seed** — Full control for advanced users.
- **Character / Scene Awareness** — The app can automatically inject the current character's appearance + recent scene description when generating "character portrait", "chat background", or "scene illustration".

### Special Modes (from chat)

- Generate character portrait (uses current expression or card description)
- Generate chat background
- Generate user avatar
- Custom prompt from selection or free text

Images can be saved to the character's avatar folder (for multi-avatar expressions), used as chat backgrounds, or exported.

Generation progress, queue, and history are shown in the download queue panel and image dialogs.

**Tip**: Combine with Director Mode — generate visuals for key story moments automatically or on demand.

---

## Cloud Sync

Your characters, chats, lorebooks, worlds, and settings can be kept in sync across multiple devices using the built-in **Cloud Sync** service (accessible from the sidebar or Settings). Supported providers: Google Drive and WebDAV (Nextcloud, ownCloud, Synology, etc.).

### Google Drive Setup

1. Go to Cloud Sync page.
2. Choose **Google Drive**.
3. Authenticate via Google's OAuth flow (secure, no password stored).
4. Select a target folder in your Drive.
5. Enable sync for Characters, Chats, Worlds, Settings, etc.
6. Set sync interval (manual or automatic on app close / interval).

The app uses the official Google Drive API and stores only an auth token.

### WebDAV Setup

For self-hosted or NAS users:

1. Enter your WebDAV server URL, username, and password (or app-specific token).
2. Test connection.
3. Choose remote path.
4. Same category toggles as Google Drive.

Popular with Synology, Nextcloud, ownCloud, and any standard WebDAV provider.

### Sync Conflicts

When the same character or chat is modified on two devices:

- The app detects conflicts on sync.
- You are presented with a clear conflict resolution dialog showing timestamps and a diff.
- Options: Keep local, Keep remote, or Merge (for supported data types).
- Full database backups are created before any sync operation.

Sync status, last successful sync time, and error logs are shown on the Cloud Sync page. Failed syncs never silently corrupt data — everything is atomic.

**Best Practice**: Use one "primary" machine for heavy editing and let others pull updates, or enable frequent auto-sync with conflict prompts enabled.

Cloud Sync works alongside local auto-backups (every 10 minutes).

---

## Web Server

Front Porch AI can run a lightweight built-in web server, allowing you to access the app from phones, tablets, or other computers on your local network (or the internet with port forwarding / VPN).

### Enabling Remote Access

- In **Settings → Web Server**, toggle **Enable Web Server**.
- Choose a port (default **8085**, stored in `StorageService._webServerPort`).
- Optionally bind to all interfaces (0.0.0.0) instead of localhost.
- The server starts immediately; a QR code or local IP address is shown for easy connection from mobile devices.

You can then open `http://your-ip:port` in any browser on the same network and get a responsive web UI for chatting with your characters.

### Authentication

- **PIN-based session tokens** protect the server.
- On first connection you are prompted to enter a PIN you set in the app.
- Sessions are remembered per device with secure tokens.
- You can revoke all sessions from the settings page.

This keeps your private characters and conversations safe even if the port is accidentally exposed.

### API Endpoints (for Developers)

The server (implemented in `lib/services/web_server_service.dart` using `shelf_router`) exposes a large number of REST endpoints under `/api/` (this list is **not exhaustive**; inspect the source for the current surface):

**Character management** (`/api/characters/...`):
- GET/POST for listing, detail, import (PNG/JSON), edit, avatar upload, evolution updates, databank (lore) CRUD, export PNG, delete.

**Chat / generation** (`/api/chat/...`):
- select, send, stop, regenerate, continue, swipe, edit, author-note, session management, state.

**Other**:
- `/api/auth/login`, `/api/health`, TTS endpoints, memory/RAG queries, story pipeline triggers, image gen, group chat support, and more.

The web UI itself is served from the same server (via `web_chat_bridge.dart` and static assets). There is **no** guarantee of a stable public REST contract — this is primarily for the built-in responsive web client and power-user automation. Full endpoint inventory lives in the router setup inside `WebServerService._startServer()`.

**Security note**: The PIN system + token sessions are the only protection. The server is **not** a hardened production API.

This is excellent for:
- Using Front Porch AI from a phone while the desktop runs the heavy model
- Building custom frontends or automation
- Home automation / voice assistant integrations

Security note: Only enable remote access when on a trusted network or behind proper firewall/VPN. The PIN system is strong but the app is not a hardened production server.

---

## Display & Theme

The Settings page contains a rich set of appearance options under **Display & Theme** (and the dedicated UI Settings dialog).

### Available Customizations

- **Theme Mode**: Dark (default, beautiful deep slate/navy), Light, or System.
- **Text Scale**: Global font size multiplier for accessibility.
- **Chat Backgrounds**: Dozens of high-quality themed images (cyberpunk, anime, cozy, nature, fantasy) + full support for **custom uploaded backgrounds** (stored in your data directory).
- **Message Bubble Colors & Opacity**: Fine-tune user vs. character bubble colors and transparency.
- **Font Family**: Choose from several Google Fonts (Roboto, Open Sans, Lato, Source Sans 3, Nunito) plus system defaults. Applied live.
- **Expression Display Mode**: Sidebar portraits, floating, or disabled.
- **Grid Scale** (Home screen): How large character cards appear.
- **Sidebar Width** persistence in chats.

Many of these are also accessible quickly via the **UI Settings** dialog from the chat or main menu.

Changes are applied instantly and persisted. The entire app feels cohesive because theming is applied at the root level.

---

## Backend Configuration

The **Model Manager** page (rocket icon in sidebar) and **Model Settings** dialog are your central hubs for everything LLM-related.

### Local Backend (KoboldCpp)

- The app automatically manages a bundled or user-provided KoboldCpp binary.
- **Model Hub** inside the app lets you browse and download popular GGUF models directly.
- **Hardware Acceleration**:
  - NVIDIA (CUDA + Flash Attention — massive speed boost)
  - Apple Silicon (Metal)
  - AMD (ROCm or Vulkan)
  - Intel Arc / Vulkan
  - CPU fallback (AVX2/AVX512)
- **Context Size**: Set per model or globally (subject to `.kcpps` preset overrides).
- **GPU Layers**: How many layers offload to VRAM (auto or manual).
- **.kcpps Presets**: Place preset files in your `bin` folder — they can lock context size, sampling, and other params. The UI dims controls and shows clear warnings when a preset is active.

### External / Remote APIs

- **OpenRouter** support with API key entry and model browser.
- Generic OpenAI-compatible endpoints.
- Per-feature routing (e.g., use local for chat, remote for story generation or image prompts).

### Model Selection & Switching

- Switch the active model live from the Model Manager or Model Settings dialog without restarting chats.
- The app remembers your last used model per backend type.
- Kobold log viewer is available for debugging generation issues.

All settings are explained with tooltips. The first-launch setup wizard helps new users choose the right acceleration method for their hardware.

See the Model Manager page and `lib/ui/dialogs/model_settings_dialog.dart` for the full UI.

---

## Updates

Front Porch AI has a robust built-in updater.

- On launch (and periodically), the app checks for new releases on GitHub.
- When an update is available, a friendly **Update Dialog** appears with release notes.
- You can **Download & Install** immediately or **Later**.
- The downloaded installer is staged; on the next clean app close it will run automatically.
- **Beta vs Stable**: You can opt into the beta channel in Settings for early access to new features (and occasional bugs — use at your own risk).

Update checks respect your privacy and only contact GitHub. You can also manually trigger a check from the Settings page or the sidebar update indicator.

The current version is shown in the app title bar and About dialog (with `app_version.dart` constants).

---

## Backups

Your data is precious. Front Porch AI protects it aggressively.

### Automatic Backups
- Every **10 minutes** of active use, the app creates a timestamped backup of the entire SQLite database + critical folders (characters, chats, worlds, settings).
- Backups are stored in a dedicated `backups` directory inside your data folder.
- Old backups are pruned intelligently to avoid filling your disk.

### Manual Backups
- From the Settings page or Cloud Sync page, click **"Create Backup Now"**.
- A full consistent snapshot is written immediately.

### Restoring
- The app can restore from any backup directly from the Settings UI.
- On launch, if corruption is detected, the app offers to restore from the most recent healthy backup automatically.
- You can also manually copy a backup folder back into place (advanced users).

### Database Health
- Drift ORM + careful transaction handling makes corruption extremely rare.
- The app performs integrity checks on startup and before/after sync operations.

**Recommendation**: Enable Cloud Sync + rely on the automatic local backups. Between the two, data loss is virtually impossible even in the event of hardware failure or user error.

Backups include everything except large model files and downloaded TTS/embedding models (those are easy to re-download).

