# Local model fixes: what to fix and in what order

Written 2026-10-03 from three read-only reviews of the KoboldCpp code paths:
one of `.kcpps` preset handling and model swapping, one of what happens when
a model does not fit in graphics memory, and one comparing the preset
generator with what KoboldCpp 1.122.1 offers. Nothing in this plan has been
built.

## How to read this

- **Checked** means the finding was confirmed by reading the code a second
  time. **Reported** means it came from the review and was not re-checked.
- **Size** is a rough guess: small is under a day, medium is a few days,
  large is a week or more.
- **Needs a real machine** marks anything that cannot be settled by reading
  code or by tests in CI.

The order puts first what is small, certain, and costs users the most time
or gives them a wrong answer. Work that needs hardware to confirm comes
later, so it does not block the rest.

---

## Phase 1: small fixes with a certain payoff

No hardware needed. Each can ship on its own.

### 1. A Porch Stories job on a local model reloads it on every call

- **Status:** Checked.
- **What is wrong:** Each story call asks "is this the same job as last
  time?" by comparing two objects. A new object is built for every call, so
  the answer is always no. The app puts the chat model back, then loads the
  story model again: two full model loads per call, and the prompt cache is
  lost each time.
- **Fix:** Keep one host object per job, or compare by job id.
- **Where:** `lib/services/llm_provider.lanes.dart`,
  `lib/services/story_pipeline_service.llm.dart`.
- **Test:** Two calls in a row on the same local job must cause one swap and
  no return to the chat model. This fails today. No test covers story jobs
  at all.
- **Size:** Small.
- **Follow-up (medium):** Going from one local job to a different local job
  loads the chat model in between for nothing.

### 2. Switching model from the phone keeps the old model's settings

- **Status:** Checked for the preset; reported for the layer count.
- **What is wrong:** The web model switch saves the new model and restarts.
  It does not change the preset to match, and it reuses the last model's
  GPU layer count. Moving from an 8 GB model to a 16 GB one launches with
  the old preset's context and "all layers".
- **Fix:** Do what the desktop model picker does: apply the new model's own
  preset or clear it, and recompute or reset the layer count.
- **Where:** `lib/services/web/facade/backend_facade.dart`.
- **Test:** Switch between two known models through the facade and assert
  the preset and layer count that would be launched.
- **Size:** Small.

### 3. Vision is silently lost when a preset is used

- **Status:** Reported.
- **What is wrong:** The preset generator never writes the vision add-on
  into the file, and a launch from a preset passes none. The app still
  reports vision as working, so images are ignored and the caption fallback
  is skipped.
- **Fix:** Write the vision add-on into the generated preset, and look it up
  by the preset's model when launching.
- **Where:** `lib/services/kcpps_generator_service.dart`, the preset launch
  sites, `lib/services/capability/vision_support_resolver.dart`.
- **Size:** Small.

### 4. Preset housekeeping

- **Status:** Reported.
- **What is wrong, and the fix for each:**
  - An internal file, `fpai_batch_override.kcpps`, appears as a preset you
    can pick, on desktop and web. Hide it from both lists.
  - The generator always targets GPU 0, ignoring the GPU setting the normal
    launch uses. Use the same setting.
  - Generating a preset overwrites one with the same name without asking.
    Ask first.
  - The story picker says "Same as chat" for an empty preset, but no preset
    is passed. Either pass the chat preset or change the words.
  - The generator writes the cache-quantisation setting as text while the
    launch path passes a number. Phase 5 will say which KoboldCpp expects.
- **Size:** Small, as one batch.

---

## Phase 2: make the default load sane

This is the "model does not fit in graphics memory" problem.

### 5. Let KoboldCpp choose GPU layers by default

- **Status:** Checked that the app computes its own number and never uses
  KoboldCpp's automatic fit. Checked that the app's own generated presets
  already use automatic fit with the memory lock off.
- **What is wrong:** When a model does not fit, the app guesses a layer
  count as if every model had 99 layers. On a 12 GB card with a 16 GB model
  it picks about 28 layers, which is too many for a 40-layer model and far
  too few for an 80-layer one. It also treats total graphics memory as free
  memory, and locks the whole model into system RAM as well.
- **Fix:**
  - When the user has not typed a layer count, send "automatic" and let
    KoboldCpp fit the model.
  - Turn the memory lock off unless the whole model is on the card.
  - Choose the GPU backend on every launch path. Today some paths send no
    GPU backend at all if Settings was never opened, which means CPU only.
  - A number the user typed is still honoured.
