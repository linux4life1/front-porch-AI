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
- The app's KoboldCpp **answers this computer only**. It used to listen on
  every network the computer was on.

**What gets deleted**

- The Auto-Configure layer picker (the code that chose a GPU layer count
  for launches without a preset). Not the VRAM usage estimate: see "The
  estimate is a guess, not a setting" under Design.
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
| 6 | Preset editor | Edit, rename, duplicate, delete, summary | Large |
| 7 | Web | Chat preset picker and summary | Small |

Stage 8 (built): the draft settings left over from Stage 6, the thinking
cap keyed on the model loaded, presets over several cards kept and
explained, and unload when idle.

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
models that have sliding window, in the preset editor. Auto mode (the app's
own settings, no preset) always writes the default: it once kept a stored
switch for the other pairing, but nothing ever set it, so it was removed.
Models without sliding window always get fast forward and context shift.

**What I can't prove without a real machine**

1. That KoboldCpp will live-reload a config in its admin folder that points
   at a model elsewhere on disk. Stage 4 depends on it. Test this first, on
   Windows and Linux.
2. What automatic fitting picks for a 16 GB model on a 12 GB card, and for a
   MoE model on a 6 GB card.
3. The real out-of-memory text on each platform, for Stage 5's messages.

**Status of these three (2026-10-04).** Item 1 is proven on macOS (below).
Item 2 was measured on Linux with a 16 GB AMD card and in the original
author's log from a 6 GB NVIDIA card (next section). Item 3 is partly
captured: ROCm reports "ROCm error: out of memory" during the first prompt,
after a load that succeeded; Vulkan with Gemma 4 dies on the first prompt
without a message. Windows has not been run.

**Measured on Linux, a 16 GB AMD card (RX 6900 XT), and in a 6 GB NVIDIA
log (2026-10-04)**

KoboldCpp 1.122.1 on Vulkan and the 1.121 ROCm build, with Qwen3-14B,
Qwen3-30B-A3B and Gemma 4 12B; the original author's KoboldCpp log for
Qwen3.6-35B-A3B on a GTX 1060. Full figures are pinned in
`test/utils/vram_estimator_real_engine_test.dart`.

- The memory KoboldCpp sets aside follows exact rules that can be read from
  the model file: the weights on the card are the file's own tensor sizes
  (the embedding stays in system memory; a model that ties its output to
  its embedding gets a second copy on the card, 540 MB on Gemma 4 12B), and
  the cache is per layer (context plus 128 cells rounded up to 256; a
  sliding-window layer, with sliding window on, holds the window plus one
  batch rounded up to 256, plus 128). Both matched the engine to the MiB.
