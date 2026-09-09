# Waifu Coder architecture judo — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan wave-by-wave. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> After this plan is accepted, copy it to `docs/superpowers/plans/2026-09-10-waifu-coder-architecture.md` and the spec body to `docs/superpowers/specs/2026-09-10-waifu-coder-architecture.md`. Plan mode can only write this file.

**Goal:** Collapse Waifu Coder internals to one history, one turn object, one fill number, and one permission `decide(call)` — without changing the product (Plan/Build/Yolo, Jail/Disk, verify-before-speech, desktop-only coworker loop).

**Architecture:** Keep the island under `lib/services/waifu/` + `lib/ui/waifu/`. Do not construct `ChatService`. Seven shippable waves; each leaves the app runnable. Extract *before* adding a line to harness (496), permissions (485), or page (485).

**Tech Stack:** Flutter/Dart, existing `generateWithTools`, AppColors, JSON under the data dir. No new sidecars, no Drift schema, no `web_ui/`.

**Spec:** Amends `docs/superpowers/specs/2026-09-05-waifu-coding-design.md`. The holes this plan closes are the 2026-09-10 landscape review (three books of truth, two histories, four compact meters, regex nanny, nine permission gates, repeated UI chrome).

## Global Constraints

- Desktop only. No `web_ui/` Waifu surface. Path-complete chat matrix N/A.
- No `ChatService`, Realism, Journal, Needs, RAG on this pipeline.
- Every Dart file under 500 lines. No `lib/` file at 1,000.
- **Do not add a method** to `waifu_harness.dart`, `waifu_permissions.dart`, or `waifu_page.dart` without extracting first.
- Barrel imports. `dart format` only files you touched. Never `dart format .`.
- New tests in **new files** when possible. Changing an existing test needs written rationale (test-integrity). Prove each new guard red then green.
- Hostile self-review before claiming a wave done. Green suite is not a second look.
- Do not run `dart format .`, edit `pubspec.yaml`, or destructive git.
- Honesty / sit-down copy stays blunt. Do not kindergarten it.
- Yolo skips the **ask**, not secrets/wipe/jail. Do not merge Jail into Plan/Build/Yolo.
- MCP stays unscoped (cannot live behind the folder jail). Plan denies, Build asks, Yolo allows — said once in `decide`, not a name regex plus a warning.
- Commit each wave on Rawhide with conventional messages. Do not push unless asked.

---

## What we are not doing

- Rewriting personality, honesty, or sit-down copy.
- Making local small GGUFs into Claude.
- A second MCP admin UI inside Waifu (connecting servers stays Settings).
- Growing `_YamlMini` in `waifu_plan_codec.dart`.
- An eleventh `WaifuFinalAction` or a fourth permission gate “just for this bug.”
- Injecting a full folder listing into every prompt (we do not do this today; do not add it).

---

## Re-reads: what is required vs what is waste

**Required (keep):** After she **writes/edits** a path, she must **re-read that path** before wrap-up. The bytes on disk changed. That is verify-before-speech, once per mutation, not forever.

**Waste (stop):** Listing the tree or reading `Foo.swift` again when that read is **still in the prompt** and she has **not** mutated it since. Coding models are trained to “read first.” We currently persist dumps across sends but never say “don’t fetch what you already have,” so she burns tokens (and the bar) on the same glob/read every send.

**Rule to ship:**

| Situation | What she should do |
|---|---|
| Just wrote/patched `Foo.swift` | Re-read `Foo.swift`. Required. |
| `Foo.swift` already in history, not mutated this send | Do not `read`/`glob` it again. Prompt already has it. |
| History was compacted and that read was dropped | `read` again. Correct. |
| User asked “what’s in the folder now?” | `glob` once. |

**Where it lands:**

- Wave 3: one line on the builtins cue — do not re-read or re-glob a path whose contents are still in this prompt unless you just wrote it.
- Wave 5: dispatch-level skip. A `read` of an unmodified path that already has a `kind: tool` result returns a **short stub** (`already in history, unchanged`) instead of a second full dump. Same for `glob` if the last glob is still in history and no writes landed since. Tests pin: second `read` of the same path without a write does not double the file body in the prompt.

---

## Target types (lock these names; later waves consume them)

