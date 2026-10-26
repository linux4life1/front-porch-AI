# The Ambient Stage

Design doc for the living chat background: weather you can see and hear,
character mood you can see on the speaker, and the stage those later grow
into (animated avatars, a visual-novel layout, layered parallax scenes).
Weather is the first tenant. Everything here is presentation: nothing in
this doc makes a model call or changes generation, scoring, Needs, the story
clock, or what is saved.

Status: roadmap. Sections marked **Now** are the first PR; **Next** follow;
**Horizon** are stated destinations that the first PR must leave room for.

## 1. Long view

The maintainer's stated destinations, in the order they are wanted:

1. **Weather on the canvas** (Now). Rain, snow, clouds, fog and a
   time-of-day tint over the chat background, driven by the chat's own
   Living Worlds weather and story clock.
2. **Weather sound** (Next). Loops per condition and thunder on storms.
3. **Mood on the speaker** (Next). A glow on the speaking character's
   bubble and portrait coloured by their current feeling.
4. **Animated avatars** (Horizon). GIF and animated WebP portraits that
   play everywhere a portrait shows.
5. **Visual-novel layout** (Horizon). Background fills the window,
   characters stand on it as large expression sprites, the current line
   sits in a text box along the bottom.
6. **Parallax scenes** (Horizon). Backgrounds built as depth layers that
   shift at different rates, with weather living between the layers.

Items 5 and 6 are why the first PR builds a *stage* rather than a weather
painter: the surface weather paints on is the one sprites later stand on.

## 2. Decision: Flame is the stage

The stage is a Flame `GameWidget` mounted where the chat background image
is painted today (`lib/ui/pages/chat_page_overlays.dart`). Flame draws on
Flutter's own canvas, so it runs on the Skia renderer this app pins on
every desktop OS (see the Impeller notes in `macos/Runner/Info.plist` and
`windows/runner/main.cpp`) and needs no platform code. It is pure Dart,
MIT licensed, and fits the Flutter and Dart floors in `pubspec.yaml` and
`.github/workflows/ci.yml`. It is in-process, so the Engines rule holds.

Why Flame over a hand-rolled `CustomPainter`: particles, a parallax
component, sprites with animation, a camera and tween effects are finished
parts, and items 4 to 6 need all of them. The cost of Flame today is one
dependency and a second mental model (a component tree with an update
loop beside the widget tree). The cost of a painter is rebuilding it when
sprites and parallax arrive.

Conditions that make Flame worth it:

- **Simulation is plain Dart.** Particle positions, tint values and effect
  budgets live in a Flame-free class with an injectable seeded random
  source, unit tested without the engine. Flame only renders it. The web
  twin reproduces the same numbers from the same inputs.
- **Colours are tokens.** Every colour the stage paints is handed in from
  `AppPalette` / the active theme or from the weather token map below.
  No literal colours in stage code; the raw-colour ratchets stay green.
- **The stage costs nothing when nothing moves.** It is not mounted when
  Ambient scene is Off. A static stage (Tint only, or the weather while
  the OS asks for reduced motion) never runs the engine loop; it paints
  once when it loads and once per change of scene.
- **Pause rules come with the effects (PR 2).** Once something moves,
  the stage ticks only while the app is visible and the window has focus,
  and (optionally, the Pause effects while generating switch, on by
  default) not while a reply is generating, because KoboldCpp shares the
  GPU. When the OS asks for reduced motion the stage is static again: the
  weather is drawn, held still where it is, and repainted only when the
  scene changes. A static tint has nothing to pause, so these rules apply
  only to a moving stage.
- **All text is widgets.** Names, dialogue, controls and the composer stay
  Flutter widgets layered above the stage. The stage is only the picture.

Pubspec rule: the `flame` line carries its reason and licence in the
comment, as the other reasoned dependencies do.

## 3. Stage architecture

```
chat page (ChatSurface)
└─ Stack
   ├─ chat background image         the page's own layer, unchanged
   ├─ AmbientStage → AmbientStageGame (GameWidget, transparent)
   │   ├─ SceneTintComponent        priority 0: daypart + condition + temperature washes, haze
   │   ├─ SceneCloudLayer           priority 1: drifting cloud puffs
   │   ├─ SceneFogLayer             priority 2: drifting fog blobs
   │   ├─ ScenePrecipitation        priority 3: rain or snow
   │   ├─ SceneLightningFlash       priority 4: the storm flash
   │   └─ (later) sprite stage      expression sprites for the VN layout
   └─ existing chat column          bubbles, composer, overlays, unchanged
```

The web paints the same stack: the tint as the chat view's CSS layers,
then one canvas (`SceneEffectsCanvas`) drawing clouds, fog, rain or snow
and the flash in that order. Both surfaces composite the same colours in
the same order, so one readability test covers both.

