# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.
**Only list what landed after the last shipped nightly.** Clear this section when a new nightly goes out — delete the old bullets; do not accumulate them.

Last shipped nightly: `rawhide.20260906.7059c91`. Everything below is unreleased.

## Recent improvements (unreleased — ships in the next build)

- 👋 **Group friends can come back** — if someone wandered off (Away), `@Ana` asks her to check in this turn. Just saying “Ana, you coming?” does not drag her back — she may stay Away. Or they quietly notice and rejoin on their own. `@Bea` still gets Bea when she is already with you — a returning friend does not talk over her. A mid-sentence “I told Ana about it” does not drag them back. People at work stay on the clock. If the whole porch is empty, you still get the Away line after a check-in that did not stick, and a later message can still bring someone back. Same on the phone.

- 🏡 **Stoop NSFW toggle refreshes the porch** — “Show NSFW content” now reloads The Stoop right away. You no longer have to leave and come back. Same on the phone.

- 📦 **Downloaded models show up in Model Selection** — after a download finishes, Settings → Model Selection lists the new GGUF without leaving the page.

- 🎯 **Switching hosts clears the model picker** — Kobold, OpenRouter, Nano-GPT, and the rest no longer keep the last host’s model id. Pick a model that belongs to the new host. Realism evals only clear when that host changes. Same on the phone.

- 📋 **Copy a reply like any other text** — drag across the words in a bubble (including an open Thought) and Copy. The character name and the buttons stay out of it. Sending a new line no longer yanks the transcript if you had scrolled up. Same on the phone. macOS Edit → Find is gone; it never searched the chat.