```dart
// Wave 2 — session.dart
enum WaifuMsgKind { user, assistant, tool, recap }

class WaifuMessage {
  const WaifuMessage({
    required this.kind,
    required this.text,
    this.chips = const [],
    this.reasoning = '',
    this.thinkingStartMs,
    this.thinkingMs = 0,
    this.imagePath,
    this.toolName,
    this.toolOk,
  });
  final WaifuMsgKind kind;
  final String text;
  final List<WaifuToolChip> chips;
  final String reasoning;
  final int? thinkingStartMs;
  final int thinkingMs;
  final String? imagePath;
  final String? toolName;
  final bool? toolOk;
  bool get isUser => kind == WaifuMsgKind.user;
  bool get hidden => kind == WaifuMsgKind.recap;
}

// Wave 3 — new waifu_turn.dart (not the 390-line regex file)
enum WaifuPhase { tools, verify, speak, done }

class WaifuTurnReceipt {
  const WaifuTurnReceipt({
    this.writes = const [],
    this.mutatedPaths = const {},
    this.readPaths = const {},
    this.tested = false,
    this.todoWriteOk = false,
    this.successfulTool = false,
  });
  final List<WaifuWriteRecord> writes;
  final Set<String> mutatedPaths;
  final Set<String> readPaths;
  final bool tested;
  final bool todoWriteOk;
  final bool successfulTool;
  bool get reviewed =>
      mutatedPaths.isEmpty ||
      mutatedPaths.every((p) =>
          readPaths.any((r) => waifuReadVerifiesMutate(r, [p])));
  bool get verified => reviewed && tested;
}

// Wave 4
class WaifuCall {
  const WaifuCall({
    required this.tool,
    required this.args,
    required this.mutating,
    this.path,
    this.command,
  });
  final String tool; // canonicalWaifuToolName already applied
  final Map<String, dynamic> args;
  final bool mutating;
  final String? path;
  final String? command;
}

sealed class WaifuDecision {}
class WaifuDeny extends WaifuDecision { WaifuDeny(this.reason); final String reason; }
class WaifuAsk extends WaifuDecision { WaifuAsk(this.why); final String why; }
class WaifuAllow extends WaifuDecision { const WaifuAllow(); }
```

---

## Wave order (do not skip)

```
1 compact between sends + one fill
2 recap kind
3 receipts, not English
4 decide(call) after jail
5 one history list          ← needs 1 + 2
6 thin page + chrome        ← needs 1 (bar); MCP live catalog can start after 4
7 plan JSON, one todo file, nested receipt  ← needs 3
```

Each wave: tests first → implement → red-proof one guard → `flutter analyze` on touched paths → per-file `dart format` → hostile self-review → commit.

---

# Wave 1 — Compact between sends + one fill number

**User-visible:** The sidebar bar and auto-fold use the same number. Reload keeps the window size (277k stays 277k). She does not fold the transcript in the middle of a tool loop. Hot bar can start compact.

**Why first:** Stops the cursor/list fight without rewriting history kinds yet. Smallest judo that prevents the next compact bug.

**Files:**
- Modify: `lib/services/waifu/waifu_compact.dart`
- Modify: `lib/services/waifu/waifu_harness_compact.dart`
- Modify: `lib/services/waifu/waifu_harness_turn.dart` — delete `await _maybeCompact()` from inside `_loop`
- Modify: `lib/services/waifu/waifu_harness.dart` — `_maybeCompact()` only after `_loop()` in `send()` (already there)
- Modify: `lib/services/waifu/waifu_store.dart` — persist `contextBudget`
- Modify: `lib/ui/waifu/waifu_context_bar.dart` — tap when fill ≥ 75% calls compact
- Modify: `lib/ui/waifu/waifu_page.dart` — wire bar `onCompact` only if you can do it without growing the file; otherwise add a 20-line callback on the bar and pass it from the existing `_applyLocalSlash` compact path via a one-line closure in the sidebar constructor (count lines first; extract if page would exceed 500)
- Test (new): `test/services/waifu/waifu_compact_between_sends_test.dart`
- Test (new): `test/services/waifu/waifu_fill_number_test.dart`

**Interfaces:**
- Consumes: `session.tokensUsed`, `session.tokensFromApi`, `session.contextBudget`
- Produces:
  - `int waifuFillUsed(WaifuBudgetSnapshot snap)` — the number the bar shows
  - Auto-compact uses **that same snapshot**, not a second chars÷4 pass that ignores API usage
  - `waifuShouldCompact(used:, budget:)` remains the 75% line

