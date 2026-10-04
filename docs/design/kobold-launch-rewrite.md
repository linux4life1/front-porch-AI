# KoboldCpp launch rewrite: let KoboldCpp decide

## Cliff notes (read this; the rest is reference)

**The idea.** Today the app has two ways to start KoboldCpp, and on the
normal one it second-guesses KoboldCpp with its own memory maths. That maths
is wrong when a model doesn't fit and wrong for MoE models. After the
rewrite there is one way: the app always writes a config file and KoboldCpp
fits the model itself.

**What you'll notice as a user**

- "GPU Layers" becomes **Automatic**. A "set layers myself" switch brings
  the number back. Everyone starts on Automatic once.
- The **Auto-Configure** buttons and the "confirm your VRAM" dialog are gone.
- "Generate preset" becomes a **preset editor**: create, edit, rename,
  duplicate, delete, with a plain-words summary of what each preset does.
- Cache compression offers **all five levels**.
- Sliding-window mode is **only offered for models that have it**, and says
  it trades speed for memory. Fast forward stays off in that mode.
- Swapping models says **which model is loading and why**.
- Failures say **what actually went wrong** in plain words.
- Web can **pick a chat preset and see its summary**, and switching model
  from the phone uses the right settings. Editing presets stays on desktop.

**What gets deleted**

- The layer estimate and Auto-Configure code.
- The second launch path.
- The internal batch-override file that shows up as a fake preset.
- The file-linking trick that breaks model swaps on Windows.

**Eight stages, each shippable on its own**

| # | Stage | What you get | Size |
|---|---|---|---|
| 0 | Two quick fixes | Story jobs stop reloading the model every call; stopping KoboldCpp no longer kills one you started yourself | Small |
| 1 | One config reader and writer | Presets written correctly: right GPU, chat template included, all five cache levels | Medium |
| 2 | Launch from a config, always | Automatic memory fitting; MoE handled; estimate code deleted | Large |
| 3 | One rule for "which model loads" | No more wrong model after a restart; phone model switch fixed | Medium |
| 4 | Swaps by config name | Windows swaps work; no pointless reloads; honest wait and messages | Medium |
| 5 | Failure messages and live reload | Plain reasons; changing model tries a live reload before a restart | Medium |
| 6 | Preset editor | Edit, rename, duplicate, delete, summary, draft settings | Large |
| 7 | Web | Chat preset picker and summary | Small |

Stage 8 (optional, later): thinking defaults in presets, splitting across
cards, unload when idle.

**Context handling: the app must choose, not leave it to chance.**
Sliding window on its own is fine. The problem is sliding window together
with fast forward. Today's normal launch sends no context-handling settings,
so on models that have sliding window (Gemma 4, where it makes the model a
hybrid, and Qwen similarly) current KoboldCpp turns it on with fast forward
also on. That is the bad pairing. The rewrite always writes one of the two
safe pairings:

- **Sliding window on, fast forward off.** Less graphics memory. Every
  reply re-reads the whole chat.
- **Sliding window off, fast forward and context shift on.** More graphics
  memory on those models. Replies start fast.

**Default, chosen by the maintainer: sliding window off, fast forward and
context shift on.** The other pairing stays available as a choice for
models that have sliding window. Models without it always get fast forward
and context shift.

**What I can't prove without a real machine**

1. That KoboldCpp will live-reload a config in its admin folder that points
   at a model elsewhere on disk. Stage 4 depends on it. Test this first, on
   Windows and Linux.
2. What automatic fitting picks for a 16 GB model on a 12 GB card, and for a
   MoE model on a 6 GB card.
3. The real out-of-memory text on each platform, for Stage 5's messages.

**Measured on a real KoboldCpp (1.117.1, Apple Silicon, 2026-10-03)**

These answer two of the three unknowns above for macOS. Windows and Linux
are still to be checked.

- A config in the admin folder that points at a model elsewhere on disk
  live-reloads correctly. No file links are needed.
- The reload call answers `{"success": true}` at once, before anything has
  happened. The old model keeps answering for about a second, the server
  then goes away, and it comes back with the new config. So "the reload
  returned" and even "the server answered" do not mean the new model is
  ready. Stage 4 must wait for the server to go down, or for the reported
  context size to change, and only then for it to be ready.