- `lib/ui/chat_components/ambient/` holds the stage and its components,
  each a small class (size law applies).
- `lib/services/chat/scene/` (plain Dart) owns the mapping from weather
  and clock to **scene tokens** (`SceneSim`), the gate that decides
  whether there is a scene at all and how much of it (`SceneGate`, which
  also holds High Contrast to Tint only), and the moving weather's
  budgets and seeded sim (`SceneEffectSpec`, `SceneEffectsSim`). It is
  the single source of truth for the numbers; this doc
  does not pin them. The colours live in `lib/ui/theme/scene_palette.dart`.
  A unit test pins each (daypart, condition, temperature) cell.
- `WebThemeTokens` gains a sibling, `SceneTokens.wireOf(...)`, so the web
  paints the same scene from the chat state the way it paints the theme
  today and never works a colour out itself. Like the theme wire it
  carries both brightnesses, because the web may run its own mode.
- The stage reads `chat.currentSegmentWeather` (the segment carries its
  day), the story clock's daypart and day count from `chat.timeService`
  (the six dayparts `time_strip.dart` already names) and the chat's
  session id for the seed, through the existing accessors
  (`scene_resolver.dart`). It does not read the forecast or the biome;
  the segment's condition and temperature band already carry the
  biome's weather. It adds no new state and no new model call.
- Custom backgrounds load from the app's storage paths, never Flame's
  asset bundle. No sync I/O in the widget tree (`io-lint`).

### Scene tokens

The wire carries, for the current chat: `daypart`, `condition`, `temp`,
and per brightness (`dark`, `light`) the washes as CSS colours in paint
order (shade, daypart, condition, temperature cast) plus the haze
strength and its centre and edge colours. PR 2 adds, at the top level
because they do not depend on the mode, `level` (tint or effects),
`seed`, `pauseWhileGenerating` and `effects` (kind, density, clouds, fog,
lightning, wind), and in each brightness's map the weather's `paints`
(rain, snow, cloud, fog and its clear stop, flash). Every field is
additive.
The interactive prototype that accompanies this doc shows every cell and
the JSON the desktop would send; the Dart sim and its test are the source
once they exist.

### Readability guard

The tint and the effects sit behind the bubbles, never over them, so
bubble contrast is unchanged by construction. What must survive is the
background's own text (timestamps, system notices drawn on the canvas),
held to the floor the theme already promises:
`AppearanceSettings.accentMinRatio` (4.5:1, and 7:1 for High Contrast),
measured with `contrastRatio` from `lib/ui/theme/accent_fit.dart`.

- **Tint:** every (daypart, condition, temperature) cell over every
  theme's background in both modes (`scene_sim_test`).
- **Effects:** the same cells with the thickest cloud (0.75 of its paint)
  or the thickest fog blob centre (0.5 of its paint) composited over the
  tinted ground (no condition draws both), in the stack order both
  surfaces share (tint, clouds, fog, then rain or snow and the flash on
  top), every theme in both modes except High Contrast, which the gate
  holds to Tint only so no effect is ever drawn on it
  (`scene_effects_test`). Rain, snow and the flash are thin or momentary
  and are not part of the floor.
- **Next:** if dark-mode fog reads too faint under the 4.5:1 floor, the
  lever is a scrim pill behind the canvas-drawn text (timestamps, system
  notices); with that in place the effects need no text floor and the
  fog paint can go back up.

### Settings and gates

| Setting | Values | Default | Where |
|---------|--------|---------|-------|
| Ambient scene | Off · Tint only · Tint and effects | Off | Appearance (desktop and web) |
| Pause effects while generating | on/off | on | Appearance (desktop and web, PR 2) |
| Scene sound | on/off + volume | off | Appearance (Next) |
| Mood glow | on/off | off | Appearance (Next) |

Reduce motion is not a setting here: the stage follows the OS (PR 2), and
an in-app override is Next.

PR 1 ships Ambient scene with Off and Tint only. PR 2 ships Tint and
effects, the Pause effects while generating switch and reduce motion
(followed from the OS, on the desktop through Flutter's disable
animations and on the web through `prefers-reduced-motion`), since a
static tint has nothing to pause or reduce. Every row is a
`settings_parity_manifest` entry when it ships. High Contrast holds
Ambient scene to Tint only at most: `SceneGate` applies the cap, so the
desktop stage and the web wire cannot disagree. Weather paints nothing
when the chat has no world with climate on, and nothing when the clock
is off.

### Performance budget

A few hundred particles drawn as one batch per frame is trivial for any
GPU. The real risks are GPU contention with a local model on integrated
graphics and laptop battery. Mitigations: default off, a static stage
that never runs the engine loop, the pause rules above (PR 2), a
particle budget that scales with stage area and caps low, and the
generating pause. Flame cannot run at half frame rate, so the knobs
are particle count and pausing. The poke script for the PR measures token
speed on an integrated-GPU machine with the stage on and off.