### Task 1.1 — One snapshot drives bar and fold

- [ ] **Write failing tests** in `waifu_fill_number_test.dart`:
  - When `totalTokens: 9000` is passed, `waifuMeasureRequest(...).used == 9000` and `fromApi == true` (already true; keep).
  - New: `waifuShouldCompact` on that snapshot, not on a re-guessed chars÷4 of system+prompt.
  - New: store round-trip `contextBudget: 277518` reloads as 277518, not 8192.
- [ ] Persist `contextBudget` in `waifu_store.dart` `_sessionMap` / load (mirror `tokensUsed`).
- [ ] In `_maybeCompact`, if `session.tokensFromApi && session.tokensUsed > 0`, compact when `waifuShouldCompact(used: session.tokensUsed, budget: session.contextBudget)` — do **not** call `_measureLive()` solely to decide fold. Still prune traces. Still `_measureLive()` after fold to refresh the bar if API flag was cleared.
- [ ] Red-proof: temporarily ignore `tokensFromApi` in `_maybeCompact`; the new test goes red; restore.
- [ ] Commit: `fix(waifu): compact uses the same fill number as the context bar`

### Task 1.2 — Compact never runs inside `_loop`

- [ ] **Write failing test** `waifu_compact_between_sends_test.dart`:
  - Scripted LLM: first call returns a write, second returns speech.
  - Pre-seed 20 transcript messages + `contextBudget: 100` so fill is hot.
  - `send('keep going')` must use the **first** scripted reply as the **task** (tools/speech), not as a recap. `llm.calls.first.systemPrompt` contains `kWaifuPreamble`, not `kWaifuCompactSystem`.
  - After send, if compact ran, it is a call **after** the wrap-up, not before the first generate.
- [ ] Remove `await _maybeCompact();` from the top of `_loop` in `waifu_harness_turn.dart`. Keep prune-only if needed: extract `_pruneTraces()` call without LLM compact (already `_pruneTraces` inside `_maybeCompact`; add `_pruneTraces()` at loop start if dumps can blow a single turn — that is allowed; LLM recap is not).
- [ ] Keep `await _maybeCompact();` after `_loop()` in `send()` and in public `compact()`.
- [ ] Red-proof: put `_maybeCompact` back at loop start; first call’s system prompt is the compact system; test red; restore.
- [ ] Commit: `fix(waifu): compact between sends, not inside the tool loop`

### Task 1.3 — Hot bar starts compact

- [ ] `WaifuContextBar` takes `VoidCallback? onCompact`. When `hot` (fill ≥ `kWaifuCompactAt`) and callback non-null, the bar is a `GestureDetector` / `InkWell` (porch amber, not blue). Semantics: “Fold old turns”.
- [ ] Sidebar passes `onCompact: () { harness.compact(); }`.
- [ ] Widget test in new `test/ui/waifu/waifu_context_bar_compact_test.dart`: fill 0.8, tap bar, callback fired. Fill 0.1, tap does nothing (or still no compact).
- [ ] Commit: `feat(waifu): hot context bar folds old turns`

**Wave 1 acceptance:** `send` with a hot window does not steal the first model call for recap. Reload keeps 277518. Bar and `_maybeCompact` agree. Harness file did not grow (loop line is a deletion).

---

# Wave 2 — Recap is a kind

**User-visible:** Recap never appears as you or as Iris. Prompt says `Session recap`. Old sit-downs still heal.

**Files:**
- Modify: `lib/services/waifu/waifu_session.dart` — `WaifuMsgKind`; `isUser`/`hidden` become getters
- Modify: `lib/services/waifu/waifu_coworker_prompt.dart` — `waifuPromptSpeech` switches on `kind`
- Modify: `lib/services/waifu/waifu_compact.dart` — drop prefix OR for detection; `waifuIsPromptRecap` is `kind == recap`
- Modify: `lib/services/waifu/waifu_harness_compact.dart` — construct `kind: recap`
- Modify: `lib/services/waifu/waifu_store.dart` — persist `kind`; heal `isUser`+prefix → recap
- Modify: every `WaifuMessage(isUser: true/false, ...)` construction site (grep `WaifuMessage(`)
- Test: extend via **new** `test/services/waifu/waifu_msg_kind_test.dart` (do not weaken `waifu_prompt_roles_test.dart`; update it only if the subject is now `kind`)

**Migration:** `WaifuMessage({required this.kind, ...})`. Helper constructors to avoid churn:

