# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.
**Only list what landed after the last shipped nightly.** Clear this section when a new nightly goes out — delete the old bullets; do not accumulate them.

Last shipped nightly: `rawhide.20260906.7059c91`. Everything below is unreleased.

## Recent improvements (unreleased — ships in the next build)

- 🖥️ **Waifu Coder** — sit down with a character who codes: Plan/Build, in-folder edits without nagging, tasks saved under `.waifu`, they review and test before they talk, and that spoken line ends the turn. The first move on a code change is a tool, not a ten-step think. “Done” only counts after a real write and a passing check. She does not re-read a file that is already in the prompt. The context bar is the real request (system, tools, and the model's own token count). Old turns fold into a recap when the window fills, like other coding agents. Plan/Build/Yolo is one control. MCP tools update when you connect a server. Leave Stop. A porch you already sat down on does not re-quiz honesty. Plan titles can have colons. Accepting a plan does not wipe tasks you already had. You can type the next task while they are still working; it waits in line. If the model hides a write in the chat bubble, it still hits disk. Long leftover thoughts are clipped. Desktop only.

- 🔑 **Tavily key stays after a restart** — it is saved with the rest of Settings (same place as OpenRouter keys and MCP URLs). The macOS keychain copy was vanishing on relaunch.

- 🎭 **Realism still runs when a model will not turn thinking off** — if an eval gets a 400 while asking for thinking off (GLM 5.3, Kimi, or the next host's wording), we keep going the Kimi way: let it think, salvage the JSON, don't drop bond/needs. Remembered for that model so the next judge is not two wasted 400s.

- 🔊 **Mac voices speak again** — Kokoro, Piper, and Whisper on macOS were looking for the Sherpa library inside a nested folder the app never ships. Test Voice and the chat speaker buttons work; the model download was never the problem.

- 🔑 **OpenRouter and Nano-GPT keep their own API keys** — switching the Backend chips restores that host's key (or leaves the box empty). Check Connection can no longer go green on the other provider's leftover key while a story fails with a missing auth header.

- 🎭 **OpenRouter models move relationships, Needs, and scene time again** — those judges now ask OpenRouter for a JSON schema (and the live overlay path finally sends the same forced tool / `require_parameters` payload as the background POST, with room for thinking models). Nano-GPT, local MLX, and LM Studio stay on tools. Same on the phone.

- 🖼 **Drop a photo on the composer** — Finder/Explorer onto the chat bar, or the attach button. One photo per send. The picker is still there if you prefer it.

- 💭 **Thoughts stay folded** — live and finished Thought chips stay shut until you tap the chevron, including while they are still thinking. A new reply does not pop old think blocks open. Same on the phone.

- 🔌 **Connect Docker MCP / stdio add cannot stick disabled** — if the handshake throws, the button comes back. Same on Settings → Porch Life.
