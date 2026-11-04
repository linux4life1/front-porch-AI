# Scene sounds: provenance and licence

The files in this folder are the Ambient Stage's scene sound
(`docs/design/ambient-stage.md` §5): six weather/time-of-day loops, four
per-place loops and three thunder one-shots.

## What's here now (real recordings)

The shipped files are field recordings downloaded from Pixabay on
2026-11-03, cut to a calm window, loop-crossfaded (3 s equal-power
fold), loudness-normalised (loops −26 LUFS, thunder −17 LUFS) and
encoded mono 44.1 kHz MP3 (loops 56 kbps / 45 s, thunder 96 kbps /
≤4.8 s) by `dl/ambient-src/process.py`. The originals live beside that
script in `dl/ambient-src/`.

| File | Source (Pixabay, artist, title, id) |
|------|--------------------------------------|
| `rain.mp3` | DRAGON-STUDIO — Calming Rain Loop (398653) |
| `storm_rain.mp3` | drericoy (via freesound_community) — Rain and thunder (16705) |
| `wind.mp3` | haniebal (via freesound_community) — Wind ambience (14720) |
| `birds.mp3` | IndigoBunting — Autumn Morning Woodland with Birdsong and Distant Waterfall (173326) |
| `crickets.mp3` | Abinash87 (via freesound_community) — Night cricket ambience (22484) |
| `fog.mp3` | freesound_community — Fog in the trees with wind (59749) |
| `forest.mp3` | AudioPapkin — Forest ambience (296528) |
| `shore.mp3` | Prem_Adhikary — Relaxing Ocean Waves, high quality recorded (177004) |
| `cave.mp3` | iampagan (via freesound_community) — Droplets in a cave (6785) |
| `village.mp3` | DanEvaer — Small Town Street Ambience: Cars, Dogs, Birds, and Distant Voices (436102) |
| `thunder_1.mp3` | TRP (via freesound_community) — Thunder big crack explosive close, ms 77mel 190903 (62202) |
| `thunder_2.mp3` | TRP (via freesound_community) — 200817 Thunder, pretty close crack 4pm (62574) |
| `thunder_3.mp3` | TRP (via freesound_community) — Thunder, dry distant rolling, field, NOTL, 2011 (48804) |

Track pages: `https://pixabay.com/sound-effects/<slug>-<id>/` — the exact
URLs are recorded in `dl/ambient-src/TODO.md`.

## Licence

These recordings are used under the **Pixabay Content License**
(<https://pixabay.com/service/license-summary/>): free for commercial
and non-commercial use, no attribution required, and no permission
needed. Two clauses matter for a repo like this one:

- Content may not be made available for download **as stock from a
  competing (or the same kind of) service** in essentially unmodified
  form. Bundling into the Front Porch AI app is a permitted "incorporation
  into a new production"; someone who clones this repo should not
  re-publish these MP3s as a standalone sound-effect library.
- Trademarks and rights of any identifiable people or brands in the
  recordings are not granted by the licence (nothing in these clips is
  expected to raise that; the village track has distant traffic and
  voices, no identifiable speech or brand).

The earlier set — every file synthesised by `tools/gen_scene_sounds.py`
from seeded noise, CC0 — has been **superseded** by the recordings above
but remains available: running that script regenerates the CC0 set
(byte-for-byte, same seed) into any output directory, and those
regenerated files stay CC0 like the script itself
(AGPL-3.0-or-later for the script, CC0 for its output).

    python3 tools/gen_scene_sounds.py --out /tmp/cc0-scene-sounds
