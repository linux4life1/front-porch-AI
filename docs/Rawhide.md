# Rawhide — What's New (Nightlies)

These notes are the in-app "Update Available" text for Rawhide builds. The
nightly takes every bullet under **Unreleased** as that build's release
body, and `tools/rotate-rawhide-notes.sh <tag>` then removes the bullets it
shipped, so a note is read here once and lives on in the GitHub release.
Write one bullet per change, on one line, with a bold title. Nothing else
goes in this file; `test/hygiene/rawhide_notes_test.dart` checks that.

Last shipped nightly: `nightly-rawhide.20261101.6274933`

## Unreleased

- 🌅 **The sky follows the story clock** — With Ambient scene on, the stage behind the chat now blends the time-of-day wash by the minute instead of snapping at each part of day, and adds a sun by day, a moon with its phase and stars by night, and a warm band at dawn and dusk. Thick weather dims the sun and moon into a wider glow and thins the stars, but never hides them. With Tint and effects on, the stars twinkle and a jump in the story clock (a sleep, days passing) plays a short time-lapse; Tint only keeps the sky still, and so does Reduce motion. The sky moves only when the story clock does, never on its own. On the desktop and the web app.
- 🎭 **Mood on the character** — A new Appearance setting paints each character's Realism state on what they own: the sidebar portrait gets a ring in their mood's colour that burns, breathes, jitters, bounces, beats or crackles with the mood and bursts when it changes, a halo for the bond and a weight for the trust, and a breathing rim when a need is in trouble; a needs bar in trouble throbs in its own colour with a badge, twice as fast when critical, and a character who enjoys low hygiene gets that bar the other way round; at the full level the latest reply wears its mood too. Off by default, with a Drama slider, under Chat Appearance, shown only while Porch Life's Realism Engine is on. It never touches the weather behind the chat. Reduce motion holds it still. The Appearance tab's weather controls now sit under their own Background weather heading, shown only while Story Weather is on. On the desktop and the web app.
- 🎡 **Chance Time, with weight** — The Chance Time wheel now runs on the Ambient Stage's engine. The pointer clicks on every peg and trembles on the last one, carnival bulbs and sparks run with the wheel's speed, the wheel shakes, pops and flashes when it lands and throws out the slot's emoji, and the reveal plays in the result's own key: confetti for Fortune, a red dim and falling ash for Misfortune, lightning for Chaos, a purple shimmer for Wild Card. The event is still decided before the wheel moves. Reduce motion jumps straight to the card. The phone's Chance Time gets the same wheel where it had a flat card. On the desktop and the web app.
