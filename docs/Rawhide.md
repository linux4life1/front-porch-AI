# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.
**Only list what landed after the last shipped nightly.** Clear this section when a new nightly goes out — delete the old bullets; do not accumulate them.

## Recent improvements (unreleased — ships in the next build)

- 🛡️ **Opening a saved chat no longer accepts a send into the last one** — the loading cover stays up until that chat is actually ready, so a fast Enter cannot write into the wrong conversation.

- ✨ **Enhance Review leaves empty rewrites unticked** — if the model returned a blank description or greeting, Use this starts off so Save cannot wipe what you already wrote.

- 📖 **Enhance lorebook adds entries instead of replacing the book** — new places from the story are appended; the original entries stay.
- ✍️ **AI Create can write in third person and/or past tense** — on the output-settings step, pick First or Third person and Present or Past. Default is still first-person present. Third person uses the Sex field for he/she/they (blank Sex → they/them). Applies to description, personality, example dialogue, and greetings. AI Enhance keeps that same voice instead of rewriting everything as first-person present.
- 🔒 **Web login is tighter** — changing the remote API URL or key from the phone now asks for your web password (and 2FA if you use it), the same way turning on a tunnel already did. Report on The Stoop still needs a written reason.
- 🔒 **Web login is tighter** — changing the remote API URL or key from the phone now asks for your web password (and 2FA if you use it), the same way turning on a tunnel already did. Test connection and the model list need that password too when the URL or key is not the one already saved. Report on The Stoop still needs a written reason.

- 👗 **AI Create fills wardrobe, pockets and ambitions** — after it writes the greeting it seeds what they are wearing and carrying, what they want long-term, and (if you turned 18+ on in the wizard) intimate likes and limits. You can still edit every chip on the Porch Life step.

- ✨ **AI Enhance proposes Porch Life the same way** — tick wardrobe / ambitions / likes on the interview checklist. Review shows Before vs After with a Use this switch, just like description. Untick to keep what the card already had. A mute or partial proposal cannot wipe an authored wardrobe — empty lists stay off the write.