- A second reload sent during that first second is lost. Swaps must be
  one at a time.
- The chat template and the vision file written in a config are active
  after a reload, and a config without a vision file loads without one.
- A config written by the new writer launches and generates, in both
  context modes, with 8-bit and 5-bit caches.
- A manual layer count is honoured (10 of 37 layers when 10 was set).
- KoboldCpp's own exported config stores the card id as text
  (`"usecuda": ["normal", "1"]`), which confirms the number form the old
  generator wrote was ignored.
- **An old key name survives a launch and is lost on a live reload.** A
  config with only `blasbatchsize: 1024` ran at 1024 after a launch and at
  the default 512 after a live reload of the same file. The reload fills in
  every missing default before it converts old names, so the conversion is
  skipped. The same code handles `usecublas`, so a config that names the
  card only under that old key would keep the card at launch and lose it on
  a reload. The writer therefore writes both spellings of a renamed key
  (`usecuda` and `usecublas`, `batchsize` and `blasbatchsize`); with both
  present the value held across a reload. `usehipblas` is not a config key
  at all: it is a command-line alias, and a ROCm build picks its library
  from `usecuda`.
- **Unloading frees the memory with mmap on, off, or with memory lock.**
  KoboldCpp ends the process that holds the model and starts a fresh one.
  With mmap on and the model on the GPU, system wired memory went from
  4.6 GB to 8.8 GB on load and back to 4.6 GB on unload; with memory lock
  on the CPU, 4.6 to 7.8 and back to 4.6. What stays behind is the model
  file in the operating system's file cache (3.3 GB here), which is given
  up the moment anything needs it and is why a second load is quick. With
  mmap on, the process's own footprint was 0.9 GB against 4.5 GB with it
  off.
- **Batch sizes outside the launcher's list work from a config.** The
  command line refuses 1536 ("invalid choice"); a config with 1536 or 8192
  loads and reads a 9,000-token prompt normally. The number set is the
  physical batch; the engine reports a logical batch of twice that.
- **Draft settings pass through a config and survive a reload.** A config
  with a draft model and `draftamount: 6` drafted (67 of 80 tokens accepted,
  none rejected), and still drafted after a live reload to `draftamount: 3`.
  `usemtp: true` on a model with no built-in draft heads loads and
  generates normally.
- In admin mode the engine is five processes, each with a command line
  that begins with the executable's path, so a stop pattern anchored to
  the app's engine folder gets all of them. Unanchored, the same pattern
  also matched another program that merely used a file kept in that folder.
- **Why a swap can end with the wrong model or none (read from the 1.117.1
  source, then seen on the engine).** A reload request is only a note left
  for the engine's manager, which looks for one every 0.2 seconds. When it
  finds one it clears the note, waits half a second, stops the old model
  process, starts the new one, and clears the note again. Two things
  follow. First, the old model keeps answering for up to about a second
  after "success", so the app's readiness check can be answered by the old
  model and the next request goes to it. Second, a request that arrives
  while the manager is in that half second is accepted and then wiped.
  The app sends "unload" and then "reload" back to back, so whether the
  reload survives depends on where the 0.2-second tick falls. A real run
  reproduced it: unload then reload, the app reported ready, and the
  engine still had the old config.

**Cost in test changes.** Stages 2, 3 and 4 each have to rewrite existing
tests, because those tests pin behaviour that is being removed on purpose.

---

## Context

Three read-only reviews on 2026-10-03 found 22 problems in how the app
launches and configures KoboldCpp. They are listed in
`docs/design/local-model-fix-plan.md`, which is the requirements source.
Most trace to two causes: two launch paths that drift apart, and an
app-side memory estimate that is never given the model's real layer count.

Decisions already made by the maintainer:

1. One path: always launch from an app-written config.
2. KoboldCpp decides memory placement; the estimate and Auto-Configure go.
3. Everyone moves to Automatic GPU layers once.
4. Web gets pick, switch and summary. The preset editor is desktop-only
   (explicit deferral, as `docs/web-phone.md` already documents).
5. Sliding-window mode keeps fast forward off (`nofastforward: true`,
   `noshift: true`). Not to be changed.
