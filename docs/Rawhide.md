# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.
**Only list what landed after the last shipped nightly.** Clear this section when a new nightly goes out — delete the old bullets; do not accumulate them.

Last shipped nightly: `rawhide.20260906.7059c91`. Everything below is unreleased.

## Recent improvements (unreleased — ships in the next build)

- 📋 **Waifu Coder Plan mode now writes a real plan** — in Plan they explore, then save a markdown plan under `.waifu/plans/` (a turn without that file is not done). The Plan panel sits on the main stage: Accept → Build (steps become todos), Revise, or Discard. A draft plan will not silently flip to Build — Accept it, or stay in Plan. They still cannot change project source until you accept. Personality stays the card’s.

- ✅ **A patch is not “done” until they check it** — after they write, edit, or patch a project file in Build or Yolo, they must re-read that file or run a real test/analyze command before claiming the step finished. Looking at the file before they change it does not count, and `--help` / dry-run anywhere in the command is not a test — even if a real test is chained after `||`. Same rule with or without a pinned plan. A plan step stays pending until both the change and that check land — the task list cannot show the step finished while the plan still says pending. Personality stays on the spoken line.

- 📊 **Waifu Coder remembers how full the context bar is** — sit back down on a porch and the meter shows the last turn, not a fake 0. Old sessions still start at 0 until you send once.

- 🎨 **Waifu Coder themes actually paint the bubbles** — Sakura (and the rest) plus your custom bubble/text colors apply in the session instead of writing to the last 1:1 chat and leaving the coworker in default colors.

- 🔧 **Waifu Coder tools show while they run** — a live chip appears the moment they pick up a tool, then flips to ok or fail when it finishes. You are not staring at a black box until the receipt lands.

- 🧾 **A spoken “todo done” needs a real todowrite** — if they claim they marked a todo complete or ran `todowrite` but no successful chip landed this turn, the turn contract asks again, then stops instead of pretending. Thinking out loud does not count.

- ✅ **Waifu Coder Tasks look like a real list** — pending is an empty box, the current job is a play mark, done is checked and struck through. No more raw `in_progress: …` sludge in the sidebar.

- ♾️ **Waifu Coder is not capped at chat Max Output Tokens** — a turn can fill the rest of the context window so a tool call is not cut off mid-file. Chat still uses that slider. One reply bubble per send: reads/writes/bash stack as a quiet log above it, then she speaks. The old 20-step cutoff is a runaway fuse at 80.

- 🎭 **OpenRouter models move relationships, Needs, and scene time again** — those judges now ask OpenRouter for a JSON schema (and the live overlay path finally sends the same forced tool / `require_parameters` payload as the background POST, with room for thinking models). Nano-GPT, local MLX, and LM Studio stay on tools. Same on the phone.

- 🖼 **Drop a photo on the composer** — Finder/Explorer onto the chat bar or Waifu Coder, or the attach button. One photo per send. The picker is still there if you prefer it.

- ↵ **Enter sends the task** — Shift+Enter still makes a new line. The last-write preview has an X to dismiss it.

- 🧠 **Thought chevron works while they are still thinking** — tap to collapse (or expand) the live think block; the timer keeps running. It used to ignore you until the next think started.

- 💭 **Finished thoughts stay folded** — only the line that is still thinking opens by itself. Older Thought chips stay shut until you tap the chevron, even while a new reply is generating. It used to pop every old think block open for the whole turn.

- 🖥️ **Waifu Coder pairs real coding power with a real character voice** — pick a V2 card, then let that coworker read, search, patch, write, run tests, and verify in one tool loop while still sounding like herself. The Sit-down gate offers **Folder jail** (the safer default) or an honestly disclosed **Whole-disk** scope; either way, secrets, environment dumps, destructive Git, force-pushes, and machine/parent wipes stay hard-blocked. `apply_patch` keeps existing-file edits surgical, Stop kills active commands even inside nested workers, and Explore/General may delegate one more bounded task layer before the tree ends. MCP remains per-session opt-in and cannot pivot a Bearer token to another host. Photos accept bounded PNG/JPEG/WebP input and land under `.waifu/inbox/`. Skills and workflows stay under `.waifu`, Plan/Build/Yolo keep their charm, and the visible bubble remains her spoken line instead of a source dump. Not Claude Code; not for code you cannot afford to lose. Desktop only.

- 🎙️ **Patches need both proof and personality** — ask for a code change and Waifu Coder will not accept sass alone as “finished”: a real write/edit/patch receipt must land, then the final bubble must sound like the card instead of “Done.” Empty post-tool replies get a speech-only retry, and words spoken beside a tool call are kept rather than wiped. The empty screen also tells the truth about Folder jail versus Whole-disk scope.

- 🔌 **Waifu Coder MCP now needs both invitations** — its own checkbox only exposes servers already enabled for the active character chat. A global server switch alone cannot quietly enroll remote tools; Plan still blocks mutation and Build still asks.

- 🪟 **Windows command note** — Waifu Coder’s v1 command tool needs Git Bash (or another `bash`) on PATH. Without it, read/edit/apply_patch/write still work and command attempts return a plain start error; Waifu Coder does not silently rewrite bash into PowerShell.

- 🔌 **MCP tools: tap Docker, don't invent a URL** — Settings → Porch Life. Docker Desktop does not give Front Porch an address; the Docker chip fills the local gateway, Find local looks on port 8811, and a token only appears if the server asks. A success is "Connected — 110 tools", not a wall of names. The URL, switch, and token survive an app restart without asking for your Mac password. Same on the phone.