```dart
factory WaifuMessage.user(String text, {String? imagePath}) =>
    WaifuMessage(kind: WaifuMsgKind.user, text: text, imagePath: imagePath);
factory WaifuMessage.assistant(String text, {List<WaifuToolChip> chips = const [], ...}) =>
    WaifuMessage(kind: WaifuMsgKind.assistant, text: text, chips: chips, ...);
factory WaifuMessage.recap(String text) =>
    WaifuMessage(kind: WaifuMsgKind.recap, text: text.startsWith(kWaifuCompactPrefix) ? text : '$kWaifuCompactPrefix\n$text');
factory WaifuMessage.tool({required String name, required String output, required bool ok}) =>
    WaifuMessage(kind: WaifuMsgKind.tool, text: output, toolName: name, toolOk: ok);
```

Keep `isUser` getter so UI `message.isUser` and existing tests compiling against `isUser:` named ctor can migrate in this wave (replace named `isUser:` with factories).

- [ ] Grep `WaifuMessage(` under `lib/` and `test/` — every site uses a factory or `kind:`.
- [ ] Prompt: recap → `Session recap (not a user message, not spoken by $coworkerName):`; user → `User:`; assistant → `$name:`; tool → `[tool $name ${ok ? 'ok' : 'error'}]\n$output` (Wave 5 will rely on this).
- [ ] `_isLiveAssistantAt`: `kind == assistant` (not `!isUser && !hidden`).
- [ ] Store: write `kind`; read kind if present; else heal prefix/hidden/isUser as today.
- [ ] Tests: recap prompt is not `User:` / `Iris:`; user line still `User: keep going`; load heal of old JSON.
- [ ] Commit: `fix(waifu): recap is a message kind, not a hidden user line`

**Wave 2 acceptance:** `waifuIsPromptRecap` does not sniff `[Session compact]` as the only source of truth; `kind == recap` does. A user message whose text happens to start with that prefix stays a user message **unless** it was stored as hidden recap (heal only `hidden == true` OR explicit kind, **not** raw user text). **Fix the current heal:** do not treat a typed `[Session compact]` user send as recap. Heal `hidden: true` or `kind: recap` only.

---

# Wave 3 — Receipts, not English

**User-visible:** Same rule — she still cannot wrap up a code change with “done” unless a write landed and verify passed. Fewer wrong retries because we stop parsing the bubble.

**Files:**
- Create: `lib/services/waifu/waifu_turn.dart` — `WaifuPhase`, `WaifuTurnReceipt`, small `WaifuTurn` (live bubble pointer + receipt + `phase`). Stay under 400 lines.
- Modify: `lib/services/waifu/waifu_turn_contract.dart` — **shrink** to adapters if tests still import `decideFinal`; do not grow it. Prefer moving tests to the new type in a **new** test file `test/services/waifu/waifu_turn_receipts_test.dart` and leaving old contract tests until the last call site is gone (one commit that deletes `decideFinal` + 10-way switch together).
- Modify: `lib/services/waifu/waifu_harness_turn.dart` — `_loop` becomes:

```dart
// after generate:
if (calls.isNotEmpty) {
  for (final call in calls) { await _runTool(...); }
  continue;
}
switch (turn.phase) {
  case WaifuPhase.tools:
    if (turn.receipt.needsMutation && !turn.receipt.didMutate) { cue = retryMutate; continue; }
    turn.phase = turn.receipt.needsVerify ? WaifuPhase.verify : WaifuPhase.speak;
    continue;
  case WaifuPhase.verify:
    if (!turn.receipt.verified) { cue = retryVerify; continue; }
    turn.phase = WaifuPhase.speak;
    continue;
  case WaifuPhase.speak:
    if (body.trim().isEmpty) { cue = retrySpeech; continue; }
    _say(body);
    turn.phase = WaifuPhase.done;
    return;
  case WaifuPhase.done:
    return;
}
```

`needsMutation` = user asked for a file change **or** mode is Plan (plan file). Detect file-change from **receipts after tools**, not from `waifuTaskRequestsFileChange` on the user sentence as the *only* gate. Keep the sentence heuristic only as a **hint** to wait for a write on the first empty wrap-up (one retry), then fail. Do not keep `waifuLooksGenericCompletion` as a hard fail if receipts are complete — if she wrote+verified, “done” in character is accept.