- **Where:** `lib/services/kobold_launch_args.dart`,
  `lib/services/storage/settings/backend_settings.dart`, the launch sites,
  the GPU Layers fields, and an "Auto" indicator on web.
- **Test:** The launch-argument builder is a pure function with existing
  tests. Add cases for "automatic gives -1 and no memory lock" and "a typed
  number passes through".
- **Size:** Medium.
- **Needs a real machine:** the exact spelling of the automatic-fit flags on
  the command line, and what KoboldCpp actually picks for a model larger
  than the card. KoboldCpp's own documentation says its guess is less
  accurate with more than one GPU.

### 6. Fix the app's own estimate for people who use Auto-Configure

- **Status:** Checked.
- **What is wrong:** The model's real layer count is read from the file and
  stored, but the code that picks layers is handed nothing. A comment in the
  code says so.
- **Fix:** Pass the real layer count in and delete the "45% of 99" guess.
  Keep the shared-memory flag that the Settings path currently drops, so a
  laptop's shared system memory is not counted as graphics memory.
- **Where:** `lib/services/optimization_service.dart`,
  `lib/utils/kobold_layer_solver.dart`,
  `lib/ui/pages/settings_page.controls.dart`.
- **Test:** The solver is a pure function. Feed it real model sizes and real
  card sizes.
- **Size:** Small to medium.

### 22. MoE models on the normal launch path

Numbered 22 because it was added last, but it belongs here: build it with
items 5 and 6.

- **Status:** Checked. The design already exists in
  `docs/moe-vram-estimation.md`; its first two steps are built and the rest
  are not.
- **What is wrong:** A MoE model only uses a few of its "expert" blocks for
  any one token. The rest can sit in system memory. The preset path gets
  this right by leaving it to KoboldCpp. The normal launch path does not:
  - The layer estimate assumes every expert must be on the graphics card,
    so it over-estimates the memory needed by 4 to 20 times and recommends
    far too few layers.
  - The launch never passes KoboldCpp's "keep experts in system memory"
    setting (`--moecpu`), so every expert in an offloaded layer is copied to
    the card.
  - The memory lock is on by default, so those same weights are also pinned
    in system memory. The design doc records a 13 GB model on a 6 GB card
    using about 35 GB in total and running at 0.2 tokens a second.
- **What is already built:** The model file reader collects the MoE details,
  and the model-info class has the two ratios the estimate needs
  (`isMoe`, `gpuWeightRatioWhenOffloadingExperts`). The preset dialog's
  estimator uses them. The normal path does not.
- **Fix, following the design doc's remaining steps:**
  1. Give the layer estimate the model's real layer count (item 6) and the
     MoE ratio, so each layer is costed at what actually goes on the card.
  2. Pass the model's details from the three Auto-Configure call sites
     (Settings, the Model Settings dialog, the character creator's setup
     step). Wait for the details to load first; today the Settings path can
     run before they are ready.
  3. At launch, when the model is MoE and any layers are on the card, pass
     `--moecpu` and do not pass the memory lock.
  4. Fix the memory-lock default. The code comment says "on for Windows and
     Mac, off for Linux", but it is on everywhere.
- **Where:** `lib/utils/kobold_layer_solver.dart`,
  `lib/services/optimization_service.dart`,
  `lib/services/kobold_launch_args.dart`,
  `lib/services/kobold_service_process.dart`,
  `lib/services/storage/settings/backend_settings.dart`, and the three call
  sites.
- **Test:** The estimate and the launch-argument builder are pure functions.
  Feed the estimate the real figures in the design doc's table (Gemma 4 26B,
  Qwen 3.6 35B) and check it recommends full offload on a 6 GB card. Check
  the launch arguments include `--moecpu` and omit the memory lock for a MoE
  model, and are unchanged for a dense one.
- **Size:** Medium.
- **Decision needed, because it conflicts with item 5:** KoboldCpp's
  automatic fit and `--moecpu` cannot be used together. From its source and
  release notes: automatic fit switches itself on only when `--moecpu` is
  not set, and forcing it on makes `--moecpu` ignored. So for a MoE model on
  the default path there are two options:
  - **A. Leave it to automatic fit**, as the preset path does. Simplest, and
    one behaviour for both paths. It relies on automatic fit handling MoE
    well, which the design doc states but this review did not confirm.
  - **B. Pass an explicit layer count with `--moecpu`**, as the design doc
    describes. More predictable, and it works when the user has typed a
    layer count, but the app's estimate has to be right.
  A reasonable split: A when the user has not chosen a layer count, B when
  they have.