- The app's model reader looked for `<arch>.sliding_window`. Real files say
  `<arch>.attention.sliding_window`, so sliding window was never detected,
  and every check that depends on it (the context-mode note at launch, the
  editor's choice) saw "no sliding window".
- The working memory is the output scores for a batch (batch x vocabulary x
  4 bytes) at small batches. On Vulkan, once those scores reach 1 GiB they
  get their own block and add to the layers' working set: Gemma 4 took
  1331 MB at batch 1024 and 2662 MB at 2048.
- ROCm with flash attention off, as the app launched it, needs far more
  working memory (1377 MB against 307 at 16k on Qwen3-14B, growing with the
  context) and runs slower: 30.7 against 38.8 tokens/s with everything on
  the card, and 12 against 32 at 32k, where it no longer fit. With flash
  attention on, every model ran on this card. ROCm also uses about 250 to
  300 MB its log does not list, plus up to 220 MB more during a reply, so
  32 MB spare ("greedy") ran out of memory on the first prompt.
- Gemma 4 on Vulkan with flash attention on: loaded, then died on the first
  prompt, every time. With it off it ran at 37 tokens/s; ROCm ran it either
  way.
- Sliding-window mode on Gemma 4 cut the cache from 5.4 GB to 0.8 GB at 16k.
- Smart cache keeps each slot (one conversation's cache, plus a hybrid
  model's recurrent state) in system memory: 372 MB for a 2,388-token chat
  on Qwen3-14B, up to the whole cache for a full context. Going back to a
  saved conversation took about 0.2 s against 2.8 s to re-read it.
  KoboldCpp gives a hybrid model one slot more than asked. The author's
  machine had 9 to 11 GB free for a model keeping 17 GB in system memory;
  there every slot takes memory from the model itself.

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

**Measured on 1.117.1 and 1.122.1, Apple Silicon (2026-10-04): the listen
address**

- `host` is applied from the staged config at launch. With
  `host: 127.0.0.1` there and nothing about the address on the command
  line, both engines answered on 127.0.0.1 and refused this computer's own
  network addresses (Wi-Fi and VPN). With the line removed, both answered
  on the Wi-Fi address with the admin endpoints on.
- A live reload leaves it alone: a config with no `host` in it, loaded by
  reload, did not reopen the engine to the network, and neither did the
  reload back to chat's own config.
- Pinned by `test/live/kobold_host_live_test.dart` (the real engine) and
  `test/services/kobold/kobold_listen_address_test.dart` (every staged
  config).

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
2. KoboldCpp decides memory placement; Auto-Configure goes. (Corrected
   2026-10-03: the VRAM Usage Estimate stays, as a guess of how KoboldCpp
   will load the model. See "The estimate is a guess" under Design.)
3. Everyone moves to Automatic GPU layers once.
4. Web gets pick, switch and summary. The preset editor is desktop-only
   (explicit deferral, as `docs/web-phone.md` already documents).
5. Sliding-window mode keeps fast forward off (`nofastforward: true`,
   `noshift: true`). Not to be changed.
6. Cache quantisation offers f16, bf16, q8_0, q5_1, q4_0.
7. Sliding window alone is fine; only sliding window with fast forward is
   bad. Every config the app writes from its own settings has one of the
   two safe pairings. The default is sliding window off with fast forward
   and context shift on. A user's preset is run as written (2026-10-03):
   the app switches sliding window off only when the file itself has it on
   with fast forward on. A preset that does not mention sliding window is
   left to KoboldCpp's default, and the engine log says what that default
   does when the model has sliding window.
8. Old KoboldCpp versions are not supported (2026-10-03). An engine before
   1.112 stops at load on the staged config: it compares the cache type as
   a number, and a config file is not converted the way a command line is.
   No compatibility code or tests are added for those versions.
9. Manual presets and the automatic path are both first class
   (2026-10-04). Any rule worked out for the preset dialog (the memory
   estimate, the smart cache suggestion, the context-mode pairing) also
   drives the automatic path, which shows none of the machinery: one shared
   rule, two surfaces.
10. ROCm may use flash attention (2026-10-04), with a fallback: if the
    engine dies on the first reply, the app restarts it with flash
    attention off and remembers that for the machine. The app had forced
    it off for every ROCm launch since before the rewrite. Built in Stage 5.
11. Gemma 4 on Vulkan runs with flash attention off (2026-10-04): with it on,
    KoboldCpp 1.122.1 dies on the first prompt. Built in Stage 5, lifted
    once a fixed KoboldCpp is confirmed on a real card.
12. A preset that asks KoboldCpp to run a program or open itself to the
    internet is refused, not rewritten (2026-10-04). A preset still launches
    exactly as written. The exception is `mcpfile`, `onready`, `remotetunnel`,
    `hordekey`, `preloadstory` and `baseconfig` when set (any value Python
    reads as true: the text "false" counts) and `rpcmode` when it is `host`.
    KoboldCpp's own exports carry all of them switched off and pass. The
    reason is said in plain words, naming the settings, wherever a preset can
    reach the engine: Start, a live reload of chat, a helper or story swap,
    the editor's MMQ timing, and the phone's preset pick.
    `kcppsRiskyPresetProblem` is the one place it is decided.
13. A live reload of chat that KoboldCpp could not load keeps the old model
    when a fresh start would be refused (2026-10-04). KoboldCpp goes back to
    the model it had, which still works. The app used to stop it and start
    again; a start refused for the new model file left nothing running and no
    reason shown. The reason is now always noted first (status line and engine
    log). If a fresh start would be refused (`koboldLaunchProblem`, which
    includes a preset the app will not start), nothing is stopped and the
    caller gets a refusal: the new model was not loaded, the previous one is
    still running, and why. Otherwise the engine is stopped and started, and
    the start's answer comes back. `reloadChatKobold` returns that answer.
    Settings shows it in a snackbar, the preset editor in its problem line,
    the phone's model switch in the response's `refused` field, and the
    phone's Local model card through the status line it now carries.
    When the old model is kept, the stored choice (the model in use, the
    preset, and the link between them) goes back to what KoboldCpp runs
    (2026-10-05), so every screen names the running model. What runs is what
    the service recorded as loaded before the reload, put back only when the
    engine itself says that model is the one running and the choice has not
    been changed meanwhile; otherwise nothing is guessed. It is written back
    as it was recorded, not worked out again: a preset whose model was
    missing at launch and has appeared since must not turn the model in use
    into that one while KoboldCpp runs the other. The staged chat config and
    the service's record go back with it.
14. The app's KoboldCpp answers this computer only, with no admin password
    (2026-10-04). Before this it listened on every network the computer was
    on, so any device on the same Wi-Fi could call its admin endpoints (drop
    the model mid-chat) and read the latest reply. The command line is
    frozen for this work, so `host: 127.0.0.1` is written into the config
    the app stages for every launch and swap, over a preset's own `host`
    (the app owns the address, and a preset naming a network address
    already cut the app off).
    KoboldCpp applies `host` from `--config` at launch and ignores it on an
    admin reload, so a swap cannot change it. The app reaches the engine at
    `http://127.0.0.1:<port>` and nothing else (`kKoboldHost`).
15. Stop while a start is still being prepared calls that start off
    (2026-10-04). Pressing Stop after the start slot is claimed and before
    KoboldCpp is spawned (the free-memory read, the model file check, the
    first-run graphics card check) means KoboldCpp is not started, and the
    start says "KoboldCpp was not started: it was stopped while it was
    getting ready." A swap that frees the graphics card for another engine
    stops a preparing start the same way (before, it spawned afterwards,
    next to the other engine). Quitting the app, and the update shutdown,
    stop a preparing start too. Only
    the "nothing spawned yet" case changed: the kill ladder for a running
    process is as it was, and the stop a start makes of the engine it
    replaces does not call that start off. The start checks for a Stop
    right before it spawns, after its last wait.
16. A start the app asked for that is refused says why where it used to be
    dropped (2026-10-05). The phone's Restart, and its model switch while
    KoboldCpp is stopped, answer with the same `refused` field a refused
    reload uses, and the Models page says it beside the buttons. Opening a
    chat starts the engine ("Auto-start on chat open"); that start's refusal
    is kept by the provider and said in place of "No API connection": in the
    desktop composer's hint, and on the phone as `llmHint` in the chat state
    (above the box), until something runs or what the engine has loaded has
    changed (`LLMProvider.composerConnectionHint`). `ensureManagedBackendIsRunning`
    returns the start's answer. A refusal is not a dialog: nothing new
    interrupts the chat.

## Design

**Settings stay in preferences; a config is derived at launch.** The app's
simple settings (context size, GPU, cache level) are read all over the app,
including the web facade and the prompt budget, so they stay where they
are. At launch a pure function turns them into a `KoboldLaunchConfig`.
A user's preset is read into the same type for what the app shows and
edits, but that type is a summary and is never what a launch runs.

**A user's preset is launched as it was written.** The staged config for a
preset is the file's own content with a few settings laid over it: the
model the app resolved, `jinja: true`, the vision file (when one was chosen
for the model and exists), `host: 127.0.0.1` (decision 12), and
`noswa: true` when the file has sliding window on (`noswa: false`, or
`useswa: true` in a file from before that name existed) with fast forward
on. Nothing else is added, changed or dropped. As first merged, the launch
rebuilt the preset from the typed config: a second graphics card, the CUDA
options and a MoE layer count were dropped, a cache size was clamped,
context shift was switched back on, and every setting the file had left to
KoboldCpp got the app's default (a 16384 context for a file that named
none).

**One rule for the model a preset names.** `kcppsModelOf` reads it the way
KoboldCpp does: `model_param` when it is a non-empty string, else `model`
when it is one, else the first entry of `model` when it is a list. Settings
and the launch both use it, so what Settings shows is what loads. A relative
path is resolved against the engine folder, which is the folder KoboldCpp
runs in. Settings, the vision check and the launch all get the full path,
and the staged config carries it.

**A start that cannot go ahead leaves the next one possible.** The service
marks itself "starting" before it prepares a launch. As first merged, a
failure in that preparation that was not the one expected kind (a preset
with a number too large to hold, a config folder that could not be written)
left the mark set: every later start was turned away and Stop did not clear
it, until the app was restarted. Reading a preset now never throws, a
non-finite number makes the file a broken preset, and any failure to
prepare a launch is a refusal with a reason.

**Every launch and swap uses a staged "effective config".** The app never
launches or edits a user's `.kcpps` directly. For each role (chat, worker,
story job) it writes a config into the admin folder: the source (preset or
app settings) plus the absolute model path, `jinja: true`, the resolved
vision file, and `host: 127.0.0.1`. Launch is
`--config <staged> --port N --admin --admindir D`.
A swap reloads the staged file by name, with no file links (Stage 4; until
it lands, a swap back to a user's preset still links the user's own file).

