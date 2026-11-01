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
