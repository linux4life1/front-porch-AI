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

Stage 9 (built, 2026-10-05): the slot keeper. The app saves each chat's
cache in one of KoboldCpp's memory slots after a reply and loads it back
before the chat's next reply, so a quick Realism check between replies no
longer costs a re-read of the whole chat. See decision 17 and "Stage 9".
Since 2026-10-06 it keeps only the open chat by default, always (nothing
weighs whether that is worth it), and lets it go when the user leaves it;
Settings → Advanced can keep recent chats too (decision 26).

Stage 10 (built, 2026-10-06): the batch in two, and the speed test. On
KoboldCpp 1.122 and later the app writes a logical batch of 2,048 and
chooses the physical one, which is what sets the working memory; NVIDIA
cards start at 1,024, everything else at 512. A button on the Local model
card, "Find the fastest settings for this computer", times a few settings
one at a time when the user asks, and saves the fastest as a real preset
for that model. See decisions 27 and 28 and "Stage 10".

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

**Measured on 1.122.1, Apple Silicon (2026-10-06): the batch is two
settings**

- `--help` lists `batchsize` as the logical batch (default 512) and
  `ubatchsize` as the physical one (default: the same as the batch). 1.117.1
  has no `ubatchsize`.
- Loaded from a config with Qwen2.5 0.5B, the engine reported: `batchsize`
  512 alone, n_batch 512 and n_ubatch 512; 1,024 alone, 1,024 and 1,024;
  2,048 with `ubatchsize` 512, 2,048 and 512; 2,048 with 1,024, 2,048 and
  1,024; 2,048 with -1, 2,048 and 2,048.
- The working memory follows the physical batch alone: 298.5 MiB at 512,
  597 at 1,024 and 1,194 at 2,048, whatever the logical batch. The output
  buffer did not change (0.58 MiB).
- KoboldCpp's own export (`--exportconfig`) writes `ubatchsize: -1` for "the
  same as the batch", and the value itself when one is given. Both exports
  are pinned in `test/fixtures/kcpps/`.
- A live reload first resets every setting to its default and then reads
  the file, so a config without `ubatchsize` runs the physical batch equal
  to `batchsize`, whatever the config before it said.

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
   does when the model has sliding window. The user is told on screen too
   (2026-10-05): the preset editor, the desktop preset card and the phone's
   preset card say it in the same sentence (`kSwaLeftToKoboldNote`) when the
   model has sliding window and the file leaves fast forward on
   (`kcppsSwaLeftToKobold`), and the editor's sliding-window switch shows a
   third state, "left to KoboldCpp", instead of "off" (the editor's own
   "In plain words" says the sentence too). Until the switch is
   answered, a save keeps the file's own word: nothing about sliding window,
   and fast forward and the window's padding as written
   (`KcppsDraft.swaLeftAsWritten`), even when another edit rewrites that
   group of settings, and whatever model the form has (a model without a
   sliding window shows no switch, so its silent file stays silent). The phone's cards print the preset's plain words as
   the server sends them (`preset.words`), so they need no change of their
   own. Wording only: the launch runs the file as written, and the editor's
   MMQ timing still loads the form with sliding window answered "off", as
   before.
8. Old KoboldCpp versions are not supported (2026-10-03). An engine before
   1.112 stops at load on the staged config: it compares the cache type as
   a number, and a config file is not converted the way a command line is.
   No compatibility code or tests are added for those versions.
9. Manual presets and the automatic path are both first class
   (2026-10-04). Any rule worked out for the preset dialog (the memory
   estimate, the smart cache suggestion, the context-mode pairing) also
   drives the automatic path, which shows none of the machinery: one shared
   rule, two surfaces. Flash attention and a compressed cache are one such
   rule (2026-10-05): a compressed cache turns flash attention on wherever
   it can run, as auto mode always did, and where it cannot (decisions 10
   and 11) flash attention is off and the cache full size. One helper,
   `koboldFlashAndCache`, gives the pair to auto mode's config, the preset
   the editor writes and the editor's "New from my settings" starting
   values; before, the editor did the opposite (flash attention off meant a
   full-size cache). In the editor a compressed size can be picked whenever
   flash attention can run, and the flash attention box then shows on,
   greyed, with "A compressed chat memory turns this on."; Full gives the
   switch back. A file that pairs a compressed cache with flash attention
   off (KoboldCpp's own launcher allows it, compressing half the cache) is
   launched as written; the editor shows it by the rule and its next save
   writes flash attention on. Settings' Flash Attention switch says the
   same line when it is off and the cache is compressed.
10. ROCm may use flash attention (2026-10-04), with a fallback: if the
    engine dies on the first reply, the app restarts it with flash
    attention off and remembers that for the machine. The app had forced
    it off for every ROCm launch since before the rewrite. Built in Stage 5.
    "The first reply" (2026-10-05): no reply has finished since that
    KoboldCpp process started, that is no "CtxLimit:" line from it yet. A
    crash after one only stops, with its reason; nothing is marked or
    switched off.
11. Gemma 4 on Vulkan runs with flash attention off (2026-10-04): with it on,
    KoboldCpp 1.122.1 dies on the first prompt. Built in Stage 5, lifted
    once a fixed KoboldCpp is confirmed on a real card.
12. A preset that asks KoboldCpp to run a program or open itself to the
    internet is refused, not rewritten (2026-10-04). A preset still launches
    exactly as written. The exception is `mcpfile`, `onready`, `remotetunnel`,
    `hordekey`, `preloadstory` and `baseconfig` when set (any value Python
    reads as true: the text "false" counts), `rpcmode` when it is `host`, and
    `hordeconfig`, the old name of the Horde settings, when it holds a Horde
    key (KoboldCpp takes `hordekey` from it on every load).
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
    `adminunloadtimeout: 0` is laid on the same way (decision 18).
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
17. The app keeps the chats' cache itself, with the slot keeper
    (2026-10-05). KoboldCpp holds one chat's cache at a time and every
    helper prompt (a Realism judge, a needs check, a journal pass) replaces
    it, so the next reply read the whole chat again. Its smart cache saves
    at every switch between prompts, helpers included, and writes over the
    least recently used slot, so the helpers pushed the chats out. For an
    ordinary model auto mode now writes no smart cache (context shift stays
    on) and the app saves a chat's cache in one of KoboldCpp's five admin
    slots when a reply ends and loads it back before that chat's next reply.
    The maintainer's answers: a model with recurrent layers keeps
    KoboldCpp's own smart cache and the keeper stays out of it (a saved state
    only matches a prompt that starts with all of it); the preset editor and
    its smart cache suggestion are unchanged, and a preset with smart cache
    on keeps the keeper out; if the keeper fails at run time in an auto-mode
    launch, the failure is remembered for that model on that engine version
    and the next start writes the smart cache auto mode wrote before, so the
    user is never worse off than before the keeper. Details under "Stage 9".
18. KoboldCpp's own idle unload never runs (2026-10-05). The app keeps its
    own timer (Stage 8, "unload when idle"), which unloads the model and loads
    chat's setup back before the next request. KoboldCpp's timer
    (`adminunloadtimeout`) cannot do that: its wake-up exists only in router
    mode, and the app's requests name "koboldcpp", which the router does not
    wake. A preset that carries the key above 0 (KoboldCpp's own launcher
    exports it) would unload the model behind the app's back and the next
    reply would reach an engine with no model. So `adminunloadtimeout: 0` is
    written into the config the app stages for every launch and swap, over a
    preset's own value or none, the way `host` is (decision 14): the command
    line is frozen, KoboldCpp reads every key of `--config` at launch (1.112
    to 1.122.1 all have the key), and ignores this one on an admin reload, so
    the staged 0 is what a launch applies. `kKoboldAdminUnloadTimeout`; pinned
    by `test/services/kobold/kobold_admin_unload_off_test.dart` and, on a real
    engine, `test/live/kobold_launch_live_test.dart` (the engine reports
    `adminunloadtimeout=0` for a preset that asked for 300). The preset file
    is never edited.