**Only these stay on the command line:** port, admin, admin folder.
KoboldCpp protects them from being set by a config. The listen address is
protected on a reload too, but a launch reads it from the config, which is
why it rides in the staged config and not on the command line (decision 12).
The one config the app stages without it is the preset editor's speed
trial, which is only ever live-loaded.

**The estimate is a guess, not a setting.** The "VRAM Usage Estimate" in
the preset dialog has never decided how a model is loaded. KoboldCpp fits
the model. The estimate guesses how that fit will come out (for a MoE
model: the active weights on the card, the experts in system memory) so the
user can pick a context size, batch size and cache type that fit in what is
left, and the model runs at full speed. Nothing in this rewrite removes it,
and the preset editor (Stage 6) keeps it.

The guess and the preset have to agree on one figure: how much graphics
memory the fit leaves spare (1024 MB, or 32 MB with "greedy"). KoboldCpp
keeps a preset's `autofitpadding` only when the fit is forced
(`autofit: true`). When it switches the fit on by itself (layers at -1 and
nothing else in the way) it puts the padding back to its own default. That
is in its source from 1.108 through 1.122, and was seen on a real 1.117.1:
a preset with `autofitpadding: 32` and no `autofit` ran with 1024, and the
same preset with `autofit: true` ran with 32. So a generated preset writes
`autofit: true` with its padding, as it did before the rewrite. As first
merged, Stage 1 stopped writing it, and "greedy" then did nothing while the
dialog still counted on it. The app's own settings (no preset) do not force
the fit: they carry no padding, and a manual layer count must be obeyed.

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
- A version check, from the existing `KoboldBinaryVersion`. This was planned
  as `kobold_capabilities.dart` (version to feature flags, older builds
  getting the older forms); decision 8 made that unnecessary, and as built it
  is `KoboldBinaryVersion.tooOldProblem`: one minimum (1.112), one sentence,
  and an engine below it is refused, not written an older config.