6. Cache quantisation offers f16, bf16, q8_0, q5_1, q4_0.
7. Sliding window alone is fine; only sliding window with fast forward is
   bad. Every config writes one of the two safe pairings. The default is
   sliding window off with fast forward and context shift on.

## Design

**Settings stay in preferences; a config is derived at launch.** The app's
simple settings (context size, GPU, cache level) are read all over the app,
including the web facade and the prompt budget, so they stay where they
are. At launch a pure function turns them into a `KoboldLaunchConfig`.
User presets are the same type, read and written by the same code.

**Every launch and swap uses a staged "effective config".** The app never
launches or edits a user's `.kcpps` directly. For each role (chat, worker,
story job) it writes a config into the admin folder: the source (preset or
app settings) plus the absolute model path, `jinja: true`, and the resolved
vision file. Launch is `--config <staged> --port N --admin --admindir D`.
A swap reloads the staged file by name. No file links.

**Only these stay on the command line:** port, admin, admin folder.
KoboldCpp protects them from being set by a config.

**Memory placement written into every config:** `gpulayers: -1`, automatic
fit not forced, mmap on, memory lock off. If the user sets a manual layer
count, that number is written, with `moecpu` for a MoE model.

## Stages

### Stage 0: two quick fixes (plan items 1, 11)

- Cache the `LaneHost` per job id next to the existing `_laneSwaps` map in
  `lib/services/llm_provider.lanes.dart`, so
  `_swapLaneHost` in `lib/services/story_pipeline_service.llm.dart` stops
  restoring the chat model on every call.
- `lib/services/kobold_process_control.dart`: kill only the process tree the
  app started, not every process with KoboldCpp's name.
- Tests: two calls on one local story job cause one swap and no restore
  (fails today); the stop command list has no name-wide kill.

### Stage 1: one typed config, one reader, one writer (items 4, 14, 17, 20)

New, under `lib/services/kobold/` with a `kobold.dart` barrel:

- `kobold_launch_config.dart`: the model, with enums for cache level (five),
  context mode, backend, and layer placement (automatic or manual). Keeps
  an `extras` map so settings the app does not manage survive a round trip.
- `kcpps_codec.dart`: pure read and write. Reads any `.kcpps`, including
  ones from KoboldCpp's own launcher, and normalises old key names. A file
  that will not parse returns "broken", not "no model".
- `kobold_capabilities.dart`: version to feature flags, from the existing
  `KoboldBinaryVersion`. Older builds get the older forms.
- `cpu_threads.dart`: thread detection moved out of the generator.

Writer rules: GPU id as text, using the app's GPU setting; both spellings
of a renamed key (see the measured notes: an old name alone is lost on a
live reload, a new name alone is unknown to an old engine); `jinja: true`;
automatic fit not written; cache level as text; sliding-window mode writes
`noswa: false`, `nofastforward: true`, `noshift: true`.

The existing generate dialog switches to the codec.
`lib/services/kcpps_generator_service.dart` is deleted.

Tests: round-trip a real launcher-made file with unknown keys intact; the
old numeric GPU id reads back and re-writes as text; a pinned test that
sliding-window mode always has fast forward and context shift off; all five
cache levels; version gating; a broken file.

### Stage 2: launch from a staged config; delete the estimate (items 3, 4, 5, 6, 17, 22)

- `lib/services/kobold_launch_args.dart` shrinks to four flag groups.
- New `kobold_app_config.dart` (settings to config, pure) and
  `kobold_config_stage.dart` (write temp file then rename; prune old staged
  files).
- New `lib/services/storage/settings/kobold_launch_fields.dart` mixin for
  the new preferences. `backend_settings.dart` is at 495 lines and cannot
  take them.
- New shared widgets `gpu_layers_field.dart` (Automatic or manual) and
  `kv_quant_picker.dart` (five levels), used by Settings, the Model
  Settings dialog and the character-creator setup step.
- GPU backend chosen through the existing `GpuBackendResolver` when the
  stored flags are empty. Today that case launches on CPU only.
- Memory lock defaults off.
- Deleted: `lib/utils/kobold_layer_solver.dart`,
  `lib/services/optimization_service.dart`, the three Auto-Configure blocks,
  the VRAM-confirm dialog, the batch-override file write. A startup cleanup
  removes that file and clears it if it is the active preset.