- **Needs a real machine:** a MoE model on a small card, to compare A and B.
  `--moecpu` needs a recent KoboldCpp: release 1.111.1 fixed it for Gemma 4,
  so an older build should not be sent the flag.

---

## Phase 3: make swaps reliable

### 7. The restart fallback gives a model about ten seconds to load

- **Status:** Checked in code. How tight it is in practice needs a live run.
- **What is wrong:** If a live swap fails, the app restarts KoboldCpp and
  checks 40 times, a quarter of a second apart. A normal model takes longer.
  The app gives up, tries to restore the chat model against a process that
  is still loading, and shows "Chat speech was put back. Try sending again."
  That is not true in this case.
- **Fix:** Wait on the same "ready" signal a normal launch uses, with a
  limit that scales with model size. Say what really happened.
- **Where:** `lib/services/kobold_service_admin.dart`,
  `lib/services/worker_gpu_hosts.dart`,
  `lib/services/chat/generation_error_messages.dart`.
- **Size:** Small to medium.

### 8. One source of truth for "what is loaded"

- **Status:** Reported.
- **What is wrong:** The worker and each story job keep their own note of
  whether the chat model is unloaded, for one shared KoboldCpp. The notes go
  stale. A job can skip its swap and run on the wrong model, and the next
  reply then reloads the chat model for nothing. The app never asks
  KoboldCpp what it has loaded.
- **Fix:** Make the loaded model and preset one shared record that every
  swap consults, and skip a swap when the wanted pair is already loaded.
- **Where:** `lib/services/worker_gpu_swap.dart`,
  `lib/services/kobold_service*.dart`.
- **Size:** Medium.

### 9. One rule for "which model does this preset load"

- **Status:** Reported.
- **What is wrong:** Five launch sites use four different rules. Start a
  preset that owns model B, restart the app, and model A can load with B's
  context and layers. The same stale value feeds the thinking settings, the
  vision lookup, the status card and the web "loaded" marker.
- **Fix:** One shared function that every launch site calls.
- **Where:** `lib/ui/pages/settings_page.controls.dart`,
  `lib/ui/dialogs/model_settings_dialog.local_actions.dart`,
  `lib/services/setup_service.dart`, `lib/services/llm_provider.worker.dart`,
  `lib/ui/pages/settings_page.launch.dart`.
- **Test:** Today's only test reads the source text. Replace it with one
  that checks behaviour.
- **Size:** Medium.

### 10. Live swap on Windows

- **Status:** Checked in code. The Windows effect is inferred, not run.
- **What is wrong:** To swap, the app links the model file into a folder
  KoboldCpp may read. Stock Windows does not let ordinary apps create those
  links. The failure is ignored, the swap is rejected, and the app falls
  into the restart path in item 7.
- **Fix:** Write a small preset into that folder that points at the model by
  its full path, and swap to that by name. No links needed.
- **Where:** `lib/services/kobold_admin_swap.dart`,
  `lib/services/worker_gpu_hosts.dart`.
- **Size:** Medium.
- **Needs a real machine:** Windows, to confirm both the problem and the fix.

### 11. Stopping KoboldCpp can kill one the user started themselves

- **Status:** Reported.
- **What is wrong:** On Mac and Linux the stop sweep kills every process
  with KoboldCpp's name, not only the one the app launched.
- **Fix:** Kill only the process the app started.
- **Where:** `lib/services/kobold_process_control.dart`.
- **Size:** Small.

---

## Phase 4: speed and clarity

### 12. Use live reload when the user changes model or preset

- **Status:** Reported.
- **What is wrong:** Every change made from Settings, the Model Settings
  dialog or the web is a full stop and start, although KoboldCpp is already
  running with live reload available. The restart includes fixed one-second
  waits in three places and a fixed five-second wait at startup.
- **Fix:** Try live reload first and fall back to a restart. Replace fixed
  waits with waiting for the actual event.
- **Size:** Medium. Do this after Phase 3, since it leans on swaps being
  reliable.

### 13. Notice a bad load and step down

- **Status:** Reported.
- **What is wrong:** On Windows with NVIDIA, a model that overflows the card
  does not fail. It spills into system memory and crawls, and the app says
  "ready". On Linux, KoboldCpp exits and the user sees an exit code in a
  log. There is no retry.
- **Fix:** Recognise out-of-memory output and a failed launch, retry once
  with fewer layers, and say so in a dialog. After the first reply, compare
  the speed against a floor and offer "use fewer GPU layers" in one tap.
  Measure free graphics memory, not total.