- Thread detection moved out of the generator, into
  `kobold_hardware_defaults.dart`.

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
cache levels; the minimum engine version; a broken file.

### Stage 2: launch from a staged config; delete the estimate (items 3, 4, 5, 6, 17, 22)

- `lib/services/kobold_launch_args.dart` shrinks to the port and the admin
  folder: everything else is in the staged config.
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
- `VramEstimator` stays and gains factors for bf16 and q5_1. It never set
  anything; see "The estimate is a guess, not a setting" under Design.

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
  updated to match, so the status card, vision lookup and web "loaded"
  marker agree. (Since Stage 8 the thinking cap and the system-message
  check go by the model KoboldCpp has loaded, which after a swap is not
  the last-used one. Step 9 found that a live reload does not update the
  last-used model.)
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

As built: `resolveKoboldLaunch` and `selectKoboldModel` in
`lib/services/kobold/kobold_launch_resolver.dart`, and one entry,
`KoboldService.launch`, which resolves, records the model that loads as the
last-used one, and starts it from the stored settings. The only remaining
direct start is a swap, which names its own model and preset. A preset
whose file is gone is cleared and the launch goes ahead on the app's own
settings; one whose model is not on this computer runs the chosen model
with the preset's settings. Both are said in the engine log.

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

As built: every role (chat, the helper model, a story job) gets its config
from `stageKoboldRole`, the same function a launch uses, written into the
admin folder as `fpai-<role>.kcpps`; the reload names that file. The key
for "what is loaded" is the staged content itself, kept on `KoboldService`
(`isResident`), so two roles with the same content never reload, and a role
set to the chat model's own pair stages the chat config. `KoboldProcessHost`
sends nothing when its content is resident, marks the engine not ready the
moment a reload is accepted, and waits with `waitForKoboldReload`: first
for a new model process (the engine's `uptime` restarts on every reload;
the rule is `uptime < seconds since the request - 0.25`), then for it to
generate. On a shared engine `GpuSwapOccupancy` does not unload first and
asks each role every time. A reload the engine never acted on falls back
to a process restart; one that restarted and is still loading is reported,
not restarted again.

