# Scene sounds: provenance and licence

The files in this folder are the Ambient Stage's scene sound
(`docs/design/ambient-stage.md` §5): six loops and three thunder one-shots.

| File | What it is |
|------|------------|
| `rain.mp3` | 9 s loop: filtered pink noise with a scatter of droplet tones |
| `storm_rain.mp3` | 9 s loop: heavier, lower rain with a low rumble and gusts |
| `wind.mp3` | 12 s loop: band-passed noise with a slow swell (played for snow) |
| `birds.mp3` | 10 s loop: sparse swept-sine chirps (clear daytime) |
| `crickets.mp3` | 8 s loop: regular high chirps from two crickets (clear evening and night) |
| `fog.mp3` | 12 s loop: a very low, quiet drone |
| `thunder_1.mp3`, `thunder_2.mp3`, `thunder_3.mp3` | 3.4, 4.1 and 4.8 s one-shots: brown-noise bursts under a closing lowpass |

## Provenance

Every file was synthesised by `tools/gen_scene_sounds.py` in this
repository, from seeded random noise and sine waves, with numpy, and encoded
to MP3 by ffmpeg's libmp3lame (mono, 22.05 kHz, 40 kbps). No recording,
sample, preset or other third-party material was used, and nothing was
downloaded. Running the script again with the same seed and ffmpeg
reproduces them:

    python3 tools/gen_scene_sounds.py

## Licence

The Front Porch AI project dedicates these sound files to the public domain
under the Creative Commons CC0 1.0 Universal dedication
(<https://creativecommons.org/publicdomain/zero/1.0/>). You may copy,
modify, distribute and use them, even commercially, without asking
permission and without attribution.

The generator script itself is part of Front Porch AI and is licensed
under the AGPL-3.0-or-later, like the rest of the source.
