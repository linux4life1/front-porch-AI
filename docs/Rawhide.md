# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.
**Only list what landed after the last shipped nightly.** Clear this section when a new nightly goes out — delete the old bullets; do not accumulate them.

Last shipped nightly: `rawhide.20260921.f50f22e`. Everything below is unreleased.

## Recent improvements (unreleased — ships in the next build)

- ⏱️ **A normal send always moves the story clock** — at least a minute or two, and a ⏱ chip names it. Same moment only when the scene is one continuous instant. Passage of Time is the only driver (Realism off still ticks). Continue does not tick. Needs bars stay put unless the scene itself moves them; a short no-action turn says “No needs affected.” Same on the phone.

- 🛠️ **Waifu Coder can use the same recipe cards as chat** — drop JSON in the library `tools` folder, opt in from the Waifu harness, and they show up as tools. Skills are a separate Waifu-only drawer (`skills/<name>/SKILL.md`). Not Docker, not extra MCP servers. Same on Porch Life.

- 🖼️ **Comfy Create rides Comfy’s own templates** — Z-Image Turbo, Qwen-Image, and Flux/Krea use the graphs Comfy ships (or a replaceable starter / your uploaded workflow), not a Porch-owned copy we have to rewrite every model bump. Pick the family, fill the model drawers, Generate. Expression packs still Edit first; plain models fall back to img2img. Same on the phone.
- 🖼️ **Nano-GPT Image Studio lists current image models** — Qwen Image 2.1/3, GPT Image 2.5, FLUX.2, Ideogram V4, Midjourney, and the rest of today’s Nano image page (subscription ones still marked included). Same on the phone.
- 🖼️ **Image Studio Remote API: Nano or OpenRouter** — pick the host with chips (each uses the key you already saved in Settings → Backend). Search the model list; Nano rows say Pro vs paid. Switching Studio chips does not change chat’s backend. Same on the phone.
- 🖼️ **Expression packs on Nano no longer send a leftover Comfy checkpoint** — the pack (and Edit) need a Nano edit id such as Qwen Image Max Edit. A `.ckpt` sitting in the Edit slot is cleared instead of billed as an invalid model. Same on the phone.
- 🖼️ **Nano Create waits up to 10 minutes** — slow remote image models no longer fail at two minutes with a raw timeout dump. You’ll see “try again or a faster model” if it still runs long. Same on the phone.
- 🖼️ **Image Studio stacks up to eight LoRAs** — four pickers, and More LoRAs for the rest. The list matches the checkpoint you have loaded. Draw Things can use them. Same on the phone.

- 🔎 **Web search only reads the line you just sent** — it decides whether to look something up, then the character still answers from the chat. Wiki looks a little further: the previous thing you said, the reply, and the line you just sent. Recipe cards still see the scene. Same on the phone.
- ⚡ **Long chats stay quicker on the next reply** — character growth, the fading opening scenario, and lore now sit after the transcript. When those change, only that tail is read again. Same on the phone.
- ✍️ **Impersonate in a group answers the person who just spoke.** Same on the phone.
- 📖 **“Where we are” is saved with the chat** — leave, switch models, or quit, and the recap is still there when you come back. Same on the phone.
- ⏱️ **The wait line on oMLX shows how long you have been waiting** until real progress arrives. Same on the phone.