Proven on the real engine: with the "new process" wait taken out, a job's
call ran on the chat config (4096 where 2048 was expected).

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

Added 2026-10-04:

- A failure class for "loaded, then died on the first prompt". ROCm prints
  `ROCm error: out of memory` there; Vulkan with Gemma 4 dies without a
  message.
- ROCm follows the Flash Attention setting (decision 10), with the restart
  without it as the fallback for that failure. The two ship together.
- Gemma 4 on Vulkan is written with flash attention off (decision 11), in
  the automatic path and in generated presets, with a one-line note. Cache
  compression is then unavailable for it, since it needs flash attention.
- An engine too old to read the staged config gets one line: update
  KoboldCpp (decision 8).

As built (2026-10-04): `kobold_launch_failure.dart` tells an exit apart
from what the engine printed and when: out of memory, a model file it
cannot read (exit 2), stopping mid-answer without a word, and anything
else (pointing at the log). The message goes to the engine log and
`KoboldService.lastFailure`; a stop the app asked for is never taken for a
failure. Proven on a real engine: killed mid-reply, the app says it
stopped while answering. When the ROCm build dies mid-answer with flash
attention on, a per-machine flag is set and the engine started again once
without it (out of memory does not trigger it). `koboldFlashAttentionRuns`
is the one rule for when flash attention is written (Gemma 4 on Vulkan:
off; ROCm: on unless flagged); where it is off, a compressed cache falls
back to full size and the launch log says why. An engine whose recorded
version is below 1.112 is not started. Not built: a port-in-use message
(on macOS KoboldCpp started on a taken port without any error, so there
is no text to match) and an Apple Silicon out-of-memory message (Metal did
not refuse a cache larger than memory up front). Moved to Stage 6: live
reload first when chat's model or preset changes, and the prompt budget
using the engine's real context.

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
- Draft settings (planned here, built in Stage 8): a draft model file, "use the
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
- The VRAM Usage Estimate stays, with the batch suggestion, and stays a
  guess of how KoboldCpp will load the model (see Design). It is what the
  editor is for: choosing a context size, batch size and cache type that
  fit beside a MoE model's active weights. Item 19 adds to it: what each
  choice saves or costs, and the system memory the snapshot cache uses. A
  preset saved from the editor on automatic layers keeps forcing the fit
  with the padding the estimate assumed.

Added 2026-10-04, from the measurements above:

- The estimate is made exact first, in its own PR before this stage: the
  rules above, the working memory by backend, flash attention on or off,
  what the engine uses beyond its listed buffers, and the reader fix for
  sliding window. The editor's sliding-window choice depends on that fix.