19. A preset an older KoboldCpp saved is refused until it is updated
    (2026-10-05; "Don't even let it load the old style kcpps from the
    outset"). KoboldCpp turns an old setting name into the current setting
    when it starts, and only when the file lacks the current name
    (`convert_invalid_args`). A live reload first fills in every setting the
    file leaves out from the engine that is running, so the old name is not
    turned into anything and its setting is dropped without a word: the
    preset runs one way after Start and another after the first swap. So a
    preset with an old name and not the current one is refused wherever a
    preset reaches the engine, in the same places and the same way as
    decision 12 (`kcppsPresetProblem` is the one gate): Start, a live reload
    of chat, a helper or story swap, the editor's MMQ timing, and the
    phone's pick and model switch. The words say the preset was saved by an
    older KoboldCpp and has to be updated once, name the old settings, and
    say what to do: open it from "KoboldCpp presets…" and press Save.
    The list is every old name in 1.122.1's `convert_invalid_args`, refused
    when KoboldCpp would act on it (its own test: `usecublas`,
    `blasbatchsize`, `noblas`, `sdconfig` and `hordeconfig` when on; the
    rest whatever they hold): `usecublas` (`usecuda`), `blasbatchsize`
    (`batchsize`), `flashattention` and `useswa` (inverted, `noflashattention`
    and `noswa`), `noblas` (`usecpu`), the old combined `sdconfig` and
    `hordeconfig`, and the image settings `sdnotile`, `sdclipl`, `sdclipg`,
    `sdgendefaults`, `sdclipgpu` (a null `sdclipdevice` counts as missing)
    and `sdvaecpu`. Not `sdt5xxl`: it became `sdllm` only in 1.122.1, and
    1.117.1 still writes it alone as the setting itself. Save writes the
    current names whether or not anything was edited (`kcppsWithCurrentNames`,
    applied by `kcppsMergeEdits`), each with what KoboldCpp gives it at
    Start; the card and the batch stay under both spellings, as the writer
    writes them. A file that has the current name too is not refused:
    everything the app writes, and KoboldCpp's own export (the 1.117.1 export
    in `test/fixtures/kcpps/` passes), carry both. `hordeconfig` with a Horde
    key in it (a list of more than four) is refused as risky under decision
    12, even beside the current names, since KoboldCpp takes the key from it
    on every load. There is no one-tap "Update" beside the refusal: the
    refusal is shown by the editor, the desktop's Local model card and the
    phone's Models page, which this change leaves alone, so the editor's
    Save is the route.
20. The phone's Restart and the character creator's model change check
    before they stop anything (2026-10-05), as the desktop's Start and
    Restart buttons do: `koboldLaunchProblem` first, and on a problem (a
    model file that has gone, a preset the app will not start from) the
    running engine is left alone and the reason is said where each says how
    a start went (`refused` beside the phone's buttons, the creator's status
    line). They used to stop the working engine and then have the start
    refused, leaving chat with no engine. The start's own stop order is
    unchanged.
21. Old wrong links from a model to a preset are cleaned up once
    (2026-10-05, "Clean up once"; Phase 9 MF3 part 3c). Before Phase 9 a
    preset was kept under whichever model a screen showed, so a preset that
    loads model B could sit under model A and choosing A started B. When
    the app starts, once (`repairKoboldPresetLinks`, run by the storage
    service after the settings load), a link is removed only when its
    preset names a different model and that model's file is on this
    computer; each removal is logged in plain words. A right link, a preset
    that names no model, a preset whose file is gone and a preset naming a
    model that is not here are kept, and nothing else is touched. That it
    ran is recorded (`kobold_preset_links_repaired`, beta-aware).
22. One rule for who sets the context (2026-10-05): the chosen preset does
    while KoboldCpp is the backend and a preset is chosen
    (`koboldPresetOwnsContext`, `BackendSettings.presetOwnsContext`); on
    another backend a preset left chosen is not read and the context is the
    user's. Every place that sets the context follows it and says why in
    the same words (`kPresetOwnsContext`), on the page rather than only in a
    tooltip (`PresetContextLock`): Settings → Advanced and → Generation, the
    Model Settings dialog, the creator's setup step, a chat's own settings,
    and on the phone the Settings save, the Local model card's context
    route and the Settings page (`presetOwnsContext` in `web_ui`). The
    Generation tab and the creator had no lock; Advanced, the dialog and a
    chat's settings locked on any backend. The Advanced tab's context card
    holds the cache setting too: a preset is launched as written and the
    app's cache setting is never read for it, so that card is locked whole
    and says both (`kPresetOwnsContextAndCache`). The phone has no cache
    setting.
23. The user's own chat length comes back (2026-10-05). Choosing a preset
    still copies its context in as the context in use (the prompt budget,
    the cards and the phone read that one number), but the user's own is
    kept when a preset is first chosen (`context_size_before_preset`,
    beta-aware) and comes back when the preset is cleared or a model with
    no preset of its own is picked; going from one preset to another keeps
    it, and so does a restart. Every pick on both surfaces goes through
    `setActiveKcppsPath` (`ChatContextFields.followPresetContext`), and so
    does a launch that drops a preset whose file is gone or that the app
    wrote itself. A kept number comes back exactly, under 16,384 too (it is
    the user's, and the below-16K warning says what that means). With none
    kept (a preset chosen before the app kept it, an upgrade), clearing
    keeps the number in use but never leaves it under 16,384. A different
    number the user sets while a preset is chosen (possible only on another
    backend, decision 22) becomes their own; the unchanged context the phone
    sends back with every save does not.
24. While the preset editor's speed test runs, the app's own requests wait
    for chat's model (2026-10-05). The MMQ timing loads its own preset for
    about a minute, and a reply asked meanwhile, from the desktop or the
    phone, was answered by that preset. Chat replies, and the turn's judges,
    passes and tool calls, now wait in front of the line until chat's model
    is back; the test's own prompts and the system-role check of its model
    go through. Details under "Stage 9", "The speed test holds the app's
    requests".
25. Replaced on 2026-10-06 by decision 26: nothing weighs the open chat's
    slot any more. What it was: a chat is kept while the wait keeping it
    costs the user is less than
    reading it again (2026-10-05). A fixed limit on how long a save may take
    compared it with nothing: on the AMD card through Vulkan the first save
    of a short chat took 4.4 s and the keeper never helped, while a long chat
    takes far longer than that to read again. The whole save was weighed
    next, until the maintainer ruled the same day to count only the wait
    felt: a save runs right after the reply appears, while the user reads
    and types, so it costs nothing when it is done before the user's next
    turn starts, and only what is left of it when it is still running then.
    The load back before a reply always counts. Each save weighs that cost
    (the chat's last three saves and its last load) against reading the
    whole chat again at the speed KoboldCpp itself prints after every
    request; a chat with no wait measured yet is kept, a chat let go is
    tried again as it grows, and a first save into a new slot decides
    nothing. No setting and nothing on screen: one line in the engine log.
    Details under "Stage 9", the keeper.
26. One slot by default: the open chat's (maintainer ruling, 2026-10-06).
    The keeper kept the open chat plus as many recent chats as free system
    memory allowed, each up to a full context of RAM, for as long as
    KoboldCpp ran. Now it keeps exactly the open chat, and when the user
    leaves it (another chat, another character or a group, the phone's
    switch, back to the library) that chat is let go and, once none is kept,
    the slots are emptied so the memory goes back to the system. More is an
    Advanced choice, "Keep recent chats ready" (Settings → Advanced →
    Advanced Launch Options on the desktop, the Settings page on the phone):
    0 to 4 chats besides the open one, default 0, bounded by the same
    free-memory budget; those recent chats are not let go on leaving, only
    the ones past the count, the oldest first. Nothing about it is on the
    Local model card. One rule drives the keeper, auto mode's launch and the
    card for an auto launch and a preset alike (`koboldKeeperRoom`,
    `koboldKeeperChats`). KoboldCpp's own smart cache, which auto mode turns
    off for an ordinary model and the preset editor suggests as an expert
    choice, is untouched. Details under "Stage 9", the keeper.

    The open chat's slot is forced, never judged (added the same day, from
    user feedback). Decision 25's weighing let a chat go when its save and
    load looked dearer than reading it again, but the read speed it measured
    came mostly from short judge prompts, which read faster per token than a
    long chat (about 25% faster at 4K than at 32K of context without sliding
    window), so it under-counted the re-read and gave the chat up. With one
    slot there is nothing to weigh: every reply is saved and the next one
    loads it back, always, even on a machine short of memory, where the
    memory budget now bounds only the recent chats (the plan no longer stays
    out for lack of memory). The recent chats are not weighed either. The
    safeties stay as they were: a save that never answers in 45 seconds sets
    the keeper aside for that load, a preset with KoboldCpp's smart cache on
    keeps it out, a failure is remembered and the next auto start goes back
    to the smart cache, a swap, an idle unload or a reload drops every slot,
    and a model with recurrent layers keeps KoboldCpp's own smart cache.
    `KoboldFeltWait`, `KoboldReadSpeed` and the chat service's turn-start
    signal (`noteTurnStart`), which served only the weighing, are deleted;
    `parseKoboldSpeed` stays for auto mode's MMQ learning.
27. The batch is two settings, and auto mode starts by the card
    (2026-10-06). On an engine from 1.122 the app's own config always
    writes the logical batch 2,048 (`batchsize`, both spellings) and the
    physical batch it chooses (`ubatchsize`); an older engine, or one whose
    version is not known, gets the physical batch as the one `batchsize`.
    Every estimate (the fit, the Local model card's verdicts, the keeper's
    memory plan) keys off the physical batch. The physical batch starts at
    1,024 on every NVIDIA card (a 6 GB card read faster at 1,024 than at
    512) and at 512 on ROCm, Vulkan, Apple Silicon and with no card. Memory
    is a ceiling only: a batch that puts fewer layers or experts on the card
    than 512 does is never used. A model with recurrent layers never runs
    below 1,024 on Vulkan (KoboldCpp issue 2402: garbage at 512), a batch
    chosen in Settings included. Nothing is tried at start-up: auto mode no
    longer takes "the largest that fits". A preset runs as written.
28. The speed test runs when the user asks, and its winner is a real preset
    (2026-10-06). The Local model card (desktop, and the phone's Models
    page) has "Find the fastest settings for this computer". It asks first
    with a real estimate, then times one setting at a time with the best so
    far: the physical batch (512, 1,024, and 2,048 only with plenty spare),
    MMQ (CUDA and ROCm), mmap, memory lock (only with layers set by hand and
    not for a MoE model) and flash attention (only where it can run and the
    chat memory is full size). Each try is one reload and one timing prompt
    that reads about 2,000 tokens and writes 200; the score is a whole turn
    (1,000 read and 200 written at the speeds KoboldCpp printed). Cancel
    stops after the current step and puts the model back. While it runs a
    chat message is refused with how long is left. The winner is saved as
    "<model file> (measured on <card>)" through the preset library, linked to
    the model, and auto mode runs its settings for that model from then on;
    the card says one line of outcome words and no settings. Declined or
    never pressed, nothing changes. Details under "Stage 10".

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
for the model and exists), `host: 127.0.0.1` (decision 14),
`adminunloadtimeout: 0` (decision 18), and
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
vision file, `host: 127.0.0.1`, and `adminunloadtimeout: 0`. Launch is
`--config <staged> --port N --admin --admindir D`.
A swap reloads the staged file by name, with no file links (Stage 4; until
it lands, a swap back to a user's preset still links the user's own file).

