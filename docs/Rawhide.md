# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.
**Only list what landed after the last shipped nightly.** Clear this section when a new nightly goes out — delete the old bullets; do not accumulate them.

Last shipped nightly: `rawhide.20261001.06827b2`. Everything below is unreleased.

## Recent improvements (unreleased — ships in the next build)

- 📚 **Porch Stories has a Studio engine** — a new way to write a story that interviews your cast, checks every planning step with a second model call, writes beat by beat with a continuity check, and patches only the lines that slipped instead of rewriting. It remembers hard facts ("Teodor's left hand is burned, from scene 3.3") and how everyone feels about everyone else, scene by scene. The original engine is still there as **Quick**; pick either on the new **Engine** step of the New Story wizard, along with a target length (novella / novel / epic), a format (novel or audio-drama script), and which model does the planning, the prose and the checks. Stories made from a chat still work the way they did — the chat is fed to every stage as canon.
- 🧭 **A story is now a studio** — a sidebar with Overview, Structure, Write, Read, Director, Cast, Relationships, Lore & continuity and Run log. **Continue writing** does one scene per tap; **Stop** ends any run at the next safe point and keeps what was written. Same on the phone.
- 🎬 **The Director** — type a change in plain words ("make Teodor hide that he set the fire"), get a list of edits, tick the ones you want, apply, and undo the whole set later. "Protect written prose" keeps rewrites off scenes you've already got.
- ✍️ **The writer shows its work** — quality chips per beat (words, dialogue share, rhythm, sensory detail, adverbs, banned phrases), continuity fixes as strike-through with an Undo, a rolling list of phrases the model keeps repeating (it bans them for the next chapter), and a writing lens per scene (Kinetic action, Slow-burn romance, Suspense, Reflection… 17 in all).
- 👥 **Cast, Relationships, Lore & continuity** — interviews in each character's own voice, a grid of who feels what about whom with the scene that moved it, the facts the story must keep straight, lore files you can drop in, and a "Test search" that shows what the writer would see.
- 📖 **The reader can scroll** — a Scroll mode beside the page-flip book, with chapter headings, Read aloud, and your place remembered.
- 🧾 **A run log per story** — every model call with its prompt, reply, time and verdict, for when a story goes wrong.
- 🛠️ Quick engine: planning stages now answer in simple tags (far fewer broken replies from small local models — a JSON answer still works), and the rolling banned-phrase list applies there too. Old stories open unchanged.

- 🔢 **Every message has a number** — shown under the avatar, starting at #1. The numbers on Journal and Growth Rings memories now match them (they used to start at #0), and tapping one lands on the start of that message instead of its middle. Same on the phone.
- 💬 **Your messages are laid out like the character's** — your picture on the left, your name on top, edit, fork and delete at the top right.
- 💞 **Generate reply now moves feelings and needs** — when your message is the last one (after deleting or stopping a reply, or forking at your line), Generate reply scores your message like a normal send, without counting it twice. Deleting the newest reply also undoes any quests it suggested. Group chats too, and the same on the phone.
- 🔀 **The model button in a phone chat works** — the model list shows and can be tapped, and you can switch provider right there (OpenRouter, Nano-GPT, xAI, LM Studio, KoboldCpp and more). Switching provider asks for your web login password, like Settings does.
- 💭 **Editing a message on the phone keeps its Thinking** — the editor's Thinking section now shows the reply's reasoning, and saving no longer erases it.
- 📜 **Reading old messages no longer snaps you down** — opening a Thought, scrolling inside one, or scrolling up through a long chat keeps you where you are. Same on the phone.

- ✏️ **Editing a message works on the phone again** — Save, Cancel and the text box answer taps, and on a notched iPhone the buttons sit below the clock. If a save fails, the editor stays open with your text and says why.
- 📱 **Phone taps that fail now say so** — regenerate, continue, swipe, fork, delete, switching chats, group settings and the rest show a plain reason instead of doing nothing.
- 📱 **A screen that breaks on the phone shows a way out** — Reload or Back to library, instead of a blank page.
- 📖 **Reading a story on the phone no longer overwrites it** — turning a page saves only your place, not an older copy of the story.
- 📱 **Leaving a chat mid-reply keeps that reply out of the next chat.**
- 📱 **With a chat theme picture, the Regenerate and version-picker windows cover the message box** like they do without one.
- ⚡ **Long chats on the phone stay smooth while a reply streams in.**
- ⌨️ **Japanese, Chinese and Korean keyboards no longer send mid-word** when Enter picks a character.
- 🖼️ **A photo the phone can't read is no longer dropped quietly** — your text and photo stay put with a note.

- 🤖 **xAI is a chat backend** — pick xAI in Settings → Backend (or Model Settings) and sign in with SuperGrok to use your subscription allowance instead of paid API credits. The sign-in is unofficial and at your own risk; an xAI API key also works. The sign-in borrows xAI's own Grok CLI login, so xAI may block it at any time. If your allowance runs out, chat says so in plain words. Same on the phone.

- 🧑 **A brand-new chat starts as your default persona** — left-clicking a character you've never opened now begins the chat with your default "Speak as", instead of carrying over the persona from the chat you were just in. Chats you've already opened keep their own persona. Same on the phone.
- 🖼️ **Saved ComfyUI edit workflows get the real prompt** — a chained or multi-step prompt now flows into your saved Edit workflow instead of being dropped, and Qwen image-edit keeps the denoise strength you set instead of snapping back to a default. Same on the phone.
- 🖼️ **Image before/after comparisons wait until both sides are done** — Image Studio no longer posts a half-finished ComfyUI comparison; an incomplete compare is skipped instead of shown broken.