## 4. Tenant 1: Weather (Now)

Inputs, all existing:

- `SegmentWeather.condition` (`clear cloudy overcast fog rain storm snow`),
  `WeatherEngine`'s `TempBand` (classic cold to hot plus the biome-only
  extremes), `DailyWeather.season`, and the condition skin's stance and
  label. See `lib/services/chat/weather_engine.dart`,
  `weather_segments.dart`, `weather_biomes/condition_skin.dart`.
- The story clock's daypart (dawn, morning, late morning, afternoon,
  evening, night) from the same source `time_strip.dart` reads.

Mapping, owned by `SceneSim` (`scene_tokens.dart`) for the washes and
`SceneEffectSpec` (`scene_effects.dart`) for what moves:

- **Daypart sets the base wash.** Dawn warm pink, morning pale gold, late
  morning neutral, afternoon faintly warm, evening amber, night deep blue
  at the highest alpha of the set.
- **Condition modifies it.** Cloudy and overcast grey and desaturate;
  fog lightens and adds haze; rain cools and darkens; storm darkens most
  and enables lightning; snow cools and brightens.
- **Temperature adds a cast.** Cold bands tilt blue, hot bands tilt
  orange, the biome-only extremes further. Mild adds nothing.
- **Effects per condition.** Rain: angled streaks, heavier for storm.
  Snow: slow swaying flakes. Cloudy and overcast: drifting cloud shapes
  along the top, more and lower for overcast. Fog: haze layer with slow
  drift, thicker at the edges. Storm: rain plus an occasional brief flash
  with a randomised gap before the thunder (sound is Next). Clear: tint
  only.
- **Authored tints.** `ConditionSkin` gains an optional `tint` so a custom
  biome can colour its own weather (green acid rain). Absent means the
  built-in mapping. Parsing stays defensive for older skins.

Determinism: the sim seeds from the chat's session seed and the story
day the weather engine uses, plus the daypart and condition
(`sceneSeed`), so regen, swipe and reload draw the same sky and a new
part of day or a change of weather draws a new one. That is per-surface
reproducibility: the same seed on the same surface at the same integer
stage size draws the same scene. The scatter scales by the stage size,
so the desktop and the web draw the same scene only at identical integer
sizes; the shared vectors pin the sims at fixed sizes.

### Backgrounds and the weather overlay

