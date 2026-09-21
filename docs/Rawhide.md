# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.
**Only list what landed after the last shipped nightly.** Clear this section when a new nightly goes out — delete the old bullets; do not accumulate them.

Last shipped nightly: `rawhide.20260920.5fe816e`. Everything below is unreleased.

## Recent improvements (unreleased — ships in the next build)

- 📜 **Opening a chat lands you on the latest messages** — no more marathon scroll from the first greeting. Older history loads backward as you scroll up. Fast-scrubbing the transcript should stay smooth (theme on or off). **Follow streaming replies** (Settings → General, on by default) keeps the chat pinned to the newest words while a reply is writing if you are already at the bottom — scroll up to stop, return to the bottom to follow again. Turn it off if you want the chat to stay put. Same on the phone.
- 💫 **Afterglow no longer keeps them limp the whole cooldown** — the first reply after a scene can still feel wrecked and heavy. After that, how tired or comfortable they are follows energy and comfort (Needs), not a stuck exhausted pose. Same in a group.
- 🖼️ **Comfy Create rides Comfy’s own templates** — Z-Image Turbo, Qwen-Image, and Flux/Krea use the graphs Comfy ships (or a replaceable starter / your uploaded workflow), not a Porch-owned copy we have to rewrite every model bump. Pick the family, fill the model drawers, Generate. Expression packs still Edit first; plain models fall back to img2img. Same on the phone.
- 🖼️ **Nano-GPT Image Studio lists current image models** — Qwen Image 2.1/3, GPT Image 2.5, FLUX.2, Ideogram V4, Midjourney, and the rest of today’s Nano image page (subscription ones still marked included). Same on the phone.

- 👥 **Guests can sit in a group without becoming full members** — `/create`, `/join --lite`, and `/scan` work in a group now. They take turns and can be Away like anyone else (a guest who walks off is marked Away; Needs and Realism still stay off). Promote them with `/promote Name` or the roster button. Turning a 1:1 into a group keeps the guests as guests. Same on the phone.

- 📦 **Guests survive a Full Front Porch chat share** — exporting a `.fpchat` now remembers who was a Scene Guest (1:1) or a soft group member. Importing onto the same open cast puts them back as guests. Old files still open. Same on the phone.