- 📦 **Backyard archives keep every picture** — a `.byaf` import now puts the first image on the portrait and the rest in the Avatar Gallery. You can turn the extra looks off on desktop. Phone and browser import `.byaf` the same way (not PNG-only). Desktop work started by [@Lufou](https://github.com/Lufou).

- 💬 **Thinking-only replies show up as speech** — some Nano/Qwen models put the whole line in the hidden thought channel after Realism finishes. The bubble was empty even though the chips updated. That thought is now the spoken line. Same on the phone.

- 🪪 **Stoop blurbs match the website** — tile summaries get two full lines with a real “…”. Open a card and the whole listing blurb sits beside the portrait. Description and Personality are their own drawers, like hub.frontporchai.app.

- 🛠️ **Waifu Coder OpenCode updates like Kobold** — Settings and the Waifu sidebar check GitHub for the newest OpenCode. First sit-down still downloads if the closet is empty. A tap installs that latest; it does not jump versions by itself. Homebrew is still not used.

- 🧩 **Pick the Realism evals model from chat** — the in-chat Model Settings sheet now has the same Same as chat / Different host controls as Settings → Backend. You do not have to leave the chat to point feelings/journal/growth at another host or model. Same as chat stays one dropdown. Phone Settings already had this; the PWA has no in-chat Model Settings sheet.

- 🪪 **Character creator no longer goes silent on hidden-thinking models** — some cloud models (GLM / Qwen-class) accept “don’t think” then think anyway and burn the short step budget, leaving the field empty. We notice that empty cut-off and retry the step once with more room. Chat replies still use your length cap. Same on the phone.

- 🔁 **Regen critique stays fully readable** — the optional “why this take was wrong” box grows downward. A long note no longer disappears into a sideways scroll. Same on the phone.

- 🧩 **Realism evals sit under Chat speech** — Settings → Backend is one chat stack (host, key, check, model) first. Below that, Realism evals can follow the chat host or use a different one. Same host does not ask for a second key. Two cloud models are fine, including two models on the same host. Two local engines take turns on the GPU: Realism evals keep the worker loaded, and chat speech’s model comes back only when she talks (not after every check). On the one KoboldCPP the app already starts, the two slots can each name a GGUF and its own .kcpps — same pair stays loaded; different pairs unload and reload on that same process (no restart). Chat speech still keeps its vision projector; Realism evals do not. A local host with no unload path still stays on chat speech. Leave the worker off and everything stays on one backend. Same on the phone.

- 🌍 **World from Wiki** — a studio wizard that scouts a saved wiki (Fandom or Tiddly) and proposes a short shelf of cards — era, hub, leaf, crown — instead of one card per page. You sign the ones to write. Climate stays off unless you turn it on; if climate write misses, it stays off (no stock Temperate). Stop is on the write step. Needs a tool-calling model. Same on the phone.

- 📖 **Neokosmos works in the same Wiki picker as Bleach** — paste a TiddlyWiki URL (GitHub Pages path is kept). She can search, then open a named page. Fandom / MediaWiki is unchanged.
- 🪟 **Mac title bar is a real bar again** — after Flutter 3.47 the traffic lights were sitting on the same charcoal as the page. The native title strip is opaque. Windows and Linux stay a normal window.

- 🔁 **Tell Regen why that take was wrong** — optional box on the last reply. Leave it empty and Regen is the same as today. Type a reason and she sees a short clip of the rejected take plus your note, then writes a new swipe. It is not a chat message and it is gone on the next turn. Same on the phone.

- 📖 **She can look up a second wiki page before she talks** — if the first clip is thin, she may fetch another, then speak once in character. Not a lecture. Same on the phone.

- 📖 **Looking something up does not spend her spoken thinking budget** — wiki and web tool picks use the same short, careful settings as Realism checks (not your max-gen or thinking sliders). Her actual line still uses those sliders. Same on the phone.

- 🎭 **Thinking models no longer freeze the Realism spinner** — if a fused check starts rambling, we cut it and still update bond, trust, and mood. Same on the phone.

- 📖 **Save as many wikis as you want** — Porch Life keeps a list (Bleach, One Punch Man, …). The chat sidebar Wiki picker chooses which one this chat uses, or none. A 1:1 pick is remembered for that character, so Sophia can default to Bleach and Mirin to One Punch Man.

- 🧰 **Choose JSON recipe cards** — Porch Life has a Choose files button that copies `.json` cards into your library `tools` folder. Other file types stay out. Phone and browser still have no file picker there.

- 🔎 **Search results no longer steal the reply** — after a lookup, the character still starts talking at their own `Name:` line. Wiki text sits above that, not after it.
- 🕐 **Clock chevrons work with Realism off** — if you turned on the standalone story clock in Porch Life, the ±30 minute arrows and Story Calendar work on desktop and phone. They used to look paused whenever the engine was off.

- 🔎 **Web Search happens in the reply, not a silent extra trip** — the character sees the search tool while they are actually talking. If they look something up, the result lands and they speak; if they already know, they just speak. Same on the phone.

- 🛠️ **GLM 5.3 Journal and Growth keep their tools** — a think-budget of 0 is Off, and that model refuses Off. We stop sending 0 after it says so, instead of dumping tools and getting an empty XML round.

- 🌳 **Growth Rings grow again on a hot scene** — a bond spike used to re-check every turn and only water the same two rings. Checks wait for the slider (or a real kick) so new rings can land and old ones can fade. Journal is unchanged. A scored bond/trust spike now actually arms that kick — Growth was waiting the full slider because the flag never got set.

- 🔎 **Reading Size is one knob for what you read** — bubbles, the chat input box, and message edit follow that slider. Sidebar stays put.

- 🖥️ **Waifu Coder wrap-up speaks once** — after tools stop, the in-character recap is one spoken bubble, not two copies of the same goodbye.

- 🖥️ **Waifu Coder follows Model Settings** — switching Nano-GPT / oMLX / OpenRouter (or the model on that host) restarts the coding session onto that backend. The spoken bubble is the in-character voice pass after tools stop; Kimi-style thinking-only wrap-ups still land as speech. The context bar counts OpenCode tools and MCP schemas, not just the character card, and oMLX no longer shows a 256k Kobold window.

- 📣 **Stoop Inbox notifications show the actual notice again** — they were painting as empty bars because Flutter will not draw a rounded card with a different-colored left stripe.

- 🔀 **Swap OpenRouter and Nano-GPT in one tap** — Model Settings is a row of hosts (KoboldCpp, OpenRouter, Nano-GPT, LM Studio, Custom; oMLX on Mac only). Each host keeps its own key. The model picker blanks so you pick one that belongs there. Same on Settings and the phone.

- 🖥️ **Waifu Coder is powered by OpenCode** — the custom coding engine is gone; your coworker now tools through OpenCode.
- 🎭 **Characters are not “she” by default** — generic prompts, mood copy, and Waifu Coder blurbs use they/them unless the card’s Sex field is actually female (woman / she / her still maps to she/her).

- 🖥️ **Waifu Coder Jail / Disk stay honest** — sit-down scope is chips, not stuck radios. Picking Disk after a jail sit-down asks honesty again; confirm actually opens the disk. A denied Plan write says it did not write. Wiping the folder above the sit-down is still denied.

- 💬 **Add Greeting works again** — editing a character (or group) that had no alternate greetings used to crash the moment you tapped Add.

- 🔑 **Tavily key stays after a restart** — it is saved with the rest of Settings (same place as OpenRouter keys). The macOS keychain copy was vanishing on relaunch.

- 🎭 **Realism still runs when a model will not turn thinking off** — if an eval gets a 400 while asking for thinking off (GLM 5.3, Kimi, or the next host's wording), we keep going the Kimi way: let it think, salvage the JSON, don't drop bond/needs. Remembered for that model so the next judge is not two wasted 400s.

- 🔊 **Mac voices speak again** — Kokoro, Piper, and Whisper on macOS were looking for the Sherpa library inside a nested folder the app never ships. Test Voice and the chat speaker buttons work; the model download was never the problem.

- 🔑 **OpenRouter and Nano-GPT keep their own API keys** — switching the Backend chips restores that host's key (or leaves the box empty). Check Connection can no longer go green on the other provider's leftover key while a story fails with a missing auth header.

- 🎭 **OpenRouter judges cost one API call each** — they use native tools (the documented Chat Completions shape) instead of trying JSON-schema first and then tools. Models that do not advertise tools skip the tools POST. Nano-GPT, local MLX, and LM Studio are unchanged. Same on the phone.

- 🖼 **Drop a photo on the composer** — Finder/Explorer onto the chat bar, or the attach button. One photo per send. The picker is still there if you prefer it.

- 💭 **Thoughts stay folded** — live and finished Thought chips stay shut until you tap the chevron, including while they are still thinking. A new reply does not pop old think blocks open. Same on the phone.