- Delete (this wave or immediately after call sites die): `waifuLooksTodoReceiptClaim` as a gate (todo receipt is `todowrite` ok on the receipt). `checkInWrapUp` if still unread. Chip scan `waifuTurnHasTodoWriteReceipt` if `noteResult` already sets the flag.
- Check-in: after N file writes, set `phase = speak` (verify first if required), do not invent a second speechOnly paint flag. Tools stay available for verify.
- Builtins cue (one sentence on `kWaifuBuiltinsCue`): do not `read`/`glob` a path whose contents are still in this prompt unless you just wrote it. Re-read after mutate stays required.
- `speechOnly` advertised-tools empty list: only when `phase == speak` **and** receipts already satisfied. One place.

**Tests (new file):**
- Mutate without verify → cannot accept wrap-up (existing contract; re-pin against receipt).
- Write + re-read + passing `dart analyze` → “Hmph. It’s in.” accepts even if the line is short.
- “please write hello.txt” + no write → retry then failMutation.
- Todo claim without `todowrite` → retryTodoWrite then fail.
- Check-in after 6 writes: no 7th write in that batch; verify still allowed.

- [ ] Implement `WaifuTurn` with an actual `WaifuMessage live` field (the bubble object), not `_stepAt`. Harness `_liveAssistant` becomes `turn.live ??= WaifuMessage.assistant('')` appended once. Compact between sends (Wave 1) means compact no longer runs while `turn.live` is mid-stream.
- [ ] Replace `_stepAt` integer if you can without growing harness — live bubble on `WaifuTurn` **is** the judo for hole #1. Do it here, not in Wave 5.
- [ ] Commit: `fix(waifu): turn wrap-up is receipts and phases, not a regex nanny`

**Wave 3 acceptance:** `decideFinal` has no remaining production call site. `_loop` has no 10-way enum switch. `_stepAt` is gone or unused. Harness did not grow (logic in `waifu_turn.dart` + turn part).

---

# Wave 4 — `decide(call)` after jail

**User-visible:** Same Allow / Deny / Always. `ls` still does not ask. In-porch Build writes still do not ask. Unknown MCP does not silently become a file tool. Plan + MCP mutation is deny or ask, never silent allow.

**Files:**
- Create: `lib/services/waifu/waifu_deny.dart` — move `waifuDeniedCommand`, `_rmDangerous`, `waifuShellWords`, wipe targets, **one** protected-tree list (union of today’s OS-write + wipe roots; document the union in the class doc). Recursive-flag helper **once**.
- Create: `lib/services/waifu/waifu_call.dart` — `WaifuCall.parse(name, args)` using `canonicalWaifuToolName` + one alias table (`command`/`cmd`, `path`/`file_path`/`file`, `contents`/`content`/`text`).
- Modify: `lib/services/waifu/waifu_permissions.dart` — **shrink** to doom-loop, Always-this-session, and:

```dart
WaifuDecision decide(WaifuCall call, {required WaifuPathMode pathMode}) {
  // 1 hard floor (deny.dart) — even Yolo
  // 2 scope: jail.resolveLive; Plan overlay: only .waifu/plans/*.md writes
  // 3 consent: plan / build / yolo
}
```

Target ≤ 200 lines after extract.

- Modify: `waifu_bash.dart` — `mutating` is command class (redirect / write / rm / pkg / unknown), **not** `waifuPlanBashDenied != null`. Plan allowlist stays Plan-only.
- Modify: `waifu_harness.dart` `_runTool` — parse `WaifuCall` once; `switch (permissions.decide(call))`; drop the second live Plan block if `decide` already used resolved path.
- Modify: `waifu_harness_dispatch.dart` — unknown name → `WaifuToolResult.error('unknown tool $name')`. MCP-blocked names are **aliases** via `canonicalWaifuToolName` only when they map to a local tool; otherwise error. No `fs.dispatch` fallback for garbage names.
- Modify: `waifu_mcp_filter.dart` — `null` mutation hint in Plan = deny; in Build = ask (mutating unknown).
- Modify: `waifu_harness_spawn.dart` — Explore child is `consent: read` / `exploreOnly: true` **without** forcing `WaifuMode.plan` unless the parent is Plan. Do not encode read-only as Plan.
- Test (new): `test/services/waifu/waifu_decide_test.dart`