- "Fits" is judged against the card's free memory with the spare memory
  the fit keeps and the engine's extra memory included, never more
  optimistically than KoboldCpp. A MoE model's figure says how much of the
  experts also fits, not only the part that always sits on the card.
- Smart cache: a suggested number of slots with its system memory cost.
  One slot for each kind of prompt the app sends that engine, capped by the
  system memory left after the model's own share; none extra on a machine
  already short of memory, with the reason shown. The automatic path
  applies the same number without showing it (decision 9).

Tests: library operations on a temp folder; a widget test that edits,
saves and reopens a preset; summary lines for three real files.

As built (2026-10-04), to the sketch the maintainer approved:

- Placement by hand follows the engine and was checked on the 16 GB card:
  N layers puts the output layer and the LAST N - 1 blocks on the card
  (Qwen3-14B at 20 of 41: 4843.57 MiB, the file's sizes for blocks 21 to
  39 and the output exactly); `moecpu M` keeps the experts of the FIRST M
  blocks in system memory (KoboldCpp: "the MoE weights of the first N
  layers"); a block in system memory keeps its cache there (4883 and 5397
  MiB at 64k); a split adds working memory (479.75 against 316.75). The
  same search reproduces KoboldCpp's own fit: 30 of 41 layers at 64k, every
  layer at 32k, MoE experts never above what the engine placed.
- The editor writes `autofit: true` with its padding for automatic
  placement and `autofit: false` with `gpulayers` and `moecpu` by hand. A
  placement that does not fit says by how much, and "Use the largest that
  fits" takes the most that does. Numbers past the model are refused.
- The display name is the file name. Renaming moves the file and every
  setting that points at it (chat, each model's preset, the helper model,
  Porch Stories jobs); deleting lets go of them. One listing
  (`kcppsPresetFiles`) serves every picker.
- Free memory is read before each launch (nvidia-smi, the AMD driver,
  vm_stat, /proc/meminfo, FreePhysicalMemory) and kept as "free before the
  engine": a reading taken while the app's KoboldCpp runs would count the
  model against itself.