Decision (maintainer, this doc's first review): **the stage paints the
story's weather over whatever background is chosen, and the user owns
any mismatch.** A golden-hour café can have rain falling on it. The wow
of real weather in the window is the feature; a matching-picture system
(tags, an Auto background that follows the story, per-image switches) is
out of scope so the SOW does not spiral.

- Background resolution stays exactly what `chat_page_overlays.dart`
  does now: chat theme preset or its per-chat override, else the global
  Chat Background (built-in or custom). The stage takes the resolved
  image as its backdrop layer and adds nothing to the picker.
- The one guard is the existing Ambient scene setting: a user who does
  not want rain on a bedroom picture sets Tint only or Off. The
  expression-background mode is treated like any other image.
- The sidebar weather chip remains the authority on what the story's
  weather is; the overlay illustrates it, the picture does not.

Someday, not a dependency: tagged scenes with an Auto mode that follows
the story, and a Living Worlds place owning its own scene set, possibly
generated by Image Studio from the place's description and climate.

## 5. Tenant 2: Scene sound (Next)

Reuses the players that Porch Stories already uses for its ambient loop
and page-turn sound (`lib/ui/pages/story_reader_page.dart`) and the web
reader's `<audio>` element served from the app's own audio folder
(`web_ui/src/pages/story/useAmbient.tsx`), including its "could not
play" fallback for browsers that refuse autoplay.

- Loops per condition: rain, heavier rain for storm, wind for snow, birds
  for clear day, crickets for clear night, near silence for fog. Short
  seamless loops, compressed small, under `assets/audio/`.
- One-shot thunder timed to the lightning flash, with the flash-to-rumble
  gap randomised.
- Ducking: ambience drops while TTS speaks and returns after.
- Off by default; a Scene sound switch and volume slider with web twins.
- Every bundled file has a recorded licence (CC0 or equivalent) and
  attribution in the repo. No sounds fetched from the network.

## 6. Tenant 3: Mood glow (Next)

Inputs, all existing: the judge's emotion label, intensity, cause and
held count on each message (`lib/services/chat/mood_physics.dart`, the
`kMoodStamp*` keys), collapsed to the six `MoodTone`s (sour, low,
anxious, lifted, warm, charged); the web already receives `emotion`,
`emotionIntensity` and `mood`.

- A soft edge glow or left rule on the **speaker's** bubble and a ring on
  their sidebar portrait, coloured by tone through a `RealismColors`-style
  resolver (hue fixed, lightness per brightness) so it holds on every
  theme. Alpha scales with intensity and eases as `held` grows.
- A short pulse when `MoodChange.moved`, reusing the sidebar emoji-burst
  pattern.
- The standing mood may tint the greeting bubble only.
- **Layering rule:** weather owns the canvas, emotion owns the speaker.
  Never a whole-canvas mood tint; it is wrong in groups and fights the sky.
- Groups: each speaker carries their own, keyed by the message's speaker
  id, never whoever is active after post-gen (Group restore contract).
- Path-complete: regen, swipe, Continue and edit re-derive from the
  message's stored stamp; 1:1 and group match; desktop and web ship
  together. See `docs/design/path-complete-chat-work.md`.

## 7. Horizon

### Animated avatars

Flutter's `Image` and the browser's `<img>` both play animated GIF and
WebP natively; the display side is nearly free. The work is the import
pipeline: `expression_pack_*` and the avatar gallery normalise, crop,
check and re-encode, and each step would flatten an animation to its
first frame. Needed: detect animated files on import and pass them
through untouched, skip or per-frame crop, still-frame thumbnails in the
gallery, a file-size cap, and a freeze-to-one-frame path under reduce
motion. Once the file survives import, the sidebar portrait, bubble
header, group roster and web all play it.

### Visual-novel layout

A per-chat layout switch beside the chat theme presets. The stage fills
the view; the speaker's emotion image stands centre, large, with group
members side by side (speaker lit, others dimmed); the latest message
sits in a text box along the bottom with the speaker name and the
dialogue and action colours; the composer sits under it; swipe, regen and
Continue are buttons on the box; a pull-up log holds the transcript. The
mood glow moves to the sprite edge. Works at 400 px (sprite shrinks, box
grows) and 1440 px, and gets a `layout_sweep_test` stop. On the web it is
a second chat page layout on the same socket. Every message action keeps
a home in the new layout.

### Parallax scenes

Backgrounds as layers (sky, far, mid, near) that shift at different rates
with scroll, pointer drift or a slow automatic sway; weather lives between
the layers (rain in front of the hills, behind the window frame). Flame's
parallax component does the shifting. The cost is content: today's
built-in backgrounds are single images and would need remaking as layers;
a user's flat custom background stays flat unless an automatic depth
split is built, which is its own project.

## 8. PR plan

Weather is three PRs. Each is a draft to Rawhide, ships desktop and web
together, adds its own `docs/Rawhide.md` bullet, and carries a poke
script for what a sandbox cannot certify.

1. **Stage and tint.** Flame dependency (reason and licence in the
   pubspec comment); the stage mounted at the backdrop spot; the
   plain-Dart scene sim (daypart, condition, temperature in; scene tokens
   out); the daypart wash, condition wash and temperature cast; the
   Ambient scene setting with Off and Tint only; a static stage that
   paints on change and never runs the engine loop; the scene token wire
   in both brightnesses; the web tint layer. Tests: one per mapping cell,
   the readability guard per theme, the gate, the stage's paint and focus
   behaviour, appearance settings, parity rows, a web painter unit test.
   No golden was recorded in PR 1: the sandbox it was written in cannot
   run the Linux golden image. PR 2 owes the tint golden beside the seeded
   first frame; a maintainer with the image can record it any time with
   `./scripts/ci-local.sh update-goldens`.
2. **Effects.** Rain, snow, clouds, fog and the storm flash as stage
   components; particle budget scaled to stage size and capped; the web
   canvas twin from the same seeded model; the Tint and effects setting
   value, with High Contrast held to Tint only; the pause rules (window
   focus and visibility, reduced motion) and the Pause effects while
   generating switch, with web twins. Tests: budget and seed determinism
   against vectors shared by the Dart and web sims, the High Contrast
   cap in the gate, the wire, the stage's effects, freeze and generating
   pause, and the web player and controls. Still owed: a golden of the
   seeded first frame (the authoring sandbox cannot run the Linux golden
   image) and a Playwright sweep stop. Poke: token speed with effects on and off on an
   integrated-GPU machine.
3. **Scene sound.** Loops per condition and the thunder one-shot on the
   players Porch Stories uses; ducking under TTS; Scene sound switch and
   volume with web twins; licence record for every bundled file. Tests:
   thunder scheduler and ducking in plain Dart, web audio wiring, parity
   rows. Poke: ears.

Then, as separate work: mood glow (one PR, path-complete), animated
avatar pass-through (one), the visual-novel layout (two: the layout on
both sides, then sprite stage polish), parallax (two or more, only if
people live in the visual-novel layout).

Maintainer inputs before PR 1: sign-off on the Flame dependency, the
source of the sound files (CC0 or equivalent, approved before fetching),
and an integrated-GPU machine for the PR 2 poke.