**Only these stay on the command line:** port, admin, admin folder.
KoboldCpp protects them from being set by a config. The listen address is
protected on a reload too, but a launch reads it from the config, which is
why it rides in the staged config and not on the command line (decision 14).
The one config the app stages without it is the preset editor's speed
trial, which is only ever live-loaded.

**The estimate is a guess, not a setting.** The "VRAM Usage Estimate" in
the preset dialog has never decided how a model is loaded. KoboldCpp fits
the model. The estimate guesses how that fit will come out (for a MoE
model: the active weights on the card, the experts in system memory) so the
user can pick a context size, batch size and cache type that fit in what is
left, and the model runs at full speed. Nothing in this rewrite removes it,
and the preset editor (Stage 6) keeps it.

The older memory bar in Settings → Advanced → Hardware & GPU is retired
(2026-10-05). It added the whole model file to a rough cost for each token
of chat, leaving out sliding window, flash attention, the working memory
and the engine's own share, so the same model showed one figure there and
another on the Local model card. The section keeps the card's name and its
memory and points to the Local model card, which judges the model with the
same estimate as the editor (`KoboldFit`). Its helpers went with it
(`GGUFParser.getKvCacheBytesPerToken`, `ModelManager.getKvCacheBytesPerToken`
and `getCachedModelArchitectureInfo`, `GGUFModelInfo.estimateBytesPerLayer`).
The phone never had the bar.

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
generate. "Since the request" counts from before the request is sent
(2026-10-05; `since` on `waitForSwap` and `waitForUnload`, noted by the
host as `adminAskedAt` and by the idle unload and load back): counted from
when the answer was read, an app busy for longer than the engine's half
second to restart saw a new process no younger than its wait, never
counted it, and waited out the whole limit; a reply after an idle load
back hung. On a shared engine `GpuSwapOccupancy` does not unload first and
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
failure. Since 2026-10-05 it also goes on the status line
(`modelLoadingStatus`, in place of the loading step it stopped in) until
the next Start or Stop, so every screen that shows that line says why:
the desktop Local model card under its header while stopped, the home
screen's status bar (which moves only while starting or loading, and says
why only while chat runs on KoboldCpp, `KoboldHomeStatus`, as the phone
shows its local cards only then), and the phone's Local model card and
Local backend card through `statusMessage` (no new field). A start's readiness poll listens only for the process it
started: after an exit, anything that answers on the port (a leftover
KoboldCpp, another program) no longer marks the dead engine ready, which
had wiped the sentence; stop and exit handling are unchanged. Proven on a
real engine: killed mid-reply, the app says it stopped while answering.
When the ROCm build dies on its first reply with
flash attention on (mid-answer, with no reply finished since that process
started: a per-process flag set by its first "CtxLimit:" line, read as
whole lines so one that arrives in two reads still counts, as decision 10
says; built 2026-10-05), a per-machine flag is set, Flash Attention is
switched off in Settings and the engine started again once without it (out
of memory does not trigger it); a later crash only stops, with its reason.
`koboldFlashAttentionRuns`
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
  A save writes only what was edited, a group at a time, and placement
  (`gpulayers`, `autofit`, `autofitpadding`, `moecpu`) is one group, so a
  file's own `moecpu` that the form does not hold (beside automatic layers,
  where the form's forced fit writes none) goes when placement is edited.
  The editor says so once before that save (2026-10-05, review row 360-8):
  "Replace this preset's MoE setting?", with Cancel keeping the file as it
  was (`saveReplacesOwnMoe`). A `moecpu` the form shows (placement by hand)
  is the user's own edit and is not asked about.
- The display name is the file name. Renaming moves the file and every
  setting that points at it (chat, each model's preset, the helper model,
  Porch Stories jobs); deleting lets go of them. One listing
  (`kcppsPresetFiles`) serves every picker.
- Free memory is read before each launch (nvidia-smi, the AMD driver,
  vm_stat, /proc/meminfo, FreePhysicalMemory) and kept as "free before the
  engine": a reading taken while the app's KoboldCpp runs would count the
  model against itself.
- Auto mode tunes silently: the physical batch by the card (decision 27,
  which replaced "the largest of 512/1024/2048 that keeps as much of the
  model on the card as 512 does" on 2026-10-06), or what the speed test
  measured for the model (decision 28), within the same memory ceiling (an
  "Auto" chip, the default, in Advanced; a chosen batch is kept); smart
  cache slots that fit in free system memory (3, or KoboldCpp's 7 for a
  recurrent model).
  Context shift (decisions 7 and 9): KoboldCpp's source keeps a slot for
  a regenerated reply and a checkpoint part way into a long prompt for a
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
  another backend) ends a trial that is open. Since Stage 10 the editor's
  timing and the speed test share one timing loop (`koboldTimeSettings`):
  one timing per setting, scored as a whole turn from KoboldCpp's own
  speed line, not the wall clock; a launch that runs measured settings
  pauses the reply learner, and the speed test's MMQ answer is kept for
  the card as the editor's is.
- The "Local model" card on the KoboldCpp settings page is auto mode's
  only surface: how the model runs, in plain words, and the context, with
  a verdict per size from a read-cost model (weights a token uses plus the
  whole chat memory; system memory counted six times the card; extra
  reading from the disk over a GB is "very slow"). Below 16,384 is always
  "not recommended or supported", even for the size in use. The sizes
  offered go up to the length the model was made for, whatever it is
  (2026-10-05, `koboldContextMost`, the same ceiling as the preset
  editor's slider): past 131,072 for a model made for 262,144, and no
  further than 8,192 for a model made for 8,192, which also gets a plain
  warning (`koboldShortModelWarning`, `auto.warning` on the phone). The
  size in use is always offered. With "Set layers myself" on (2026-10-05)
  the card's facts use the real settings (the layer count, the memory lock,
  the experts a MoE model keeps in system memory, as the launch writes
  them), its speed line and verdicts come from that fixed layer count
  (`koboldPlacedLoad`) at the batch the launch tunes, and it says "Set up
  by hand in Advanced settings." with no layer numbers; a context that does
  not fit on the card that way is too big, the size in use included, since
  KoboldCpp does not fit layers set by hand. The phone reads the same facts.
  The figures do not model the memory lock itself. The card, the
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
as on the desktop. On an Intel Mac host, which cannot run KoboldCpp
(2026-10-05), `/api/backend/status` says `localUnsupported: true`
(additive), and the phone hides the Local backend, Local model and preset
cards and says the desktop's sentence instead (`kIntelMacLocalUnsupported`,
the same words in `web_ui/src/backendOptions.ts`), whatever the backend, as
the desktop's Backend tab does. Installed models lose their "Use" there,
and the Side jobs host picker greys out KoboldCpp with the same sentence, as
the desktop's does. A Mac counts as an Intel one only once `uname -m`
has answered (`BackendManager.architectureKnown`): before, every Mac was
"Intel" for the moment after start-up. The first-run setup and the engine
download wait for the answer, the desktop redraws when it comes, and the
phone's Models page and host picker keep asking while it says
`localUnsupported`, so they follow the answer rather than the first one.
The phone Settings' chat backend picker (`SettingsPage.tsx`) still offers
KoboldCpp on an Intel Mac: not changed here.

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
  to make a split. A preset's own split (`tensor_split`) is kept as
  written, except when an edit switches a CUDA preset from every card to
  one named card (2026-10-05): the split goes with it, since KoboldCpp
  pins the named card only when there is no split (1.122.1 and 1.117.1
  alike); `kcppsMergeEdits`.