- Auto mode tunes silently: the largest batch of 512/1024/2048 that keeps
  as much of the model on the card as 512 does (an "Auto" chip, the
  default, in Advanced; a chosen batch is kept); smart cache slots that fit
  in free system memory (3, or KoboldCpp's 7 for a recurrent model).
  Context shift (decision 12): KoboldCpp's source keeps a slot for a
  regenerated reply and a checkpoint part way into a long prompt for a
  recurrent model, since its state cannot be rewound; so context shift
  stays on for such a model and is switched off only where memory has no
  room for KoboldCpp's smallest count (three).
- MMQ: the editor times both ("Time both on this card": the preset loaded
  each way as a trial, a fresh 2,000-token prompt twice, the faster kept);
  auto mode learns it from KoboldCpp's per-reply speed line ("Processed: N
  in Ts", "Generated: N/M in Ts"): on until three replies that read 512 or
  more tokens and three that wrote 16 or more can be timed, then off until
  the same, and keeps the faster per card and engine version. Replies that
  cannot be timed do not count towards either (counting them left the
  trial on "off" for good after three short replies), the newest eight of
  each kind are kept, and a launch that is not auto mode on CUDA (a preset,
  another backend) ends a trial that is open.
- The "Local model" card on the KoboldCpp settings page is auto mode's
  only surface: how the model runs, in plain words, and the context, with
  a verdict per size from a read-cost model (weights a token uses plus the
  whole chat memory; system memory counted six times the card; extra
  reading from the disk over a GB is "very slow"). Below 16,384 is always
  "not recommended or supported", even for the size in use. The card, the
  phone's, and the editor's fit take the graphics backend from the one rule
  the launch uses (`koboldBackendFor`, honouring the switches in Settings),
  and the card assumes the batch the launch runs: the one chosen in
  Settings, or KoboldCpp's own when nothing goes on a card.
- Live reload first (moved from Stage 5): a new chat preset or model in
  Settings, "Save and use now", and the phone's model switch reload the
  staged chat config by name and restart only when that is not acted on.
- Prompt budget (moved from Stage 5): KoboldCpp runs with the context its
  config gives (`maxctx = args.contextsize`), so the context in chat's
  staged config is recorded when it names one, and every prompt budget is
  held to it: a chat set longer than the engine no longer has its start,
  card first, cut. A config that names none runs KoboldCpp's own default,
  which differs by version (12,288 on 1.117.1, 16,384 on 1.122.1): staging
  records nothing then, because staging is not a load (a swap back to chat
  stages this config before every reply) and must not forget what the
  engine said. The engine is asked (`/api/extra/true_max_context_length`)
  when a launch is ready and when a reload is checked, and that is held
  until the next one.

Path-complete (prompt budget): generation, Continue and regenerate share
the generation plan; group chats the same; impersonate, lorebook blocks,
RAG memory, the creator's lore, enhance (desktop and web) and Waifu Coder
read the held value. Realism and Needs evals, Journal, Growth Rings and
pockets do not read the context size.

Owed to Stage 7 (web, next): the chat-preset picker with the summary
line, the "Local model" card with its context verdicts, and the preset
summary card.

### Stage 7: web (item 21)

- Routes on the backend facade (`backend_facade.local_model.dart`, see
  "Stage 7 as built" below): list presets with summaries, set the chat
  preset (limited to the engine folder), set the context.
- Web chat-preset picker and summary card. No editor (deferred).
- A journey in `web_ui/e2e/journeys.spec.ts`.
- Update `docs/web-phone.md` and `docs/user-guide.md`.
  (`docs/moe-vram-estimation.md` was wrongly marked superseded in Stage 2.
  Its estimation is live in the preset dialog; only its Auto-Configure
  parts describe removed code, and the page now says so.)

Stage 7 as built (2026-10-04): the phone's Models page has the "Local
model" card (the same KoboldStatusFacts as the desktop card, moved to
`lib/services/kobold/kobold_status_facts.dart`) and a separate "KoboldCpp preset"
card (auto mode never shows a door to presets). Routes:
`GET /api/backend/local-model`, `POST /api/backend/local-model/preset`
(only a preset in the engine folder, or none: the server may be reachable
from the internet) and `POST /api/backend/local-model/context` (512 to
1,048,576 tokens; a running KoboldCpp reloads once the phone stops
changing it). Both cards show only when KoboldCpp is the backend, as the
desktop's section does. The browser suite seeds a real model header and a
preset, switches the host to KoboldCpp for that journey only, and walks the
card. While a preset runs, the settings save refuses a context that differs
from the stored one (the page sends the whole form with every save, so the
stored value coming back is not a change) and the Settings slider is locked,
as on the desktop.

### Stage 8: the rest (as built)

Stage 8 as built, the rest (2026-10-04):

- Draft settings left over from Stage 6: `draftamount` (tokens guessed
  each step; empty leaves KoboldCpp's 4) and `usemtp` (the model's own
  draft heads) are managed. The heads are offered only for a model whose
  file has them: GGUFModelInfo.draftHeads is `<arch>.nextn_predict_layers`
  (1 in the real Qwen3.6 35B A3B MTP header). Live: an editor-made preset
  with a draft model and 3 tokens a step launches and writes on 1.117.1
  and 1.122.1; `usemtp` on a model without heads still loads and writes.
- Thinking stays per request (every request carries the user's setting,
  the same from any launch or swap). The "stop thinking" cap
  (`thinking_budget: 0` for a template that forces thinking on) is keyed
  on the model KoboldCpp has loaded, not chat's, so a helper or story
  model is judged by its own template. The system-message check (whether
  the template drops a system message, so it is folded into the user turn)
  follows the same model, `KoboldService.requestModel`.