**Tests:**
- Yolo + `rm -rf /` still deny.
- Build + `ls` → Allow (read-only bash).
- Build + in-porch `write` → Allow (no ask).
- Build + `rm file` inside porch → Ask (bash mutate).
- Plan + MCP `create_issue` → Deny.
- Plan + unknown MCP name → Deny (not Allow).
- Dispatch `not_a_tool` → error string, not a file write.
- Wipe list: `C:\Windows\System32` recursive and `/tmp` recursive both deny (union).

- [ ] Red-proof: restore MCP→fs fallback; unknown-name test goes red; restore.
- [ ] Commit: `fix(waifu): one permission decide() after jail; unknown MCP is not a file tool`

**Wave 4 acceptance:** `permissions.dart` well under 500. One protected-tree list. `waifuBashMutates` does not call `waifuPlanBashDenied`. Grep `fs.dispatch` in dispatch default = only canonical file tools.

---

# Wave 5 — One history list

**User-visible:** After a fold, old file reads are either in the recap or gone — not a silent sidecar novel. Prompt heading “this turn” dies.

**Depends on:** Wave 1 (compact between sends), Wave 2 (kinds).

**Files:**
- Modify: `waifu_session.dart` — delete `toolTraces`.
- Modify: `waifu_harness.dart` — on tool result, `transcript.add(WaifuMessage.tool(...))` instead of `session.toolTraces.add`.
- Modify: `waifu_coworker_prompt.dart` — walk `transcript` kinds; tool lines as in Wave 2; no `toolTrace:` parameter (or ignore if empty for one commit).
- Modify: `waifu_compact.dart` / harness compact — prune **tool-kind messages** older than protect window; LLM recap is given **speech + stubbed tool names/paths**; compact the list the model reads.
- Modify: `waifu_store.dart` — stop writing `toolTraces`; on load, if `toolTraces` present, convert each string to `WaifuMessage.tool` and drop the field.
- Test (new): `test/services/waifu/waifu_history_list_test.dart`

**Tests:**
- After `read` + wrap-up, next `send` prompt contains a `kind: tool` line, not a “Tool results for this turn” dump of a parallel list.
- Compact folds tool-kind messages; recap prompt includes the tool names that were dropped.
- Old session JSON with `toolTraces` still loads.
- Duplicate `read` of the same path with **no** write in between returns a short `already in history, unchanged` stub; the file body appears **once** in the next prompt. After an `edit` of that path, `read` returns the new bytes (verify still works).
- Duplicate `glob` with no writes since the last glob stubs the same way.

- [ ] Commit: `fix(waifu): one history list; tool results are messages`

**Wave 5 acceptance:** grep `toolTraces` in `lib/` is zero (or one tombstone comment). Compact cannot disagree with the prompt’s contents.

---

# Wave 6 — Thin page + one chrome

**User-visible:** One place to change Plan/Build/Yolo. Jail/Disk is a sit-down receipt, not a fake live chip. One MCP consent; catalog updates when you connect Docker. Leave Stop. Hot bar already folds (Wave 1). Resume a porch does not re-quiz honesty if that porch already consented.

**Files:**
- Create: `lib/ui/waifu/waifu_session_scope.dart` (or `waifu_harness_bind.dart`) — factory that today’s `_harnessOf` duplicates (injected llm vs `LlmServiceWaifuLlm`). **Move both constructor copies out of the page.**
- Modify: `waifu_page.dart` — layout + callbacks; `dispose` calls `harness.abort()`. Must shrink, not grow.
- Modify: `waifu_harness.dart` — `mcpTools` / `mcpCall` are **functions or re-read each generate**, not a list frozen at construction. `_advertisedTools` calls `mcpToolsOf?.call() ?? mcpTools` each step.
- Modify: `waifu_mcp_bind.dart` + page — pass `List<Map> Function() mcpToolsOf` that reads `waifuMcpBind(context)` live (or harness holds a callback).
- Modify: `waifu_session_chrome.dart` — mode chips are display-only (or remove duplicates). Sidebar `WaifuModeBar` is the only control.
- Modify: `waifu_scope_badge.dart` — not a ChoiceChip twin of mode; static receipt “Jail” / “Disk”.
- Modify: `waifu_mcp_panel.dart` — one checkbox “Let her use MCP”. Drop “from Settings” lie. Docker connect can stay as a shortcut but must refresh catalog.
- Modify: `waifu_plan_stage.dart` — empty plan is a one-line hint, not 280px.
- Modify: wizard sit-down / new-session — if `WaifuStore` already has pathMode + honesty for this folder, skip re-quiz on “new session in this folder” (resume already skips; make them share that rule).
- Test (new): `test/ui/waifu/waifu_chrome_once_test.dart` — one ModeBar control; scope badge not tappable to change pathMode.
- Test (new): `test/services/waifu/waifu_mcp_live_catalog_test.dart` — after construction, changing the tools callback changes advertised names on the next generate.

