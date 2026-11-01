# Rawhide — What's New (Nightlies)

These notes are the in-app "Update Available" text for Rawhide builds. The
nightly takes every bullet under **Unreleased** as that build's release
body, and `tools/rotate-rawhide-notes.sh <tag>` then removes the bullets it
shipped, so a note is read here once and lives on in the GitHub release.
Write one bullet per change, on one line, with a bold title. Nothing else
goes in this file; `test/hygiene/rawhide_notes_test.dart` checks that.

Last shipped nightly: `nightly-rawhide.20261101.6274933`

## Unreleased

- 🎭 **Mood on the character** — A new Appearance setting paints each character's Realism state on what they own: the sidebar portrait gets a ring in their mood's colour that burns, breathes, jitters, bounces, beats or crackles with the mood and bursts when it changes, a halo for the bond and a weight for the trust, and a breathing rim when a need is in trouble; a needs bar in trouble throbs in its own colour with a badge, twice as fast when critical, and a character who enjoys low hygiene gets that bar the other way round; at the full level the latest reply wears its mood too. Off by default, with a Drama slider, under Chat Appearance, shown only while Porch Life's Realism Engine is on. It never touches the weather behind the chat. Reduce motion holds it still. The Appearance tab's weather controls now sit under their own Background weather heading, shown only while Story Weather is on. On the desktop and the web app.