- `VramEstimator` stays for display only and gains factors for bf16 and
  q5_1.

Tests (pure, real figures): default NVIDIA setup; manual 20 layers on a
dense model; manual layers on Gemma-4-class MoE figures; ROCm; batch 8192;
empty backend flags resolving to a GPU.

Existing tests that must change: `test/services/kobold_launch_args_test.dart`
(most cases assert flags that no longer exist),
`test/utils/kobold_layer_solver_test.dart` (deleted with its subject),
`test/ui/pages/settings_page_launch_state_test.dart` (reads source text;
replaced with a widget test).

Web: Settings shows "Graphics memory: fitted automatically". Rebuild the
bundle.

### Stage 3: one resolver, one launch entry (items 2, 9, 14, 16)

- New `kobold_launch_resolver.dart`: one function decides which model and
  config a launch loads. Rule: the preset's model if it names one and the
  file exists, otherwise the last-used model. The last-used model is always
  updated to match, so the status card, vision lookup, thinking settings
  and web "loaded" marker agree.
- All seven launch sites call it: `settings_page.controls.dart`,
  `settings_page.launch.dart` (two), `model_settings_dialog.local_actions.dart`,
  `setup_service.dart`, `llm_provider.worker.dart`,
  `creator_state.models.dart`, `web/facade/backend_facade.dart`.
- The phone model switch applies the new model's own preset or clears it,
  as the desktop picker already does.
- The model file check now always runs on the resolved model, which catches
  a preset copied from another computer.

Tests: resolver table with real temp files; facade switch between two
models. `test/ui/pages/settings_launch_records_model_test.dart` reads source
text and is replaced with a behavioural test.

### Stage 4: swaps by staged name; one "what is loaded" record (items 7, 8, 10, 15)

- `lib/services/worker_gpu_hosts.dart`: `KoboldProcessHost.restore` stages
  the role's config and reloads it by name. It does nothing when the wanted
  model and config are already loaded.
- New `kobold_resident.dart`: the single record of what is loaded, owned by
  `KoboldService`. `GpuSwapOccupancy` asks it instead of trusting its own
  flag.
- `lib/services/kobold_admin_swap.dart` loses the file-linking and filename
  logic.
- One request per swap, then wait for the real switch. A swap on the one
  engine sends only the reload (the engine replaces its model process
  anyway, so a separate unload first is what opens the window in which the
  reload is lost). It then waits until the old process has stopped
  answering, and only then for the new model to be ready. An unload that
  is wanted on its own waits until the engine reports nothing loaded.
- The lane's swap bookkeeping is cached by lane only, so the chat model it
  will put back and "is the lane's model the chat model" are frozen at
  first use and go stale when the chat model changes mid-run. Both are
  read from the one "what is loaded" record at call time instead.
- After a restart, wait on the real "model ready" signal with a time limit
  scaled to the model's size, not 40 quarter-second checks.
- The existing unused `onStep` hook is connected to the status line.
- "Chat speech was put back" is split by what actually happened.

Tests: reload body names the staged file and no link is created; a second
request for the same model sends nothing; a stale flag does not skip a
needed swap; time limits for 4, 16 and 40 GB files. Cases in
`kobold_admin_swap_test.dart` and `worker_gpu_hosts_test.dart` that pin the
old linking behaviour change.

### Stage 5: failure messages and live reload (items 12, 13, 14, 16)

- New `kobold_launch_failure.dart`: classify an exit during load (out of
  memory, unreadable model, unreadable config, a setting an old engine
  rejects, port in use) and give a plain message for each.
- Changing model or preset while running tries a live reload first, then a
  restart. Fixed one-second and five-second waits become waits on the real
  event.
- Read KoboldCpp's real context size after load and use it for the prompt
  budget.
- No automatic retry with fewer layers: KoboldCpp owns placement now. The
  message offers a smaller context or stronger cache compression.

The out-of-memory patterns ship only after real log text is captured.

### Stage 6: the preset editor (items 4, 17, 18, 19, 20)

- `lib/ui/dialogs/kcpps_editor_dialog.dart` (+ parts) replaces
  `generate_kcpps_dialog.dart`.
- New `kcpps_library.dart` (list, save with a collision result, rename,
  duplicate, delete, with reference fix-ups) replaces four duplicate
  scanners. New `kcpps_summary.dart` and `kcpps_summary_card.dart`.
