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

Conditions that make Flame worth it, all in the first PR:

- **Simulation is plain Dart.** Particle positions, tint values and effect
  budgets live in a Flame-free class with an injectable seeded random
  source, unit tested without the engine. Flame only renders it. The web
  twin reproduces the same numbers from the same inputs.
- **Colours are tokens.** Every colour the stage paints is handed in from
  `AppPalette` / the active theme or from the weather token map below.
  No literal colours in stage code; the raw-colour ratchets stay green.
- **Pause rules exist from day one.** The stage stops ticking when the
  Ambient scene setting is off, when the window is unfocused or minimised,
  when the OS asks for reduced motion, and (optionally, a user switch)
  while a reply is generating, because KoboldCpp shares the GPU.
- **All text is widgets.** Names, dialogue, controls and the composer stay
  Flutter widgets layered above the stage. The stage is only the picture.

Pubspec rule: the `flame` line carries its reason and licence in the
comment, as the other reasoned dependencies do.

## 3. Stage architecture

```
chat page
└─ Stack
   ├─ Stage (GameWidget)            ← background image + weather + later sprites
   │   ├─ BackdropComponent         the still or layered background
   │   ├─ SkyTintComponent          daypart + condition + temperature wash
   │   ├─ CloudLayer / FogLayer     drifting shapes, haze
   │   ├─ PrecipitationComponent    rain or snow particles, lightning flash
   │   └─ (later) SpriteStage       expression sprites for the VN layout
   └─ existing chat column          bubbles, composer, overlays, unchanged
```

- `lib/ui/chat_components/stage/` holds the components, each a small
  class (size law applies).
- `lib/services/chat/scene/scene_sim.dart` (plain Dart) owns the mapping
  from weather and clock to **scene tokens** and the particle budgets. It
  is the single source of truth for the numbers; this doc does not pin
  them. A unit test pins each (daypart, condition, temperature) cell.
- `WebThemeTokens` gains a sibling, `SceneTokens.wire(...)`, so the web
  paints the same scene from `settings_changed` / chat state the way it
  paints the theme today and never works a colour out itself.
- The stage reads `chat.currentSegmentWeather`, `chat.upcomingWeather`,
  `chat.activeChatBiome` and the story clock's daypart (the six dayparts
  `time_strip.dart` already names) through the existing accessors. It
  adds no new state and no new model call.
- Custom backgrounds load from the app's storage paths, never Flame's
  asset bundle. No sync I/O in the widget tree (`io-lint`).

### Scene tokens

The wire carries, for the current chat: `daypart`, `condition`, `temp`,
`tint` (colour and alpha), `cast` (temperature colour and alpha), `fog`
(0 to 1), `effects` (kind and density), and `flash` (a lightning pulse).
The interactive prototype that accompanies this doc shows every cell and
the JSON the desktop would send; the Dart sim and its test are the source
once they exist.

### Readability guard

The tint sits behind the bubbles, never over them, so bubble contrast is
unchanged by construction. A test asserts the tint alpha ceiling keeps the
background's own text (timestamps, system notices drawn on the canvas)
above the contrast floor the theme already promises, using `contrastRatio`
from `lib/ui/theme/accent_fit.dart`.

### Settings and gates

| Setting | Values | Default | Where |
|---------|--------|---------|-------|
| Ambient scene | Off · Tint only · Tint and effects | Off | Appearance (desktop and web) |
| Pause effects while generating | on/off | on | Appearance |
| Scene sound | on/off + volume | off | Appearance (Next) |
| Mood glow | on/off | off | Appearance (Next) |
| Reduce motion | follows OS, with an override | OS | Appearance |

Every row is a `settings_parity_manifest` entry. High Contrast forces
Ambient scene to Tint only at most. Weather paints nothing when the chat
has no world with climate on, and nothing when the clock is off.

### Performance budget

A few hundred particles drawn as one batch per frame is trivial for any
GPU. The real risks are GPU contention with a local model on integrated
graphics and laptop battery. Mitigations: default off, the pause rules
above, a particle budget that scales with stage area and caps low, and
the generating pause. Flame cannot run at half frame rate, so the knobs
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

Mapping, owned by `scene_sim.dart`:

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

Determinism: the sim seeds from the same session seed, day and hour the
weather engine uses, so regen, swipe and reload draw the same sky.

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

## 8. Order

1. **Stage + weather tint + rain, snow, clouds, fog**, desktop and web,
   with the settings, gates, pause rules, sim test, golden and sweep stop.
2. **Scene sound** on the existing players.
3. **Mood glow** on bubble and portrait, path-complete.
4. **Animated avatar pass-through** in the import pipeline.
5. **Visual-novel layout.**
6. **Parallax**, if people are living in the visual-novel layout.

A remote sandbox cannot certify how any of this looks or sounds; each PR
carries a poke script for the maintainer.
