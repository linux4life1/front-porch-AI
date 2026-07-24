# The "Living Time" Release — Feature Scoping

**Status: SCOPED (2026-07-21) — awaiting maintainer priority call.**
Five features that make characters feel like they live in time, scoped against
the actual Rawhide codebase. Release theme for the update dialog: *"Your
character lives in time — they dream, they notice your absence, weather rolls
through their days, and your story together becomes a book."*

**Cross-cutting design wins (deliberate, all five):**
- **Based on Rawhide.** All work branches from and lands on `Rawhide` (new
  features per the branch workflow).
- **Riverpod-compliant, CODEGEN style (maintainer directive, 2026-07-21;
  tightened same day).** All new code uses `@riverpod` annotations with
  `riverpod_generator` — NOT hand-rolled provider globals: functional
  providers for pure derivations (family params are plain named args,
  autoDispose by default), `@riverpod class … extends _$…` Notifiers /
  AsyncNotifiers for state (async `build` IS the fetch; mutations are
  methods on the class), UI consumes via `ref.watch` + `AsyncValue`, and
  every provider must be exercisable in a bare `ProviderContainer` (see
  `test/services/chat/riverpod_providers_test.dart`). Domain leaves stay
  pure Dart with constructor injection — they are not state management.
  Where a feature must read the legacy Provider-based `ChatService`, values
  cross at the widget boundary as plain arguments — no new
  `ChangeNotifier`s, no new `Provider.of` in new widgets. Generated
  `.g.dart` files are committed (same policy as Drift).
- **Zero schema changes.** Weather is recomputed (pure function of existing
  state), milestones ride the existing `journal_cards` table, absence is
  computed from existing timestamps, dreams are ordinary messages + journal
  cards, novella export adds only additive JSON fields to `StoryProject`.
- **No new native/sidecar anything.** Every LLM call goes through
  `LlmEvalEngine` (think-strip, retry/cancel, local-model floor).
- **1:1/group parity by construction** — each feature's state is either
  per-chat-shared (weather, absence) or keyed the same way the Journal already
  keys per-character state (`ChatParticipant.id`).
- **Web parity planned per feature** (facade + web_ui surface listed in each).

---

## 1. Dreams 💤 (Effort: S–M, ~2–3 days)

When the story clock crosses a night (or an AFK nap fires), the character
dreams — seeded from what the Journal says actually mattered.

### Behavior
- On the first turn after `TimeService.dayCount` increments past a night
  period (or after an AFK sleep/nap snapshot), a short first-person dream
  (2–4 sentences) arrives as a special narration before the morning reply:
  hazy, associative, referencing real memories — never new canon facts.
- The dream is also planted as a journal card (`metadata.kind = 'dream'`,
  low heat, unpinned) so it appears in the diary and can resurface later.

### Architecture
- **New leaf:** `lib/services/chat/dream_service.dart` (<300 LOC) — pending
  flag, prompt builder, forgiving parse (plain text; sanity/length floor —
  a garbage local-model output silently skips the dream), card plant via
  `JournalStore`.
- **Seed inputs (all existing):** top-N hottest cards via
  `JournalPhysics.cooledHeat` ordering; active fixation
  (`RelationshipService`); current `_characterEmotion` scalar; the "Where we
  are" recap.
- **Trigger wiring:** day-rollover detection in the existing
  `TimeService.advanceTimePeriods` callback path + the AFK activity hook in
  `chat_service_idle_autonomous.dart` (which already advances time and has
  the `_pendingIdleCue` mechanism — dreams ride an identical
  `_pendingDreamCue`).
- **Rendering:** reuse the Chance Time centered-banner style in
  `message_bubble.dart` (`metadata['is_dream']`), moon icon, porch-amber
  chrome.
- **Group parity:** dreams are per-character; the speaker whose turn follows
  the night crossing dreams. Cards key off `ChatParticipant.id` exactly like
  the Journal.
- **Web:** free for the message (arrives via `chat_facade` like any message);
  diary card appears in the web journal surface.

### Settings
"Dreams" toggle in the realism cluster; effective-on requires Journal +
passage-of-time on. Default ON when both are on.

### Risks
Local-model dream quality → mitigated by skip-on-garbage floor. One extra
LLM call per story-day maximum (bounded, off the hot path).

**Shipped 2026-07-21.** Two deviations from the sketch above, both
deliberate: (1) rollover detection is session-scoped bookkeeping inside
DreamService checked once at sendMessage entry (covers every advancement
path — evals, AFK, manual nudge — with zero TimeService/AFK surgery, and a
fresh load can never fire for days that passed while the app was closed);
(2) the dream owner is the character who ended the previous day (last
assistant speaker) — ONE rule for 1:1 and group, parity by construction,
rather than the "upcoming speaker" idea which is unresolvable at insertion
time in groups. Dream message inserts before the user's morning message;
card kind='dream' rides the new additive `kind` metadata field on
JournalStore.addCard (also the base primitive milestones will use).

