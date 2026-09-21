# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.
**Only list what landed after the last shipped nightly.** Clear this section when a new nightly goes out — delete the old bullets; do not accumulate them.

Last shipped nightly: `rawhide.20260920.5fe816e`. Everything below is unreleased.

## Recent improvements (unreleased — ships in the next build)

- 👥 **Guests can sit in a group without becoming full members** — `/create`, `/join --lite`, and `/scan` work in a group now. They take turns and can be Away like anyone else (a guest who walks off is marked Away; Needs and Realism still stay off). Promote them with `/promote Name` or the roster button. Turning a 1:1 into a group keeps the guests as guests. Same on the phone.

- 📦 **Guests survive a Full Front Porch chat share** — exporting a `.fpchat` now remembers who was a Scene Guest (1:1) or a soft group member. Importing onto the same open cast puts them back as guests. Old files still open. Same on the phone.