- Splitting across cards: keep and explain (the maintainer's choice; no
  two-card machine to test on). Every Vulkan card a preset names is kept;
  CUDA with no card named uses them all. The plain words say so, and the
  editor's estimate counts the chosen cards together (free memory is read
  for one card; each other counts all but half a GB) with one working-
  memory buffer per extra card. Detection counts the cards it sees
  (HardwareInfo.cardCount): nvidia-smi lines, and for AMD the driver's
  `cardN` entries only, since it lists each card again as `renderDN`
  (`amdDrmCards`, shared with the free-memory read). A preset made on a
  machine with more cards never counts more than this one has. No control
  to make a split.

Stage 8 as built, unload when idle (2026-10-04): a setting, off by
default, `kobold_idle_unload_minutes` (off, 10, 30 or 60) in
`kobold_launch_fields.dart`, set from a chip row in Advanced Launch Options
and a card on the phone's Settings page (`koboldIdleUnloadMinutes` on
`/api/settings`). The clock is `kobold_service_idle.dart`, a part of
`KoboldService`: started by a launch, stopped by a stop or dispose, it
checks every 30 seconds. Every request (the stream and `_runSerialized`,
which carries tool calls and the system-role probe), a swap, a load and a
launch reset it. When the engine is the app's own process, its model is
loaded, nothing is in flight or queued on the swap lock, the idle time has
passed and KoboldCpp's own `/api/extra/perf` says idle with an empty queue,
it sends the same `unload_model` reload a swap's unload sends, inside the
swap lock, and waits for "inactive". It remembers the staged config whose
content is resident (chat's in the normal case, found by content in the
admin folder) and the model and preset paths. The next request of any kind
first reloads that file by name and waits for the real switch with
`waitForSwap`, then checks the model KoboldCpp reports; a swap that loads
anything first clears the record instead. Waifu Coder's OpenCode asks
KoboldCpp itself, so each of its turns runs inside
`KoboldService.keepLoadedFor`, which loads the model back first and holds
the clock until the turn ends. While unloaded, `modelReady` is
false and the status line says "The model was unloaded after N idle minutes
to free graphics memory. It loads again with your next message."; `isReady`
stays true so features that check it before asking still ask, and their
request brings the model back. `isReady` is only that gate. What every
status shows comes from one rule, `KoboldPhase` (`KoboldService.phase`:
stopped, starting, loading, unloaded or ready): the Local model card, the
engine log, the character creator's setup step, the home screen's status
line, and the phone (`phase` on `/api/backend/status`
and `/api/backend/local-model`). A process that is not running is stopped
whatever the unload record says, and an exit clears that record as a stop
does. A reload KoboldCpp accepts while the model is unloaded (any swap,
through `markModelLoading`) replaces the record, so it reads as an ordinary
swap: Loading, then Ready. A token count loads the model back first, like a
request: with no model, KoboldCpp's tokenizer has nothing to count with,
and the chat budget keeps the answer. KoboldCpp's empty model process prints
"Please connect…" like a model that came up, so the log's ready fast-path
is ignored until the model is back. A load back that fails says so in plain
words, as a transport failure (it never marks the backend as unable to call
tools), and requests in the next half minute fail at once instead of asking
again. Proven on 1.117.1 and 1.122.1 (`test/live/kobold_idle_unload_live_test.dart`):
`/api/v1/model` answers `inactive` after the unload; a reply and a tool
call each reload `fpai-chat.kcpps` and are answered.

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

The migration is not one function: each setting is read where it is used
(the cache level in `KoboldLaunchFields.kvQuant`, the layer count and its
one-time note in `loadKoboldLaunch`), over the stored preferences. It is
tested with the old preferences seeded as an upgrade finds them.

## Reuse (already in the repo)

- `GpuBackendResolver` for choosing a backend when none is stored.
- `GGUFModelInfo.isMoe` and `.slidingWindow` (`lib/utils/gguf_model_info.dart`).
- `KoboldBinaryVersion` (`lib/services/kobold/kobold_binary_version.dart`).
- `ModelFileCheck` for the pre-launch file check.
- `KoboldAdminSwapLock` and `KoboldProcessHost`, already injectable.
- `WorkerBackendFields` as the pattern for a settings mixin.
- `VramEstimator` for the guess of how KoboldCpp will load the model.

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