Stage 8 as built, unload when idle (2026-10-04): a setting, off by
default, `kobold_idle_unload_minutes` (off, 10, 30 or 60) in
`kobold_launch_fields.dart`, set from a chip row in Advanced Launch Options
and a card on the phone's Settings page (`koboldIdleUnloadMinutes` on
`/api/settings`). The clock is `kobold_service_idle.dart`, a part of
`KoboldService`: started by a launch, stopped by a stop or dispose, it
checks every 30 seconds. KoboldCpp's own idle unload is never used and is
held off in every staged config (decision 18). Every request (the stream
and `_runSerialized`, which carries tool calls and the system-role probe),
a swap, a load and a launch reset it. When the engine is the app's own process, its model is
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

### Stage 9: the slot keeper (as built)

Decision 17, in detail (2026-10-05). KoboldCpp 1.112 to 1.122.1 have the
same four admin calls, the same default of five slots and the same lock.

**What KoboldCpp does** (read from its source, and checked live on 1.117.1
and 1.122.1)

- `POST /api/admin/check_state`, `load_state`, `save_state` and
  `clear_state`, body `{"slot": n}`. They need `--admin`, an existing
  `--admindir` and the admin password; the app's engine has the first two
  and no password (decision 14). With any missing, or no model loaded, the
  answer is HTTP 200 `{"success": false}`: the reasons cannot be told apart.
- Five slots when smart cache is off; a slot number past the limit becomes
  slot 0. `check_state` lists each slot's tokens and size and the tokens in
  the cache now.
- The calls wait in the generation lock, as a generation does, and block
  under the default `--multiuser 10`. A client that disconnects aborts its
  generation and releases the lock. Token counts, perf and abort run
  outside it and never touch the cache.
- A save copies the whole llama state (the cache cells in use and the
  recurrent state) into system memory, never graphics memory and never disk,
  and keeps the token list. It answers `success: false` when the copy
  cannot be allocated. A slot's buffer never shrinks, and there is no call
  to clear one slot: `clear_state` frees all of them. A load clears the cache
  and restores the slot; it compares nothing and fails only for an empty
  slot.
- What follows a load is an ordinary request. An attention model keeps the
  longest common start of the tokens (fast forward) and drops the rest of
  the cache, so a prompt that shares a long start with the slot reads only
  the rest, and a slot that does not fit only costs time. A model with
  recurrent layers needs the saved tokens to be a full start of the new
  prompt. KoboldCpp makes its own smart cache for it when fast forward and
  context shift are on (seven slots by default), and takes the snapshots
  that make it useful in the middle of a generation, which the admin calls
  cannot. The app can only save between requests, and the next chat prompt
  carries the reply inside the user message after a tail that changes every
  turn, so a saved state is never a start of it: the keeper stays out of
  those models.
- A reload, an idle unload and a swap replace the model process in admin
  mode, and every slot goes with it. So do Stop and exit.

**The line to the engine.** Replies, helper streams, tool calls and the
system-role check used to be sent at the same moment; only KoboldCpp's own
lock put them in order, and the app could not say which chat the cache held.
`KoboldRequestQueue` (`kobold/kobold_request_queue.dart`) is a first-come
first-served line. `KoboldService` takes a place when a stream is listened
to, a tool call is made, a system-role arm starts or a speed test (the Local
model card's, or the editor's timing) sends a prompt (`timeTurn`, a fresh
2,000-token prompt that changes the cache like any other, so it never
overlaps the save of a chat or a reply),
and gives it back when the stream ends, fails or is cancelled, or the call
returns. Auto mode's MMQ learning sends nothing of its own: it reads the
speed line of each reply. A reader that
cancels its subscription while the request still waits means it is never
sent. The Stop button does not do that: it sets the turn's cancel flag and
aborts the lanes, and the reader only notices at its next token. So a chat
reply carries `GenerationParams.stillWant` (false once Stop is pressed),
asked when its turn comes, before the model is woken or its chat loaded, and
again after the chat is loaded back; a reply the user stopped is not sent
and not saved. Who an abort belongs to: an abort closes the call on the wire
and tells the engine to stop, always, whoever asks (an eval that has its
answer, a tool call that timed out, a creator, the Stop button), except
while the editor's speed test has the engine (below). Taking a
waiting reply out of the line is a separate call, `dropStoppedReplies`, made
only by the Stop button and by the cancel-and-wait of a character or group
switch: a chat reply that still waits and whose turn was cancelled leaves at
once, which gets the chat back without waiting for the engine (a switch used
to sit behind the whole line), and the wire is left alone, because whoever is
on it is ahead of the reply and may be a pass of an earlier turn (journal,
growth) that cancelling this turn does not cancel. Stop aborts nothing when it
took a reply out of the line, whatever the lanes are: in the app a worker on
the same engine is the same service, and a test also has a second object over
the engine ask for the abort. Stop with nothing waiting aborts both lanes as
it always did, and the wait of a switch never aborts. A switch to another
chat still tears both lanes down once the wait is over (the greeting check
calls `cancelRealismEval`), as it always did, so that is where a pass of the
chat being left is cut. Perf, token counts and swaps stay outside the line.
`waitForIdle` means "what is in line at this moment". The line comes first,
the swap lock second; a swap never takes the line. No count of aborts decides
whether a waiting reply is dropped: many callers abort on purpose (the eval
engine after an early JSON, tool timeouts), and an abort that is not the Stop
button must cut the wire even while a reply behind it has been given up on.
The count is only used after the fact, to tell a reply that an abort closed
(its cache is as it left it, worth keeping) from one that broke.

**The speed test holds the app's requests** (maintainer ruling, 2026-10-05).
The preset editor's MMQ timing loads its own preset for about a minute and
puts chat's model back after. While it runs (`holdForSpeedTest` to
`endSpeedTestHold`, in `timeMmq`), every request the app makes waits for
chat's model in front of the line: chat replies (impersonate included), and
the turn's other work, its judges and passes, other streams and every tool
call, the sidebar's tool test included. Answered by the test's preset, a
judge would score the turn with another model than the reply's, and it is
asked before the reply, which waits anyway; the waits are well inside an
eval's own (180 s to the first chunk, 6 minutes for a named tool call; only
a forced one-shot pass, at 75 s, could give up and fall back as on any slow
engine). The tool test only keeps an answer for the model that is loaded
when it ends, so held, it tests chat's model. What goes through is what is
the test's: its timing prompts, and what a load of its preset starts by
itself, the system-role check, which has to measure the model loaded under
that model's name (holding the whole line would make it measure chat's
model under the test's name). Waiting in front of the line, not in it, is
what lets those through: a held request with a place in the line would keep
the test's own prompts behind it. The hold first waits for what is already
in the line, saves included, so the test's load never cuts a reply. A held
reply is a waiting reply: Stop takes it out at once (`stillWant`,
`dropStoppedReplies`) and it is never sent. Once the line is drained,
nothing of the app's is on the engine, so an abort (Stop, a check that timed
out while it waited) cuts the wire but does not tell KoboldCpp to stop: that
would stop the test's prompt. The status under the chat says "Waiting — the
speed test is using the model", on the desktop and the phone
(`LiveGenProgress.heldBy`, sent in words as `busyWith`). The hold ends also
when chat could not be put back (the refusal is said as for any reload), so
chat never waits for good.

**Who is a chat.** `GenerationParams.kvChat` is the chat's session id. Only
`paramsOf` (send, Continue, regenerate, every group speaker, Scene Guest and
cast turns, all of which build their request there) and impersonate set it.
Every other request is a helper, and the tool call ignores the field. A
helper that carries it by mistake costs speed and nothing else.

**The keeper** (`kobold/kobold_slot_keeper.dart`), one for each service and
each load of the model (`KoboldService.loadGeneration`).

- A new load empties its table without any call: the slots died with the
  model process. What the engine is given decides, once, whether it acts
  (below).
