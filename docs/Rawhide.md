# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.
**Only list what landed after the last shipped nightly.** Clear this section when a new nightly goes out — delete the old bullets; do not accumulate them.

## Recent improvements (unreleased — ships in the next build)

- 📚 **Lorebook-only worlds** — a place can be facts without weather. Flip off Climate, weather, and place traits and the world is description + lore only: no forecast, no sidebar chip, no atmosphere or gravity. Existing worlds stay as they were. Same on the phone.

- 🎂 **Birthdays** — set a year, month, and day on the character and on your persona (no February 29). The Journal keeps one card per person that heats up in the two weeks before, so they know how old everyone is without listing a wishlist. Both birthdays can fall on the same day. Objectives may freeze an outing from their likes. Same on the phone.

- 🎯 **Four side quests** — a character can hold four side goals at once (was two), so a birthday outing does not kick something you already set. Same on the phone.

- ⚡ **Realism / Journal / Growth tool calls are no longer the slow path** — they ask for the one function they need, use an eval-sized budget, and the overlay starts immediately. If your model still hates tools, Porch Life → Native tool calling off keeps the pill honest ("supported — using JSON") instead of pretending the model cannot. Same on the phone.

- 🧠 **Evals and Continue on heretic / uncensored local models no longer think until the cap** — journal, objectives, and Needs checks were burning the token budget mid-thought and coming back empty; Continue was dumping a think block into the middle of the line. Character replies still think when Request thinking is on. Same on oMLX, LM Studio, llama.cpp, and Kobold. Same on the phone.

- 🔋 **Reprocess Needs only scores the needs you tick** — Energy (or Energy + Hunger) is one short eval, not a full seven-need pass and not four oMLX jobs. Unticked needs keep the numbers they already had. Same on the phone.

- ✅ **Verified Stoop creators now wear the gold or blue check** — owner gold, trusted blue, same shape as the hub. Same on the phone.

- ↻ **Regenerate no longer ignores you while needs is still scoring the last reply** — it kills that eval and starts the new swipe on the spot. Same on the phone.

- ⏳ **Sending while the last reply is still being scored no longer looks like the message vanished** — a strip above the box says it is queued. Same on the phone.

- ⑂ **Fork a chat from the phone** — same “new branch from this message” as desktop. The old conversation stays put.

- 🎛️ **Phone Settings now has the rest of the sampler row** — Top-P, Top-K, DRY, dynatemp range, stop sequences, banned phrases, sanitise-history, and the global system prompt. Voice & Media can turn speech on without opening the desktop tab.

- 👥 **Stoop groups and places show their real contents on the phone** — member carousel and greetings for groups; climate, traits, and lore for worlds.

- 💬 **Stoop comments go to the hub now** — desktop and phone. They used to vanish when you quit the app. The card owner can turn discussion on from the listing.

- 🔐 **Only the Vite dev server may use cookies from localhost** — a random local page on another port cannot ride your session.

- 🧼 **Filthy means they reek and hate it — not that they magically freshen up** — hitting rock-bottom hygiene, they notice and feel awful, but the meter stays down until they actually wash. Characters who enjoy being musky still like it. Same on the phone.

- 🎭 **Alternate greetings now seed Needs the same way they seed bond and mood** — same section cards as the Realism editor, including hunger and the rest. Blank still inherits the card. Same on the phone.

- 🔐 **Signing Tailscale in from the phone now asks for your web password** — same confirm as turning HTTPS on, so a stolen session cannot bind this computer to someone else's tailnet.

- 💡 **Light mode on Group Settings, Chat History, Database Cleanup, and the Kobold log** — helper text and empty states are readable on paper, not white-on-white.

- 🧹 **Deleting a group now takes its diary, growth, and memories with it** — leftover knowledge from that chat does not keep showing up elsewhere. Same when you delete a character: their Data Bank goes too.

- 🛟 **Renaming a chat from Chat History no longer resets Porch Life** — Realism, Needs, Chaos, and the relationship numbers stay as they were. Same on the phone.

- ▶️ **Continue keeps speaking as whoever started the line** — a Scene Guest or a group member with a shared name is not hijacked by the host. Same on the phone.

- 👜 **Taking back a gift from the middle of a group chat returns it on both sides** — unique things no longer exist twice. Swiping a “I set my keys down” line keeps the diary matching the kit. Same on the phone.

- 💛 **Intimate preferences now guide the Realism evals** — listed tastes can change the direction of a score, not only how hard it hits. Blank preferences keep the old defaults. Same on the phone.

- 🧠 **Thinking strength chips only show when this model actually has levels** — a host that accepts every value is not a menu. On/off still works. Same on the phone.

- 💭 **Thinking dumped inside the reply is folded into the Thought chip** — same as when the host already splits it. Same on the phone.