- **Size:** Large.
- **Needs a real machine:** the real error text on each platform.

### 14. Say the right thing when a launch fails

- **Status:** Reported.
- **What is wrong:**
  - Any exit code 2 is explained as "could not open the model file".
  - A preset that will not parse shows as "No model defined in preset".
  - A preset whose model path came from another computer launches anyway.
  - Newer launch flags are sent to old KoboldCpp builds with no version
    check.
- **Fix:** Separate messages for each cause, a check that the preset's model
  exists before launching, and a version check for newer flags.
- **Size:** Small.

### 15. Show what is happening during a swap

- **Status:** Reported.
- **What is wrong:** The swap code can report each step, but nothing is
  connected to it. Users see only "Unloading model…" and "Loading…".
- **Fix:** Show which model is loading and why.
- **Size:** Small.

### 16. Keep the app's context size in step with KoboldCpp's

- **Status:** Reported.
- **What is wrong:** The app copies the context size out of a preset only
  when it is a whole number. Worker and story-job presets never feed the
  prompt budget, which always uses the chat preset's size. The real value is
  never read back from KoboldCpp.
- **Fix:** Read the real value back after a load and use it for the budget.
- **Size:** Small to medium.

---

## Phase 5: preset features and the generate dialog

From a review of the generator against KoboldCpp 1.122.1's own source
(its option parser and its context-handling code) and the release notes for
1.103 through 1.122.1.

Good news first: every key the generator writes is a real preset key with
an accepted type. Nothing is misnamed. The problems are in the values and in
what is left out.

### 17. Preset values that do the wrong thing

- **Status:** Checked against KoboldCpp's source, except where noted.
- **What is wrong, and the fix for each:**
  - **The GPU choice is dropped.** The preset writes the GPU number as a
    number. KoboldCpp only recognises it as text, so "use GPU 0" is ignored
    and every NVIDIA card is used. This is the laptop-with-two-graphics-chips
    hazard the normal launch path already guards against. Write it as text,
    under the current key name, using the user's GPU setting. (This replaces
    the "always GPU 0" note in item 4.)
  - **Not a bug: the sliding-window option switches fast forward off on
    purpose.** KoboldCpp allows the two together, but the maintainer's
    testing found the combination severely degrades model output, and
    KoboldCpp's own startup message warns of "degraded recall" for that
    pairing. Keep fast forward off in this mode. Do not "fix" it.
    What is missing is the cost in the dialog: with fast forward off, the
    whole chat is processed again on every reply and the snapshot cache is
    disabled. The option's description should say it trades speed for
    graphics memory.
  - **The sliding-window option is offered for every model.** On a model
    without it, the setting does nothing, and the user still loses fast
    forward, context shift and the snapshot cache. The app already reads
    whether a model has it. Show the option only when it does.
  - **The default choice costs more memory than the dialog admits.** Since
    KoboldCpp 1.114, sliding window is on by default for models that support
    it. The dialog's default turns it off. That keeps context shift, which is
    a fair trade, but nothing tells the user it uses more graphics memory on
    those models.
  - **The chat template and vision add-on are missing from the file.**
    Reported for the app side. At launch the app adds both on the command
    line, which works. When KoboldCpp swaps to a different preset while
    running, it resets everything to defaults first and then applies the
    file. Neither setting is protected from that reset, so a swapped-in
    preset comes up with the chat template off and no vision. Write both
    into the preset. (This widens item 3.)
  - **Automatic fit is forced on.** It is already switched on by "automatic
    layers". Forcing it makes KoboldCpp ignore any MoE or tensor placement
    setting, which blocks item 20 below.
  - **Batch size can be set higher than KoboldCpp's own launcher allows**
    (8192 against 4096), and the batch field overwrites what the user typed
    whenever another field changes.
- **Size:** Small to medium, as one batch.

### 18. Edit, view and manage presets

- **Status:** Reported.
- **What is wrong:** A preset can be created and nothing else.
  - The dialog always starts from defaults. It cannot open an existing
    preset to change it.
  - The selector shows a filename and one status line. There is no way to
    see what a preset contains.
  - There is one preset per model, with a forced filename. No rename,
    duplicate or delete.
  - A preset made in KoboldCpp's own launcher can be chosen, but the app
    understands only three of its settings and says nothing about the rest.
  - The user guide says the generator starts from the current launch
    settings. It does not: it ignores the app's GPU, backend, memory-lock,
    cache and vision settings.