- The first chat reply looks at the engine once (`check_state`). It stays
  out when admin is off, when a slot is already used (someone else's), or
  when the engine fails. Chats kept are the plan's, never more than the
  engine's slots.
- Before a reply it loads the chat's slot unless the engine still holds the
  chat. An empty slot drops that chat only. A chat that comes back with a
  token count more than two off means something else uses the slots, and
  the keeper steps aside. A busy answer (429 or 503) is skipped for now.
- It keeps the open chat and as many of the chats used before it as
  Settings asks for (decision 26; none by default). Chats kept:
  `koboldKeeperChats(recent: the Advanced count, room: the plan's room)`,
  read at each use, so a change applies without a restart.
- After a reply (finished, the reader left, or Stop closed the call; not one
  that failed) it saves into the chat's own slot, else a free one, else the
  least recently used chat's, never the open chat's. A chat that is not the
  open one (left while its reply was written) is saved only as a recent
  one, when Settings asks for any, and is otherwise not saved at all. The
  line is held until the save is done, so a
  helper asked meanwhile goes out after it, and the reader is not kept
  waiting. The engine counts as busy for the idle unload until then too: the
  idle time runs from the end of the save, not from the end of the reply. A
  save the engine cannot make steps the keeper aside and clears the slots to
  give the memory back.
- Nothing weighs a save (decision 26): the open chat is saved after every
  reply and loaded back before the next, however long either takes and
  however fast KoboldCpp reads. A save that never answers in the call's 45
  seconds lets every chat go for the load instead: what its slot holds is
  not known, and an engine that cannot save in time is short of something.
  One plain line in the engine log says so, and it is not a failure, so
  nothing is remembered.
- A reply that carries pictures (`GenerationParams.images`) is a helper to
  the keeper: no load before it and no save after it, because a load does not
  restore the engine's record of which pictures are in the cache. The next
  plain reply loads the chat as it was saved before the picture.
- A deleted chat is let go at once. Every way of deleting one (a chat from the
  app or the phone, a character with its chats, a group) ends in
  `AppDatabase.deleteSessionById`, and the Settings cleanup, which removes
  chats no character or group owns any more with its own query, says the
  same of each (`noteSessionsDeleted`). The word goes to `ChatService` (it
  follows the database it is given, also after a swap; closing a database
  ends it), which tells the keeper. The table
  drops the chat, so its slot is the first free one for the next chat and it
  is not kept over a live one; a save that was already running when the chat
  went does not bring it back, and a reply that ends after the chat went is
  not saved at all, so it pushes no live chat out. The one loss left: with
  every slot in use, a save that was already running took the least
  recently used chat's slot before the delete came, and wrote over that
  chat's cache, so both chats leave the table (the others stay). No order
  avoids it without guessing: a save needs its slot before anything is known
  about how it ends, and putting the old chat back in the table would claim
  a cache that is gone. KoboldCpp cannot empty
  one slot (clearing is all of them, which would lose the other chats), so
  the engine is not called: what it holds there stays until that next save
  writes over it, and the memory was counted for every slot full anyway.
- Leaving a chat (decision 26). Which chat is open has one source:
  `ChatService`'s session id is a setter, and every change to a chat tells
  `KoboldService.openChat`: a new chat, another character, a group and back,
  a fork, an import, the chat that replaces a deleted one, and the phone's
  switch, which goes through the same `ChatService` methods
  (`ChatSessionFacade`, `ChatFacade`). A switch passes through no
  chat (null) on its way and only the chat it lands on is told, so opening
  the same chat again does not drop it. The desktop chat page counts itself
  in and out (`chatScreenOpened`, `chatScreenClosed`): when the last one
  closes the user went back to the library, and no chat is open. A reply
  makes its chat the open one too, so a chat the phone keeps using while the
  desktop sits in the library is kept again from its next reply. The keeper
  only notes the open chat; what it lets go of waits its turn in the line
  (`settle`), behind a save still running for the chat being left, and never
  wakes a model unloaded for being idle (its slots went with it). It lets go
  of the chats other than the open one past the recent count, the oldest
  first, and once none is kept it empties the slots (`clear_state`), which
  gives their memory back; the next save into a slot makes its buffer again
  and so decides nothing about cost. While any chat is kept, a slot let go
  stays allocated until a save writes over it: KoboldCpp can only empty them
  all. One engine log line says the memory was given back.
- A helper, and a coding session on the engine (`keepLoadedFor`), clear "the
  engine still holds the chat". The keeper waits out a coding session.
- Every call runs in the swap lock and is skipped when the model changed
  first, has one try and 45 seconds. The keeper never throws into a reply:
  any failure is a step aside for that load (a save that runs out of time is
  one too, without being remembered, above), and the engine log says so
  once, in plain words.

**The plan** (`kobold/kobold_keeper_budget.dart`). The keeper stays out of:
an engine the app did not start, a config with smart cache on, fast forward
off, a model that could not be read, a model with recurrent layers, sliding
window left to KoboldCpp for a model that has it, and parallel requests
above one. Its room (`koboldKeeperRoom`): the smart cache slot arithmetic
with KoboldCpp's five as the wish, a full context counted for each (slot
buffers never shrink), the model's own system memory and 2 GB set aside;
unknown figures have room for one. On a Mac graphics and system memory are
one pool. How many it keeps is `koboldKeeperChats` of the Advanced count
(above) and that room: the open chat always, even with no room (memory never
keeps the keeper out), and the recent chats as far as the room goes; the one
rule for an auto launch and a preset alike.

