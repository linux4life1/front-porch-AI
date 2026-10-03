# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.
**Only list what landed after the last shipped nightly.** Clear this section when a new nightly goes out — delete the old bullets; do not accumulate them.

Last shipped nightly: `rawhide.20261001.06827b2`. Everything below is unreleased.

## Recent improvements (unreleased — ships in the next build)

- 📚 **Porch Stories Studio** — a second story engine beside the original (now called **Quick**). Studio interviews your cast, double-checks every planning step, writes beat by beat with a continuity check, and patches only the lines that slipped. Each story opens as a studio: Structure, Write, Read, a **Director** that turns a plain-words note into edits you can tick, apply and undo, plus Cast, Relationships, Lore & continuity and a run log. Porch Stories got a whole new look to go with it — a warm, book-shop studio with a shelf of your stories, a four-step wizard (Idea, Cast, Shape, Engine) and the same layout on desktop and phone. Any job can run on any model you have set up — the chat model, your worker, or a KoboldCpp / oMLX / LM Studio / cloud host of your choice, with local models swapping onto the GPU the way chat already does. On models that support it, the planning and review steps use real tool calls (plain tags are the fallback), and **Stop** ends any run safely. Chat-based stories still use the chat as canon and old stories open unchanged.
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