- **Fix:** An "Edit preset" path that loads the file's values. A plain-words
  summary of each preset in the selector (context, graphics card, memory
  mode, vision, cache). A name field with an overwrite prompt, plus rename,
  duplicate and delete. A note on imported presets that carry settings the
  app does not manage. Either start from the current launch settings or fix
  the user guide.
- **Size:** Medium to large. This is the main UX gain.

### 19. Make the dialog explain itself

- **Status:** Reported.
- **What is wrong:**
  - Labels assume KoboldCpp knowledge: "SmartCache Slots", "Greedy memory
    allocation", "Autofit padding", "Batch Size".
  - Bad numbers are dropped silently, with no range check.
  - The memory estimate is one total. No choice shows what it saves or
    costs, and the snapshot cache's system-memory use is not shown at all.
  - A preset that will not parse is reported as "No model defined in
    preset".
  - After applying a preset there is no way from the dialog back to "use
    the app's own settings".
- **Fix:** Plain-language labels with one line each on what the setting
  does. Range checks with a message. A saving or cost next to each choice.
  A separate message for a broken file.
- **Size:** Medium.

### 20. KoboldCpp features the generator does not cover

Ranked by value to someone running a local roleplay model. "App has it"
means the rest of the app already supports the feature and only the preset
leaves it out.

| # | Feature | What the user gains | App has it? |
|---|---|---|---|
| 1 | Vision add-on in the preset, with a "keep on CPU" option | Vision survives a swap; the preset is self-contained | Yes |
| 2 | Sliding window offered only where it works, with its cost stated | No lost speed on models that gain nothing from it | Yes; the option is shown for every model |
| 3 | Thinking defaults: template, thinking on/off, effort | A thinking model behaves the same from any launch or swap | Yes |
| 4 | Graphics card choice and splitting across cards | The right card on a laptop; use of a second card | Card choice yes; splitting no |
| 5 | Keep MoE expert weights in system memory | Large MoE models on small cards | Detection yes; needs automatic fit not forced |
| 6 | Draft model, or the model's built-in booster | Faster replies on supported pairs | No |
| 7 | Unload the model after N idle minutes | Graphics memory freed when the user walks away | No |
| 8 | All five cache-quantisation levels KoboldCpp accepts (`f16`, `bf16`, `q8_0`, `q5_1`, `q4_0`), and a separate physical batch. `bf16` is the same size as `f16`, so it is offered for completeness and saves nothing; `q5_1` sits between 8-bit and 4-bit | Every level KoboldCpp has, with a middle step between 8-bit and 4-bit | Three of five today |
| 9 | Memory-lock and direct-disk loading choices | Fewer stalls; faster cold loads on some disks | Lock yes, but the preset contradicts the app setting |

Not worth adding now: server-side sampler defaults (the app sends its own
per request), KoboldCpp's own tool calling, web search and MCP (the app has
its own and avoids KoboldCpp's on purpose), bundled speech, embeddings,
image and music models (the app does these itself), and password, tunnel
and multi-user options (not relevant to a private local backend).

- **Size:** Each row is small to medium on its own. Rows 1 to 4 are the
  ones to do first.

### 21. Web

- **Status:** Reported.
- **What is there:** The web can pick the worker's preset and a preset per
  story job, and shows the active chat preset's filename. It has no
  generator, no chat-preset picker and no preset management. The web docs
  list presets as desktop-only.
- **Decision needed:** Changes to the generator and selector fall under the
  parity rule unless they are deferred for web.

### Not confirmed

- How much system memory each snapshot-cache slot uses.
- Which KoboldCpp version the app requires. On builds older than 1.112 the
  text form of cache quantisation and the padding setting do not exist.
- Whether the app's swap code already compensates for the missing chat
  template and vision add-on. The KoboldCpp side is confirmed from source.

---

## Open questions that need a live KoboldCpp

These decide how urgent some items are. None can be answered from the code.

1. Does a live reload return before or after the model has finished
   loading? This sets the right time limits for items 7 and 12.
2. Do launch settings such as the chat template and the vision add-on
   survive a live reload? If not, thinking and vision change silently after
   the first swap.
3. What does automatic fit choose for a model larger than the card?
4. Can KoboldCpp keep its prompt cache across a swap? Re-reading the whole
   chat prompt after every swap is probably the largest remaining cost per
   turn.

---

## What not to change

The reviews found these working well:

- Live swap is tried first, under one shared lock.
- The worker model stays loaded between jobs.
- A model file is checked before launch, with plain-language reasons.
- The generate dialog's memory figures come from detected hardware.
- A timeout does not kill KoboldCpp.