- Features: create from current settings or load an existing file; name
  field with an overwrite prompt; plain labels with one line each; range
  checks with messages; five-level cache picker; sliding window shown only
  when `GGUFModelInfo.slidingWindow` is set, with its speed cost stated;
  vision file with "keep on CPU"; a note when a preset carries settings the
  app does not manage; "use the app's own settings".
- The batch field stops overwriting what the user typed. It stays a free
  number: sizes the launcher does not list (1536, 8192) work from a config,
  so the range check only refuses values the engine cannot use.
- Draft settings (moved here from Stage 8): a draft model file, "use the
  model's built-in draft heads" (`usemtp`), and tokens drafted per step
  (`draftamount`, any whole number, KoboldCpp's default is 4). One number
  serves both kinds of drafting. The built-in switch is offered when the
  model file says it has draft heads (`<arch>.nextn_predict_layers` above
  zero; confirm against a real model with heads before gating on it). The
  summary says that drafting switches request batching off and should not
  be combined with a vision file.
- Turning on a manual layer count clears a forced automatic fit the preset
  carried, since KoboldCpp otherwise ignores the count and the MoE setting.
  The reader already notes this when it opens such a file.

Tests: library operations on a temp folder; a widget test that edits,
saves and reopens a preset; summary lines for three real files.

### Stage 7: web (item 21)

- `lib/services/web/facade/kcpps_facade.dart` and routes: list presets with
  summaries, set the chat preset. Writes are gated like the worker preset
  and limited to the engine folder.
- Web chat-preset picker and summary card. No editor (deferred).
- A journey in `web_ui/e2e/journeys.spec.ts`.
- Update `docs/web-phone.md` and `docs/user-guide.md`.
  (`docs/moe-vram-estimation.md` was marked superseded in Stage 2, with the
  code it described.)

## Migration for existing users

No stored setting is deleted. New ones are added beside the old.

| Stored today | After |
|---|---|
| GPU layers number | Everyone on Automatic. The old number is remembered and pre-fills "set layers myself". A one-time note says the change happened. |
| Context size, batch size | Unchanged. |
| Backend flags and GPU id | Same card, written correctly. Empty flags now resolve to a GPU. |
| Memory lock | Off unless the user turned it on. Forced off, with a note, when layers are automatic or the model is MoE. |
| Cache level 0 / 1 / 2 | Read as f16 / q8_0 / q4_0. |
| Active preset, model-to-preset map, vision map, worker paths | Unchanged. |

The migration is one pure function over a key-value map, tested with real
snapshots: fresh install, an Auto-Configured NVIDIA user, a CPU-only user,
a ROCm user.

## Reuse (already in the repo)

- `GpuBackendResolver` for choosing a backend when none is stored.
- `GGUFModelInfo.isMoe` and `.slidingWindow` (`lib/utils/gguf_model_info.dart`).
- `KoboldBinaryVersion` (`lib/services/kobold_binary_version.dart`).
- `ModelFileCheck` for the pre-launch file check.
- `KoboldAdminSwapLock` and `KoboldProcessHost`, already injectable.
- `WorkerBackendFields` as the pattern for a settings mixin.
- `VramEstimator` for the display-only memory figure.

## Verification

Per stage:

1. `flutter analyze` on changed files; `dart format` on edited files only.
2. New tests proven red by removing the product change, then green.
3. `flutter test --concurrency=4 --exclude-tags golden`.
4. `./scripts/ci-local.sh all` before any push.
5. For web changes: `cd web_ui && npm run lint && npm test && npm run build`.

On a real machine, before Stage 4 is built:

1. Start KoboldCpp with an admin folder. Put a config in it whose model
   path points elsewhere on disk. Call the reload. Confirm it loads, on
   Windows and Linux.
2. Confirm the chat template and vision file written in a config are active
   after a reload.

After Stage 2, in the running app:

1. Load a model larger than the card with nothing changed. Check it loads
   and generates at a usable speed.
2. Load a MoE model on a small card. Check memory use and speed.
3. Turn on "set layers myself", enter a number, restart, and check that
   number is used.

After Stage 4: run a Porch Stories job on a local model and check the run
log shows the model loading once, not once per call.