---

## 2. Real-absence awareness + "Previously on…" 📺 (Effort: S, ~1–2 days)

The character notices you were gone; the app reminds you where you left off.

### Behavior
- **"Previously on" banner (no LLM, always tasteful):** opening a chat after
  a real-world gap ≥ threshold (default 24h) shows a dismissible banner:
  *"It's been 4 days — where we left off:"* + the existing `Sessions.summary`
  recap. Pure read-model.
- **In-character acknowledgment (opt-in, DEFAULT OFF — maintainer decision
  2026-07-21):** the first exchange after the gap carries a single injection
  line telling the model roughly how long passed and to acknowledge naturally
  without dwelling. Consumed after one response — never repeats. The *story*
  clock is untouched; this is meta-awareness, deliberately opt-in because a
  character spontaneously commenting on your real-world absence can read as
  creepy rather than charming.

### Privacy by design (preempting "this app is tracking me!")
The honest technical answer, stated up front and enforced by the design:

1. **No new data is collected — at all.** The gap is computed in memory on
   chat open from the timestamp of the last message, which the local SQLite
   DB has stored since day one (every chat app on earth stores message
   times). The feature writes nothing, reads nothing new, and transmits
   nothing — the app is local-first and offline by default, and being
   AGPL-open-source, anyone can verify that claim in the code.
2. **The character knows only what a pen-pal would know.** "Your last letter
   was dated the 12th" — that is the entire information content. Not app
   opens, not what you did, not where you were, not usage patterns.
3. **Coarse granularity, always.** The banner and the injection both use
   buckets — "a day", "a few days", "about a week", "a long while" — never
   "4 days, 7 hours, 23 minutes". Precision is what makes time-awareness feel
   like surveillance; coarseness is what makes it feel like a friend.
4. **The banner speaks in the app's voice, not the character's.** "It's been
   a few days — where we left off:" reads like a game's "welcome back"
   screen: a familiar, obviously-mechanical convenience. Only the opt-in
   feature puts the awareness in the character's mouth.
5. **The prompt forbids speculation.** The injection instructs: acknowledge
   the gap briefly and naturally; do NOT guess what the user was doing, imply
   monitoring, or bring it up again. A character saying "you were gone a
   while" is warm; a character saying "where were you?" is not.
6. **Transparent settings copy.** The toggle's description states exactly the
   mechanism: *"Uses the time of your last message — already saved with your
   chat. Nothing new is collected and nothing leaves your device."* A
   matching FAQ entry goes in the website docs alongside this feature's
   release notes.

### Architecture
- Gap computation on session load in `chat_service_session_load.dart` from
  the last message's DB timestamp → `_absenceGapHours` scalar + one-shot
  flag. No storage.
- Injection line added to the existing
  `chat/prompt_injection/time_injection.dart` (guarded by the one-shot flag).
- **New widget:** `ui/chat_components/overlays/absence_recap_banner.dart`
  (AppColors throughout).
- **Web:** the facade already exposes the recap; add `absenceGapHours` to the
  chat snapshot and mirror the banner in web_ui (both phone + wide layouts).
- **Group:** gap is per-chat; the injection addresses the group collectively.

### Settings
Toggle + threshold (12h/24h/3d/1w) in General; acknowledgment sub-toggle
default OFF, banner default ON.

**Shipped 2026-07-21** as designed (banner + opt-in ack + threshold +
privacy copy + web parity). Gap anchor: the last message row's `updatedAt`,
read at load before any save can refresh it.

### Risks
Essentially none. Guard: never fire for gaps while the app was merely
backgrounded mid-session (anchor to last *message*, not last app-open).

---

## 3. Weather & seasons 🌦 (Effort: M, ~3–4 days)

Deterministic weather over the story calendar, felt in prompts, Needs, and
the sidebar.