- [x] Commit: `fix(waifu): one mode control, live MCP catalog, Stop on leave`

**Wave 6 acceptance:** grep `WaifuHarness(` in `waifu_page.dart` is zero (factory file owns it). `dispose` aborts. Ticking MCP after sit-down without leaving the page affects the next send.

---

# Wave 7 — Plan JSON, one todo file, nested receipt

**User-visible:** Plan titles with colons do not corrupt the file. Todos do not vanish vs plan steps fighting. Nested explore/general does not steal the parent’s wrap-up.

**Files:**
- Modify: `waifu_plan_codec.dart` — encode/decode **JSON** (or JSON-in-fenced-block in the markdown body). Delete `_YamlMini` growth. Keep a **read** path for old YAML plans (one migration function, then write JSON on next save).
- Modify: todos — `.waifu/todos.json` is source of truth. `saveLast` does not store a second full copy (store a pointer / omit and always `waifuLoadTodos`). Plan accept **merges** steps into todos, does not blindly wipe in-progress items the user already had.
- Modify: `waifu_harness_spawn.dart` — `_runNested` returns `WaifuTurnReceipt` + speech string. Parent `absorb(receipt)`. Child must not share a colliding generate with parent (same as today sequentially is OK; do not compact/abort the parent mid-child). Child does not get `store.saveLast` that overwrites parent todos.
- Test: plan title `fix: login` round-trips. Nested mutate does not clear parent `readPaths` unless absorb copies receipts correctly (pin the Wave 3 absorb behavior).
- [x] Commit: `fix(waifu): plan JSON, one todo file, nested work returns a receipt`

---

## Cap-file rule (every wave)

Before commit, `wc -l` on:

- `lib/services/waifu/waifu_harness.dart` (must not exceed 496; prefer down)
- `lib/services/waifu/waifu_permissions.dart` (must drop in Wave 4)
- `lib/ui/waifu/waifu_page.dart` (must drop in Wave 6)

If a wave would add lines, extract first in that same wave.

---

## Mapping review findings → waves

| Review hole | Wave |
|---|---|
| Three books of truth / `_stepAt` | 3 (live bubble on `WaifuTurn`), 1 (stop compact under the cursor) |
| Two histories / `toolTraces` | 5 |
| Recap hidden+isUser+prefix | 2 |
| Four compact meters / reload 8192 | 1 |
| Mid-loop compact | 1 |
| Regex nanny / 10-way enum | 3 |
| Nine permission gates / MCP→fs / two OS lists | 4 |
| Duplicate chrome / MCP frozen / no Stop on leave | 6 |
| Plan YAML god / todos twice / nested full loop | 7 |
| Cap files choosing architecture | every wave’s extract rule |
| Re-glob / re-read of unchanged files still in history | 3 (cue) + 5 (dispatch stub) |

---

## Hostile self-review of this plan

- Wave 5 is the riskiest user-visible prompt change (tool results in history will **raise** context vs today’s “dumps vanish next send”… wait: today dumps persist in `toolTraces` across sends already. Wave 5 makes that honest in the list compact walks. Fill may look similar; compact must actually drop tool-kind messages).
- Wave 3 must not weaken verify-before-speech. “done” after receipts is accept; “done” before write is still fail.
- Wave 2 heal must **not** classify a user who types `[Session compact]` as recap (the current prefix heal is too broad).
- Wave 4 union of OS roots is stricter (more denies). That is intended; do not silently allow `/tmp` recursive rm.
- Did not schedule a “make local GGUF good” wave — out of scope per 2026-09-05 spec.

---

## Execution

After you accept this plan:

1. Copy spec + plan into `docs/superpowers/specs/` and `docs/superpowers/plans/` (plan mode could not write those paths).
2. Start **Wave 1 only**. Do not parallelize waves — they touch the same three cap files.
3. Choose: subagent-driven (fresh agent per task, review between) or inline in this session.

**Which wave to start?** Default: Wave 1.