**Auto mode and the way back.** `KoboldAutoTuning.chats` is that room for
the fit, `KoboldAutoTuning.recurrent` whether the model stays with
KoboldCpp's own smart cache, `cacheSetting(keeper:)` what to write. An
ordinary model gets no
smart cache and context shift on; a model with recurrent layers is as it
was (KoboldCpp's own smart cache). The preset editor, its suggestion and a
preset's own settings are untouched. A failure at run time in an auto-mode
launch (a save the engine cannot make, a call that errors, a chat that comes
back changed, all after a first look showed the engine can keep chats; not
the keeper choosing to stay out, not a save that never answered in time,
not a first look that finds nothing or fails,
which may be an engine still starting or a blip and only steps aside for that
load, and not a preset) is remembered in `kobold_keeper_failed` beside the other KoboldCpp preferences
(engine version and model file), under the same prefix, so a beta never
reads a stable library's. The next start of that model on that engine
version writes the smart cache auto mode wrote before and says so in the
engine log. A new engine version tries the keeper again.

**Words.** The Local model card says "Going back to another chat is quick."
for an ordinary model when two or more chats are kept, by the same rule as
the keeper (`koboldKeeperChats` of the Advanced count and the room): so by
default it says "Going back to another chat takes a moment to catch up.",
and "quick" only once Advanced keeps a recent chat and memory has room for
it. The desktop card's memo key includes the count. The words are built in
Dart (`KoboldStatusFacts`) and reach the phone through the facade. The one
setting is "Keep recent chats ready" (decision 26): a row of chips in
Advanced Launch Options (`KoboldKeepRecentRow`, sharing `LaunchChoiceRow`
with the idle unload row), and on the phone a card beside the idle one
(`KeepRecentChatsSettings`), read and saved through `/api/settings` as
`koboldKeepRecentChats` with its choices (additive keys).

**Tests.** `kobold_request_queue_test` and `kobold_requests_wait_test` (the
line, over real HTTP), `kobold_slot_keeper_test` and
`kobold_keeper_plan_test` (the rules; each rule was broken once to see it
fail), `kobold_slot_api_test` and `kobold_slot_keeper_engine_test` (the
service against `test/helpers/fake_kobold_engine.dart`, a KoboldCpp
stand-in on a loopback socket that copies its lock, its slots, its fast
forward and its disconnect behaviour), `chat_slot_keeper_paths_test` (which
requests name a chat: send, Continue, regenerate, impersonate, a group
speaker, a Scene Guest and a voice call do, the judges, the suggestions and
the doorbell do not; and two runs of `ChatService` through the real service
on the stand-in), `chat_stop_while_waiting_test` (the real Stop button and a
character switch on a reply that waits behind another request, and the chat
they leave), `chat_deleted_chat_slot_test` (a chat, a character's chats and a
group deleted for real, and the phone's delete; the slot is let go and taken
by the next chat), `kobold_slot_keeper_forget_test` (a delete while the
chat's save or its reply is running) and `kcpps_editor_mmq_line_test` (the editor's real
timing waits for a save that is running, and a reply waits for it),
`kobold_speed_test_hold_test` (the editor's real timing and a real chat on
the stand-in, which knows the model answering each request: a reply sent
meanwhile is answered after by chat's model, a reply already running and
its save finish before the test loads its preset, the turn's judge and tool
call wait too, the system-role check of the test's model goes through, Stop
takes a held reply out without stopping anything, and an abort meanwhile
leaves the test's prompt alone), `generation_status_held_test` and
`ChatMessageList.genStatus.test.tsx` (the words on the desktop and the
phone), `kobold_slot_keeper_slow_save_test` (a save that runs out of
time, over real HTTP, lets every chat go for the load, without being
remembered), `kobold_keeper_idle_test` (the idle
clock counts from the end of a slow save), `kobold_wire_test` (the abort
handle, over real sockets), `kobold_auto_keeper_test` (what auto mode writes
and the way back), `chat_keeper_open_chat_test` (decision 26, through the
real chat service on the stand-in: by default a new chat, another
character, a group and back, the phone's switch through the web facade and
the chat page closing each let the chat left go and give its memory back,
a chat opened again is kept again, a reply still being written when the
user leaves is not saved; with "Keep recent chats ready" that many chats
left stay, the oldest goes first, going back to one loads it, the library
keeps them, lowering the count lets the extra ones go at the next switch,
and deleting the last one kept gives its memory back),
`chat_keeper_always_saves_test` (the slot is never weighed: a save slower
than reading the chat again at the speed KoboldCpp reports, with the next
message waiting for it, keeps the chat, and the next reply loads it back;
red on the code that weighed it), `kobold_keep_recent_rule_test` (the rule,
the room, and the card's words by it), `settings_keep_recent_test` (the phone's setting through the
real `/api/settings` route and facade), `kobold_keep_recent_row_test` and
`KeepRecentChatsSettings.test.tsx` (the desktop chips and the phone's card),
and `test/live/kobold_slot_keeper_live_test.dart`
(below). The
existing live suites (launch, swap, reload check, web card, presets) pass on
1.117.1 and 1.122.1 with the keeper in. Existing tests changed because the
behaviour they pinned is
the thing replaced: `kobold_abort_ownership_test` (two requests can no
longer be open at once; the rule that a finished request lets go only of its
own hold is pinned in `kobold_wire_test`), `kobold_auto_launch_test`,
`kobold_awaited_hardware_test`, `kobold_stage_header_cache_test` and
`test/live/kobold_presets_live_test.dart` (auto mode no longer writes
`smartcache: 3` for an ordinary model). Changed for decision 26, because
each pinned recent chats kept by default: `kobold_slot_keeper_engine_test`
("going back to another chat loads that chat"), `chat_deleted_chat_slot_test`
(its chats are deleted after the user moved on, so kept only as recent
ones), the card's "quick" case in `kobold_auto_keeper_test`, and the long
chat in `test/live/kobold_slot_keeper_live_test.dart` (a second chat while
the first stays kept); each now turns on the Advanced count it relies on.
Deleted or changed because the open chat's slot is now always kept and the
rule they pinned no longer exists: `kobold_slot_keeper_cost_test`,
`kobold_slot_keeper_felt_test`, `kobold_felt_wait_test` and
`chat_turn_start_felt_test` (the weighing, the wait felt and the chat
service's turn starts), `kobold_read_speed_test` (`KoboldReadSpeed` is
deleted), the speed-line case of `kobold_slot_keeper_slow_save_test` (its
45-second case stays), the no-room cases of `kobold_keeper_plan_test` and
`kobold_auto_keeper_test` (no room no longer keeps the keeper out), and the
let-go check and its sizing notes in the live test.

**Path-complete** (`docs/design/path-complete-chat-work.md`). The keeper is
transport only: it reads and writes no message, metadata, Realism, Needs,
Journal, Growth or Pockets state and changes no prompt text. The one thing
it keeps is a table of saved caches by session id.

| Event | What happens | Done |
|---|---|---|
| Normal send, 1:1 | the pre-reply judges are helpers; the reply loads the chat's slot, then saves | yes |
| Normal send, group, per speaker | one slot for the group's session; each speaker's dance is helpers; load and save around each speaker's reply | yes |
| Continue | a chat reply like any other (it builds its request in `paramsOf`): load, reply, save | yes |
| Regenerate | the judges re-run (helpers), then the reply loads the chat's slot (prompt and old reply) and reads only what differs | yes (live: 1 token) |
| Swipe | navigation; past the last alternate it is a regenerate | n/a |
| Delete, edit history | nothing is recorded per message; KoboldCpp compares the tokens and reads from the first one that changed | n/a |
| Delete a chat (app or phone), a character with its chats, a group, the Settings cleanup of chats nobody owns | the keeper lets go of each chat's saved cache; its slot is the next one used | yes (a test each) |
| Leave a chat: a new chat, another character, a group and back (1:1 and group), a fork, an import, the phone's switch, back to the library (decision 26) | the session id setter (or the chat page closing) tells the keeper the open chat; in the line, the chat left is let go unless Advanced keeps it as a recent one, and with none kept the slots are emptied; a reply that ends after its chat was left is not saved | yes (a test each for a new chat, another character, a group and back, the phone's switch and the library; fork and import change the session id through the same setter) |
| Any reply above, however slow its save (decision 26) | every reply path ends in the same save (`chatEnd`), never weighed: the open chat is kept and the next reply loads it back, whichever path it came from | yes (a test with a save slower than reading the chat again) |
| Scene Guest turn | the guest's line is a reply like any other (`paramsOf`), named with the host's chat | yes (a test) |
| Voice call message | the same send path in call mode: a reply naming the chat | yes (a test) |
| Any of the above while the editor's speed test runs (desktop or phone) | the reply and the turn's judges, passes and tool calls wait in front of the line until chat's model is back, then go as they would have; Stop takes a held reply out | yes (tests) |
| Prompt paths (full, Continue partial, overflow, impersonate) | no prompt text changes; impersonate is a chat request | n/a |

Twins checked: the judges, trust repair, one-shot and the post-reply fusion
(all helpers through the same line); the doorbell's recipe cards, whose round
is built from the mouth's prompt but whose parameters are rebuilt for the side
lane (`clerkSideLaneParams`) and carry no chat, and `generateWithTools`, which
would ignore one anyway (a test on each side); `paramsOf` against impersonate,
Scene Guest and the voice call (all name the chat; a test each); 1:1 against
group (one session id each; a test); desktop against web (the words are
built in Dart; the "Keep recent chats ready" setting on both, through one
facade key; a test each). The web and phone call the same service methods,
so their chat switches go through the same session id setter.

**Live** (`test/live/kobold_slot_keeper_live_test.dart`): ten chat turns,
about 1,500 tokens of rules and 200 more of history each turn plus a changing
tail of 300, three helpers of 600 to 1,200 tokens after each turn (two
streams and a tool call), then a regenerated reply; once with the keeper off
and once on. What the engine says it read (`Processed:` in its own log) is
the measure. The tables below were taken with those 1,500 tokens of rules;
the test now has about 11,000 (it grew while a weighing decided whether a
chat was worth keeping, which a short chat on the 0.5B model failed; that
weighing is gone, decision 26, and the long chats stay because they show
what the keeper spares more clearly).

Measured on Apple Silicon (a Mac with 128 GB, busy with other test runs at
the time, so the times are rough). "read" is what the engine says it
processed for each reply, "first token" is the time from asking to the first
word, the keeper's load included. Two models (Qwen2.5-0.5B at Q8, Qwen3-VL-8B
at Q2_K) on two engines (1.122.1 and 1.117.1):

```
koboldcpp-mac-arm64-1.122.1 with Qwen2.5-0.5B-Instruct-Q8_0.gguf
turn   prompt  keeper off read   first token    keeper on read   first token
1        1521        1533        366 ms         1533        414 ms
2        1701        1713        406 ms          424        469 ms
3        1874        1886        406 ms          420        473 ms
4        2045        2057        409 ms          416        454 ms
5        2228        2240        408 ms          426        468 ms
6        2401        2413        400 ms          425        461 ms
7        2579        2591        402 ms          425        463 ms
8        2751        2763        399 ms          419        457 ms
9        2923        2935        400 ms          416        456 ms
10       3104        3116        398 ms          425        458 ms
regen    3104        3116        403 ms            1        466 ms

koboldcpp-mac-arm64-1.122.1 with Qwen3-VL-8B-Instruct-Q2_K.gguf
turn   prompt  keeper off read   first token    keeper on read   first token
1        1521        1533        660 ms         1533        695 ms
2        1701        1713       2258 ms          424        491 ms
3        1874        1886       2047 ms          419        750 ms
4        2045        2057       2122 ms          416       1360 ms
5        2228        2240       1979 ms          426       1316 ms
6        2401        2413       2078 ms          425       1323 ms
7        2579        2591       2551 ms          425       1637 ms
8        2751        2763       2716 ms          419       1497 ms
9        2923        2935       2722 ms          416       1483 ms
10       3104        3116       2862 ms          425       1554 ms
regen    3104        3116       3250 ms            1        509 ms

koboldcpp-mac-arm64-1.117.1 with Qwen2.5-0.5B-Instruct-Q8_0.gguf
turn   prompt  keeper off read   first token    keeper on read   first token
1        1521        1533        577 ms         1533        601 ms
2        1701        1713        592 ms          424        460 ms
3        1874        1886        655 ms          420        472 ms
4        2045        2057        828 ms          416        475 ms
5        2228        2240        825 ms          426        468 ms
6        2401        2413        861 ms          425        471 ms
7        2579        2591        839 ms          425        464 ms
8        2751        2763        906 ms          419        456 ms
9        2923        2935        996 ms          416        454 ms
10       3104        3116       1019 ms          425        474 ms
regen    3104        3116        671 ms            1        477 ms

koboldcpp-mac-arm64-1.117.1 with Qwen3-VL-8B-Instruct-Q2_K.gguf
turn   prompt  keeper off read   first token    keeper on read   first token
1        1521        1533       2709 ms         1533       2113 ms
2        1701        1713       3214 ms          424        905 ms
3        1874        1886       3163 ms          420        551 ms
4        2045        2057       4036 ms          416        578 ms
5        2228        2240       4321 ms          426        617 ms
6        2401        2413       4608 ms          425        635 ms
7        2579        2591       5018 ms          425        615 ms
8        2751        2763       5223 ms          419        614 ms
9        2923        2935       5355 ms          416        570 ms
10       3104        3116       3441 ms          425        597 ms
regen    3104        3116       3123 ms            1        525 ms
```

With the keeper off every reply after a helper reads the whole chat again
(the prompt and about a dozen tokens of template: 1,713 to 3,116); with it on
a reply reads the new lines and the changing tail (416 to 426), and a
regenerated reply reads one token. The time follows the model. With the 0.5B
model reading is nearly free: on 1.122.1 the first token comes no sooner (it
is about 60 ms later, the load being a call of its own), on 1.117.1 it comes
at 454 to 475 ms instead of 592 to 1,019. With the 8B model it comes at 0.5
to 1.6 s instead of 2.0 to 2.9 s on 1.122.1 (a regenerated reply 0.5 s
instead of 3.3), and at 0.55 to 0.9 s instead of 3.2 to 5.4 s on 1.117.1
(regenerated: 0.5 s instead of 3.1). A load costs about 50 ms for the small
model and up to about a second for the 8B model at 3,000 tokens of chat (its
cache is about 150 KB for each token), so a machine that reads a prompt
faster than it copies its cache gains less.

A model with recurrent layers (LFM2-350M) on both engines: the keeper stays
out, `smartcache` is in the staged config with context shift on, the engine
log says once why, and KoboldCpp's own cache brings nothing here: every
turn, and the regenerated reply, reads the whole prompt.

```
hybrid LFM2-350M-Q8_0.gguf on koboldcpp-mac-arm64-1.122.1
turn   prompt      hybrid read   first token
1        1737        1750        360 ms
2        1929        1942        399 ms
3        2125        2138        409 ms
regen    2125        2138        407 ms

hybrid LFM2-350M-Q8_0.gguf on koboldcpp-mac-arm64-1.117.1
turn   prompt      hybrid read   first token
1        1737        1750        362 ms
2        1929        1942        408 ms
3        2125        2138        408 ms
regen    2125        2138        409 ms
```

A real chat through `ChatService` with Realism and Needs on (judges and
passes between the replies), on the 0.5B model: each reply after the first
found its chat's cache loaded (826 to 1,428 tokens) and read 460 to 683 of
its prompt, the new lines and the state zone that changes every turn.

```
real chat with Realism on, koboldcpp-mac-arm64-1.122.1
861 restored, 528 read
1223 restored, 683 read
1428 restored, 590 read
real chat with Realism on, koboldcpp-mac-arm64-1.117.1
826 restored, 460 read
955 restored, 583 read
1148 restored, 601 read
```

What a save and a load cost as one chat grows toward the 16,384 context
(measured with a chat that started at 2,252 tokens; the test now starts it
long): the save is timed as the line the
keeper holds after the reply, the load is asked of the engine for the same
slot, and "cache" is the slot's size as KoboldCpp reports it. A second chat
that is long from its first reply saves into a slot never used before.

```
long chat, Qwen3-VL-8B-Instruct-Q2_K.gguf on koboldcpp-mac-arm64-1.122.1
 tokens  cache  reply (read and written)  save  load
   2252    334 MB    1154 ms    211 ms    124 ms  2271 restored
   3646    540 MB     853 ms    214 ms     84 ms  3665 restored
   5052    747 MB    1084 ms    227 ms     84 ms  5071 restored
   6462    955 MB    1187 ms    240 ms    100 ms  6481 restored
   7858   1161 MB    1315 ms    253 ms     93 ms  7877 restored
   9259   1368 MB    1632 ms    276 ms    113 ms  9278 restored
  10654   1573 MB    1753 ms    317 ms    111 ms  10673 restored
  12044   1778 MB    1961 ms    320 ms    142 ms  12063 restored
  13448   1985 MB    2365 ms    337 ms    129 ms  13467 restored
   7862   1162 MB    6577 ms    214 ms    129 ms  7883 restored  (a new chat)
```

The same chat on 1.117.1: saves 201 to 395 ms, loads 72 to 105 ms; in a
second run, with the Mac busy with other work (its replies took three to
five times as long), saves 260 to 702 ms and loads up to 204 ms. The 0.5B
model on either engine: saves 183 to 215 ms whatever the length (its cache
is 12 KB a token, so the copy is small beside a fixed cost), loads 26 to 97
ms. Reading the new 7,862-token chat took the 8B model 5.4 to 6.6 s,
which is what a reply after a helper would cost without the keeper.

On the AMD card (RX 6900 XT, Gemma 4 12B Q4_K_M, the media server's run of
the first follow-ups): through ROCm the keeper read 401 tokens where the
keeper off re-read 2,272 (first token 0.67 s against 2.30 s) and a
regenerated reply 1 against 2,936 (0.56 s against 2.95 s); saves took 254 to
487 ms at 1.4 to 2.9K tokens and 513 to 707 ms from 2.1K to 13.8K tokens
(731 to 988 MB), loads 147 to 180 ms, and a first save into a slot never
used 1,263 ms (7.3K tokens, 2.3 GB). Through Vulkan (flash attention off for
Gemma 4 there, so the cache is full size) the first save took 4,390 ms at
1,442 tokens, over the three-second limit the keeper had then, so the chat
was let go and the keeper never helped (first token 2.37 s, as with it off).
Nothing weighs a save now (decision 26): the chat is kept however long its
saves take; whether later Vulkan saves are as slow is not known yet.

**Not done, on purpose.**

- The editor's MMQ timing runs after a swap that already empties the slots,
  so it needs no `keepLoadedFor`. It does not take the whole line either:
  the app's requests wait for it in front of the line instead (above), and
  its own prompts and the system-role check go through.
- A helper model that swaps in on the same engine before every reply empties
  the slots each time; a hint from the provider could put the keeper to
  sleep then.
- Saving older chats to disk instead of dropping them needs a KoboldCpp call
  that does not exist yet (LostRuins/koboldcpp#2520).
- Freeing one slot's memory while other chats are kept: KoboldCpp has no
  call for it (`clear_state` empties all), so with recent chats kept a slot
  let go stays allocated until a save writes over it, and lowering the
  Advanced count gives that memory back only once no chat is kept (leaving
  the open chat with none recent does it).
- The phone going back to its list of characters does not tell the app: the
  phone and the desktop share one open chat, which the desktop may still
  show. The phone's next switch, or the desktop's, lets the chat go.
- A Stop pressed on a reply sends KoboldCpp an abort at the same moment the
  next request in the line may go out. That race was there before the line
  existed (an eval's early stop, the retry hygiene call); the line does not
  widen it, and KoboldCpp ignores an abort that finds anything waiting.

### Stage 10: the batch in two, and the speed test (as built)

Decisions 27 and 28, in detail (2026-10-06).

**The two batch settings.** `kcppsBatchOf` reads the physical and logical
batch of any config: `ubatchsize` above 0 is the physical batch, never more
than `batchsize`; none, or -1, makes `batchsize` the physical batch.
`kcppsBatchKeys` writes them: with a logical batch, `batchsize` (both
spellings) holds it and `ubatchsize` the physical; without, the physical
batch is the one field. `KoboldBinaryVersion.splitsBatch` says which an
engine takes (1.122 and later; a version not known counts as older, since
the one field means the same everywhere). The typed config's `batchSize` is
always the physical batch, `logicalBatchSize` the logical one or null, and
the editor keeps a preset's two settings when only one is edited
(`ubatchsize` is in the batch group of `kcppsMergeEdits`).

**Where auto mode starts.** `koboldStartBatch` (1,024 on NVIDIA, 512
elsewhere), `koboldBatchFloor` (1,024 for a recurrent model on Vulkan), and
`koboldAutoTuning(measured:)`: the measured batch, else the start, each
only while it puts no fewer layers or experts on the card than 512, else
the floor. The Local model card's verdicts use the same function for every
context size, on the desktop and the phone.

**What the speed test tries.** `koboldBatchCandidates`: from the floor up,
each batch within the ceiling, and 2,048 only with plenty spare, which is
the whole model on the card at 2,048 with 2 GB of graphics memory still
free beside it (`kKoboldBatch2048SpareMb`, twice the 1 GB KoboldCpp's own
fit keeps); without a card, the floor alone. `koboldSpeedFactsFor` holds
the other rules: MMQ with the CUDA build only (NVIDIA or ROCm), memory lock
only with layers set by hand and not for a MoE model, flash attention only
where it can run and the chat memory is full size. Order: the physical
batch, MMQ, mmap, memory lock, flash attention. `KoboldSpeedRun` times what
runs now first, then each other value of each setting with the best so far;
a value is kept only when a turn is quicker by more than 2%
(`kKoboldSpeedBand`), since the test has one timing of each. A try that
could not load or could not be timed is never kept, and when what runs now
cannot be timed the run ends with nothing changed. With automatic layers on
an NVIDIA card that is six timings: what runs, two batches, MMQ, mmap,
flash attention.

**A try.** Chat's own config, built by the one launch function with the
try's settings (`koboldLaunchMap(trial:)`), staged as `fpai-speed.kcpps`
and put into the engine by the trial reload the editor's MMQ timing uses
(`loadKoboldTrial`), which sends nothing when that content is what runs
(the first try, usually). Then one timing prompt (`koboldTimingPrompt`,
about 2,000 tokens, a fresh start so nothing is reused) that writes 200
tokens with the end of text banned, so every try writes the same. The
measure is KoboldCpp's own speed line for it (`KoboldSpeedLines`: a line cut
across two reads counts once, whole, and the line still being written is
read as it stands, since KoboldCpp ends it only when it next prints). The
app's requests are held for the test as for the editor's timing
(`holdForSpeedTest`), and a chat message is refused with "Testing speed
settings, about N minutes left.": under the chat on the desktop, with the
typed text kept, and as the send's answer on the phone, which keeps it too.

**The estimate.** Before it starts: the number of timings times a reload
and a timing. The reload is how long the last load of this model took
(`KoboldLoadClock`: from the start of a launch, or a reload the engine
accepted, to the model answering), or a guess from the file size; the
timing comes from the last speeds the engine printed, or a slow card's.
After each try the reload-and-timing is the mean of those measured.

**The winner.** Saved by the preset library (`KcppsLibrary.write`, the door
the editor's Save uses) as "<model file> (measured on <card>)" in the
engine folder, over a file of that name, which the question before the test
names. The model file's own name, quant and all: two quants of one model
keep a preset each.
It is chat's whole config with the winning settings, without the address
and idle settings the app lays over every launch, and with a `measured`
stamp (card, backend, engine version, day, made by the auto test) that the
codec reads and writes as a setting of its own (the preset lists no
"settings this app does not manage") and KoboldCpp ignores. The model's
preset link points at it, the batch in Settings goes back to Auto, and MMQ
is remembered for the card as the editor's timing does. Then chat's config
is put back: the same content as the winning try when that ran last, so
nothing is reloaded then. When chat's model cannot be reloaded after the
save (KoboldCpp refuses it, or the reload fails outright), nothing saved is
undone and the test ends "Saved. The model could not be reloaded with the
new settings; restart it to use them." Before the save, every way it ends
says the settings were not changed.

**Auto mode runs it.** `koboldMeasuredKnobs` finds the model's measured
preset (the linked one, else the one under the test's own name) when its
stamp says the auto test made it on this card through this backend, and
`koboldLaunchMap` runs its five settings in place of auto mode's own, each
under the same rules (the ceiling, a compressed cache turning flash
attention on, memory lock only by hand). The Local model card takes the
same settings (`KoboldStatusFacts.of(measured:)`). Auto mode stays auto
mode: picking that model again in auto mode keeps auto mode
(`selectKoboldModel`), and the card keeps its context and shows no
settings. In custom mode the preset is picked like any other and runs as
written. A preset the editor timed is the user's: auto mode takes nothing
from it.

**What the user sees.** In auto mode the Local model card has "Find the
fastest settings for this computer" under the context. Tapped, it asks
first ("This takes about 4 minutes. Replies may start sooner afterwards.
Run it?", naming the preset it would replace when there is one), then a
warm dialog shows a progress bar, "Step 2 of 6", the time left in words and
what it is doing, with Cancel; it ends on one line ("Replies now come about
17% sooner." or "Your current settings were already the fastest.") and
Done, and the card keeps that line under the button for that model. When
it cannot run, the button is off with the reason under it ("Start the model
first, then run the test."). No setting is named anywhere on the card. The
phone's Models page has the same button, question, dialog and line, in the
desktop's words (decision 28).

**The editor.** "Time batch sizes", under the batch field, times the
physical batches that fit this preset on this card through the same loop
(`koboldTimeSettings`), each as a trial of the form (as Save would write
it), and puts the fastest in the form with a stamp that it was measured on
this card; the line above the button says "Batch 1,024, measured on this
card." or "Not measured on this card yet." (`koboldMeasuredWords`, from the
preset's own stamp). On an engine from 1.122 a trial is the physical batch
beside a logical 2,048, as auto mode runs it. The MMQ timing ("Time both on
this card") runs on the same loop: one timing of each, scored as a whole
turn from KoboldCpp's own speed line, where it used to take the faster of
two wall-clock timings. Both hold the app's requests and put chat's model
back as before. A hand edit of a setting a speed test measures (the batch,
flash attention, MMQ) drops the stamp (`KcppsDraft.editedFrom`, through
the controller's one `edit`): the line says "Not measured on this card
yet." and Save writes the file without it. The editor stays desktop only.

**Tests.** `kcpps_two_knob_batch_test` (the codec against two exports
KoboldCpp 1.122.1 wrote, and the launch on 1.122, 1.117 and an unknown
engine), `kobold_start_batch_test` (the start by backend, the ceiling, the
Vulkan floor, the candidates), `kobold_speed_lines_test` (a line counted
once, whole, across reads), `kobold_speed_plan_test` (the order and skip
rules as a table, the greedy walk, the band, the words),
`kobold_speed_test_run_test` (the real service, provider, staging and
reloads on a loopback KoboldCpp that prints the speed of what it really
loaded: six timings, the winner saved and read back through the codec, the
link, auto mode kept, the next launch running it, Cancel putting the model
back, a message refused meanwhile through `ChatService`, "A speed test is
already running." while the editor's timing holds the engine and a try
loads, two quants of one model measured in turn keeping a preset and a
working link each, and "Saved. … restart it to use them." when chat's
reload after the save is refused or throws, with nothing saved undone),
`kobold_measured_preset_test` (which preset auto mode runs, and the model
pick), `speed_test_relay_test` (the phone through the real web server:
ask, start, the hub's progress, the card's line, Cancel, a refused send),
`local_model_measured_test` and `kobold_status_card_speed_test_test` (the
phone's and the desktop's verdicts with measured settings: flash attention
off makes 65,536 tokens too big for Llama 3.1 8B on a 16 GB card),
`kobold_speed_test_overlay_test` (the dialog tapped through) and
`kcpps_editor_batch_timing_test` (the editor's button, its trials and the
saved file, and a hand edit of the batch, flash attention or MMQ dropping
the stamp). Each rule was broken once to see its test fail.

**Not done.**

- The live suites need a real engine and a real card; the speed test has
  not been run on one for this stage (decision 28's numbers above are from
  the stand-in). Run it once on an NVIDIA card and on the AMD card.
- mmap and memory lock change little the estimate can see: the card's
  verdicts take the measured flash attention and batch, not mmap.
- The Advanced tab's switches show the global settings, not what was
  measured for the model in use.
- The old reply-by-reply MMQ learner still runs in auto mode until a
  measurement exists for the card; the speed test's answer ends it.

**Existing tests changed** (the behaviour they pinned, "the largest batch
that fits", is the thing replaced): `kobold_auto_tuning_test` (Vulkan now
starts at 512), `kobold_auto_launch_test`, `kobold_auto_keeper_test`,
`kobold_awaited_hardware_test` and `kobold_stage_header_cache_test` (an
NVIDIA card's tuned batch is 1,024, still told apart from the untuned 512),
and `test/live/kobold_presets_live_test.dart` (Apple Silicon's physical
batch is 512, beside a logical 2,048 on 1.122). Changed because the
editor's MMQ timing now reads KoboldCpp's own speed line:
`kcpps_editor_mmq_line_test` and `kobold_speed_test_hold_test`, whose
engine stand-in now prints that line after each timing prompt, as KoboldCpp
does; what they pin (the hold, the order, "faster here", two trial loads)
is unchanged.

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