### Behavior
- Each story day has weather (condition + temperature band) with day-to-day
  continuity (a storm system passes through; it doesn't strobe). Seasons fall
  out of `TimeService.clock` — it is a real `DateTime`, so month → season is
  free.
- Consumers: one injection line ("Cold steady rain since morning; late
  autumn."), gentle Needs effects (comfort decays slightly faster in
  storms/heat; small fun scene-reward bonus on clear days — magnitudes tiny),
  and a weather glyph next to the existing scene-time display.

### Architecture
- **New pure leaf:** `lib/services/chat/weather_engine.dart` — seeded PRNG
  keyed on `(sessionId.hashCode, dayCount)`, yesterday-biased Markov step,
  season from clock month. **Same inputs → same weather, so nothing is
  stored** — recomputed on demand, save/load-proof, zero schema.
- **New builder:** `chat/prompt_injection/weather_injection.dart`, registered
  beside `time_injection`.
- **Needs hook:** apply identically in the 1:1 scalar path and the
  `_groupRealism` per-speaker path (weather is per-chat shared state, so
  parity is trivial — but the change touches decay/reward, so the mandatory
  dead-code audit + both-paths check from CLAUDE.md applies).
- **UI:** glyph + tooltip in the sidebar scene-time section; same in web_ui
  (facade adds `weather` to the realism read snapshot).
- **Tests:** golden determinism tests on `WeatherEngine` (fixed seeds → fixed
  sequences) + season boundaries.
- **Future (explicitly out of scope now):** auto-background switching.

### Settings
"Weather" toggle (Settings → General → Story Weather), default ON, effective
only when realism + passage-of-time are on (gated in
`ChatService.currentWeather`).

**v1 note (shipped 2026-07-21):** the global toggle shipped; the per-chat
override ("always sunny here", via the session `generation_settings` JSON
blob) was explicitly deferred — small, additive, and independently shippable
later. Not a silent deferral: recorded here and in the changelog.

### Risks
Needs balance — keep deltas ±1-grade and behind the toggle. Parity audit is
the real work item.

---

## 4. Chat → novella export 📖 (Effort: M, ~3–5 days)

Turn a beloved chat into a formatted story/EPUB keepsake.

### Key finding — mostly built already
`StoryPipelineService.runChatDistiller` already ingests chat history into a
StoryProject; the full stage chain (architect → acts → scenes → draft/edit)
exists; **`EpubGeneratorService` and the web `story_export_facade.epub()`
already ship.** What's missing is the one-tap flow and a *faithful* mode.

### Behavior
- Chat menu: **"Turn this chat into a story…"** → small config dialog
  (length: short story / novella; POV: third-limited / first; mode: faithful
  retelling / inspired-by) → lands in the existing Story dashboard with a
  pre-configured project; the familiar pipeline UI takes it from there →
  export EPUB/Markdown as today.

### Architecture
- **StoryProject model:** add `chatHistorySessionIds` (additive JSON field)
  so the distiller can scope to *this session* instead of all sessions for
  the character (current behavior), plus a `faithfulMode` flag.
- **Faithful mode prompts:** architect/scene stages constrained to follow the
  chat's actual events in order. The outline spine comes free from data we
  already have: the "Where we are" recap + salient journal cards (which carry
  `storyDay`/`storyClock` metadata — the emotionally-important beats,
  pre-identified). New prompt variants live in a new
  `lib/services/story/faithful_mode.dart` leaf (StoryPipelineService is
  already huge; do not grow it).
- **Entry point:** chat page menu item + config dialog (follows standard
  dialog patterns; it is not a wizard — the Story dashboard is the flow).
- **Web:** story facades exist; add the same entry to the web chat menu and
  pass through to the existing story surfaces.

### Risks
Very long chats vs context — the distiller already chunks; verify at 1k+
messages. Set expectations in UI copy: it produces a *draft* the user can
regenerate per scene (existing per-scene controls).

**Shipped 2026-07-21.** As designed, with one scope note: the chat-menu
entry is **1:1 only for now** (multi-protagonist novelization of groups is a
future effort; the menu item hides in groups). The shared
`buildChatStoryProject` in `services/story/faithful_mode.dart` is the ONE
builder behind both the desktop dialog and the web
POST /api/chat/tools/to-story, and the web entry uses one-tap defaults
(faithful novella) as its form-factor adaptation — full config remains
available in the web story setup like any project.

---

## 7. Milestones timeline — "Our Story" 🏆 (Effort: M, ~3–4 days)

One chronological timeline of everything that mattered: growth rings, Chance
Time strikes, completed objectives, flashbulb memories, bond thresholds.

### Architecture — a read-model first, one new write second
**v1 (pure aggregation, zero new writes):**
- **New leaf:** `lib/services/chat/milestone_feed.dart` (<300 LOC) merging
  four existing sources per session+character, sorted by story time:
  1. `growth_rings` table (already indexed by session/character)
  2. Journal cards where pinned / flashbulb-grade heat/intensity
     (`storyDay`/`storyClock` metadata already stamped on every card)
  3. Messages with `is_chance_time_narration` metadata
  4. Completed objectives (objectives table, per-chat)
- **UI:** a second tab inside the existing `journal_dialog.dart` —
  **"Diary | Our Story"** — vertical timeline grouped by story day
  (TimeService date formatting), typed icons (🌱 ring, ⚡ chance, 🎯
  objective, 📔 memory, 💞 bond). Tap-to-jump reuses `message_jump.dart`
  wherever a source message exists. No new dialog surface.
**v1.5 (one new write path):**
- Bond/trust **threshold crossings** recorded at the moment they happen via a
  hook in `RelationshipService` — written as journal cards with
  `metadata.kind = 'milestone'`. Reuses `journal_cards` (no schema), inherits
  delete-with-chat and review-first for free. Small `JournalPhysics`
  exemption: milestone cards never cool (pinned-equivalent).

### Parity
Per-character in groups — identical keying to the Journal
(`ChatParticipant.id` is the storage key). Web: `chat_facade` exposes a
`milestones` list; web_ui renders the same timeline (phone + wide layouts).

### Risks
Historical bond thresholds (before the feature existed) are only
approximately reconstructable from per-message realism metadata — v1 simply
starts recording from feature-on, which is honest and cheap.

**v1 shipped 2026-07-21** (read-model + Diary|Our Story tab + web "Our
story" panel over the same `ChatService.milestoneFeed` instance +
`/api/chat/tools/timeline`). Ordering note: entries sort by story position
where a receipt exists; position-less sources (objectives, receipt-less
rings) interleave via the diary's own (wallTime → position) index.

**v1.5 shipped 2026-07-21** (threshold-crossing milestone cards):
`RelationshipService.applyScoreDelta` / `applyTrustDelta` fire an optional
`onTierCrossing` callback only when the *named tier* changes (not every
score wiggle). `ChatService` plants a `journal_cards` row with
`metadata.kind='milestone'` via `relationship_milestones.dart` (pure text +
plant). Regen revert uses `recordMilestone: false` so undoing a rejected
reply never invents reverse beats. Physics: milestones never cool and are
cap-trim protected (`JournalPhysics.isMilestone`) but are **not**
always-injected (would crowd the hot set) — they stay on the timeline and
can still resurface via cold retrieval. Web free (same feed + 🏆 icon).
Historical crossings before feature-on remain absent by design. **Message
chips (per-turn deltas) are unchanged** — milestones are the long-horizon
diary, not a chip replacement.

**v1.5.1 shipped 2026-07-21** (long-term bond tier crossings):
`_evalLongTermGrowth` fires `axis: 'long_term'` when the long-term *named*
tier moves (same plant path; climate wording: "Something deeper settled /
cracked"). Score ticks inside the same long-term tier stay silent.
`recordMilestone: false` is threaded through growth so regen never plants.

---

## 6. Ambitions — long-term goals 🎯 (Effort: M–L, build LAST)

The current objectives system is short-sighted by construction: propose →
task-gen → background completion, all resolved within a scene. Ambitions add
the missing **future axis** — the five features above are all past/present.

### Design
- **Two tiers, no parallel system.** Ambitions are long-horizon ends ("open
  my own bakery", "win back her trust"); the existing objectives become the
  *means* and keep their proposal/dedup/task-gen/completion machinery
  unchanged. An objective may carry a parent ambition.
- **Sources:** card-authored (a `FrontPorchExtensions` field creators can
  seed), character-proposed during play (rarer, gated, like objectives), and
  user-editable.
- **Progress accrues, never "completes" in one check.** Slow ticks from
  completed objectives, salient events, and Chance Time — with waypoints
  (25/50/75%) that feed the milestones timeline and the journal salience
  kick. Achieving or abandoning an ambition plants a **Growth Ring** — that
  is an identity change, which is exactly what EvolutionService models.
- **No new LLM calls:** the "did this advance an ambition?" question rides
  the existing objective-completion eval.
- **Session-scoping resolved cleanly** (unlike a soul.md-style import, which
  was considered and rejected 2026-07-21): ambition *definitions* are
  identity and live on the card; ambition *progress* is story state and is
  strictly per-chat. Same character, fresh chat = same dreams, new journey.
- **Integrations:** AFK/dynamic responses gain direction (off-screen time
  spent working toward the ambition); dreams seed from ambitions alongside
  fixations (aspiration/anxiety dreams); the recap can mention the arc.
  Fixations stay distinct — short-lived emotional obsessions vs. stable
  long-horizon ends.

### Storage
Prefer zero-schema like everything else in this release: progress as journal
cards (`metadata.kind = 'ambition'`) or session JSON; whether the objectives
table can carry a parent/tier without a column must be verified at build
time. A schema change requires explicit maintainer approval per CLAUDE.md.

### Why build last
It feeds on dreams + milestones (both must exist), touches the Realism eval
pipeline (mandatory 1:1/group parity audit), and its integration points
become concrete rather than speculative once the rest has landed. It also
completes the release story: past (milestones), present (weather, absence),
inner life (dreams), future (ambitions), keepsake (novella).

**Shipped 2026-07-21.** Deviations from the sketch, all deliberate:
1. **Accrual is a tiny dedicated eval at quest completion, not a rider on
   the completion check** — that check is a fragile numbered YES/NO regex
   protocol on local models; overloading it risked the existing parse. The
   intent ("no per-turn LLM cost") is preserved: the ambition eval fires
   only at the rare whole-quest-retired moment, asks for one strict line
   ("NONE" / "2 solid"), and parses forgivingly with a null floor.
2. **Progress cards double as the storage** (`journal_cards`,
   `metadata.kind='ambition'` + `ambition` + `progress`) — zero schema,
   per-chat, per-character, delete-with-chat, diary + timeline visibility
   for free. Waypoints/achievement plant `kind='milestone'` cards + the
   journal/growth salience kick; achievement plants a pinned Growth Ring.
3. **Character-proposed ambitions are deferred** (needs proposal-eval
   surgery); v1 sources are card-authored + user-edited (editor field, one
   per line). Not silent: recorded here + changelog.
4. **No web editor field** — web character authoring exposes no
   FrontPorchExtensions fields today, so desktop-only authoring is the
   existing parity line; ambitions still surface on web via the timeline
   (🧭/🏆 entries).
5. Injection reads a lazy-warmed sync cache on AmbitionService (the growth
   injection-cache pattern) — "just beginning" stages render until the
   first read lands, one build later.

---

## 8. Two-tier memory — expand-memory + RAG dedupe 🧠 (shipped 2026-07-21)

Born from the maintainer's "is RAG even needed anymore?" audit: the Journal
and RAG remember different KINDS of things (lossy emotional distillation vs
lossless verbatim), so instead of deleting one, the seam was tightened into
a two-tier memory — a semantic index (cards) over an episodic store (the
transcript).

**Expand-memory** — the wedding-vows scenario: in a thousand-message chat,
"remember our wedding vows?" makes the character recall the EXACT words plus
how it felt. Mechanism: `buildJournalBlock` computes ONE query embedding
(shared with cold-card resurfacing), scores every injected card against it,
and the single best card above `kMinExpandSimilarity` (stricter than the
resurfacing floor — verbatim costs tokens) expands: its receipts (the
positions cards already store) are fetched from the live message list via a
`getMessageAt` callback, trimmed (`kExpandPerMessageChars`/`kExpandTotalChars`),
and quoted under the block as "the exact words from that moment". Gates:
embeddings present (same floor as resurfacing — no-RAG installs simply never
expand), similarity threshold, and an age gate (`kExpandMinAgeMessages`) so
lines still in the visible transcript are never quoted back. Per-speaker in
groups by construction (the block already is).

**RAG dedupe** — retrieval already excluded in-context messages
(`inContextStart`); now it also excludes spans overlapping the positions the
journal expanded this turn (`RetrievedMemory.excludingPositions`, pure,
current-session only — cross-session sources use a different position
space). The exact lines ride the prompt once, never twice.

Timeline-integrity note: expanded verbatim comes from receipts, and the
regen-invalidation fix (2026-07-21) deletes cards whose receipts were
rewritten — so expansion can never quote a discarded timeline.

---

## Suggested build order & release plan

| # | Feature | Effort | Depends on |
|---|---------|--------|-----------|
| 1 | Weather & seasons | M | — (pure foundation, fully testable) |
| 2 | Absence awareness | S | — |
| 3 | Dreams | S–M | Journal (exists); weather line enriches dream prompts |
| 4 | Milestones timeline | M | Dreams adds `kind='dream'` cards to the feed |
| 5 | Novella export | M | — (independent; biggest UX surface) |
| 6 | Ambitions | M–L | Dreams + milestones (integration points); builds last |

≈ 4–5 weeks of focused work including web parity, tests, and Rawhide.md
copy. Each feature is independently shippable — nothing blocks on anything
else, so nightly users get value incrementally.

**Per-feature done-criteria (per CLAUDE.md):** web_ui counterpart in the same
body of work; `flutter analyze` clean; dead-code audit on touched
`chat_service` paths; 1:1/group parity audit for anything touching Needs or
realism; `docs/Rawhide.md` user-facing bullet; AppColors-only chrome.
