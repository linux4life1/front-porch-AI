# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.
**Only list what landed after the last shipped nightly.** Clear this section when a new nightly goes out — delete the old bullets; do not accumulate them.

Last shipped nightly: `rawhide.20261006.fbe655b`. Everything below is unreleased.

## Recent improvements (unreleased — ships in the next build)

- ⌨️ **Typing in the AI Character Creator no longer lags on Windows** — every key used to save the whole creator form, which on Windows rewrote the settings file dozens of times per letter. Typing now saves once you pause, and only what changed.
- 🪟 **A file window that fails now says so** — when the window for choosing a file or folder, or for saving, doesn't appear, you get a plain explanation with a Try again button instead of a click that does nothing. A folder the app can't read says so too. And exporting a character, place, chat or story whose name has characters Windows doesn't allow in a file name (such as `:` or `?`) now opens the save window instead of waiting forever.
- **The AI creator has a Greetings step**, on the desktop and the phone. After a character is generated, each greeting gets its own card: edit it, rewrite it (steer the rewrite with one line, like "start at the harbor at dawn"), delete an alternate, or add another one, written straight away. On the desktop, rewriting the first message leaves the outfit as it was, and the Realism step offers to read it again from the new opening.
