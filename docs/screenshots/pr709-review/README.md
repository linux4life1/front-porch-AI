# PR 709 parity review: desktop vs web, real screenshots

Review images for [PR #709](https://github.com/linux4life1/front-porch-AI/pull/709), "Starts away". Every item from the earlier reviews checks out against the code, including #5's gate and #6's write-up. What's left is One UI: every control exists on both sides, but they don't sit or look the same.

**How these were made.** Every image below is a capture of the running app, not a mock-up:
- **Desktop:** the Linux build, run under Xvfb through `flutter test integration_test/... -d linux`, then screenshotted from the X display.
- **Web:** the PWA served by that same running app's built-in web server, logged in and opened in Chromium.

Both branches went through the same script: Rawhide `c2561ff1` ("before") and this PR's head `074732f7` ("after"). The data is made up: a group "Harbor House" with Mara (Starts away on), Jules, and Odette (Realism off). Porch Life Afterglow is on. Themes are Porch dark, Slate light and Midnight dark, with wide and phone widths.

---

### 1. Member editor, Realism on: the row is in a different spot

Desktop puts **Starts away** right under the Afterglow switch, above Recovery. Web puts it after the whole Recovery block, just above Chaos. The web row also has no icon, while desktop shows a pause icon. The wording differs too: desktop says "starts **them** Away" and web says "starts **Mara** Away".

CI didn't catch the order because `test/hygiene/one_ui_parity_test.dart` lists the Optional Features rows as `Optional Features, Afterglow, Chaos Mode (Chance Time)`, and this PR didn't add `Starts away` to that list.

| | Desktop | Web |
|---|---|---|
| **Rawhide** | <img src="base-editor-on-porch-dark-wide.png" width="420"> | <img src="base-web-editor-on-porch-dark-wide.png" width="420"> |
| **This PR** | <img src="pr-editor-on-porch-dark-wide.png" width="420"> | <img src="pr-web-editor-on-porch-dark-wide.png" width="420"> |
| **This PR, Slate light** | <img src="pr-editor-on-slate-light-wide.png" width="420"> | <img src="pr-web-editor-on-slate-light-wide.png" width="420"> |
| **This PR, Midnight dark** | <img src="pr-editor-on-midnight-dark-wide.png" width="420"> | <img src="pr-web-editor-on-midnight-dark-wide.png" width="420"> |

**Fix:** put it in the same place on both sides; right under Afterglow is my pick. Add `'Starts away'` to the Optional Features list in `one_ui_parity_test` so CI holds the order from now on. Use the same icon and the same hint text on both sides; naming the member is nicer, so do that on desktop too.

### 2. Member editor, Realism off: different sections

Thanks for un-gating the web row. Both sides show it now. But desktop draws it on its own between Time & Day and the Optional Features heading, with no card around it. Web draws it inside the Optional Features card, above Chaos.

| | Desktop | Web |
|---|---|---|
| **Rawhide** | <img src="base-editor-off-porch-dark-wide.png" width="420"> | <img src="base-web-editor-off-porch-dark-wide.png" width="420"> |
| **This PR** | <img src="pr-editor-off-porch-dark-wide.png" width="420"> | <img src="pr-web-editor-off-porch-dark-wide.png" width="420"> |
| **This PR, Slate light** | <img src="pr-editor-off-slate-light-wide.png" width="420"> | <img src="pr-web-editor-off-slate-light-wide.png" width="420"> |

**Fix:** pick one section and use it on both sides. Since the Optional Features heading shows on both with Realism off anyway, putting desktop's row inside that card, above Chaos, is the smaller change.

The earlier comment that says the regenerated `member_bottom` goldens show this Realism-off layout is wrong. Those goldens show the layout where Porch Life hides Afterglow. No golden covers desktop with Realism off.

### 3. New-group wizard: different controls, and the web layout is broken

- **Desktop:** a bare switch on each member row, on the Members step. Its only label is a tooltip that appears after a 400 ms hover, so on touch there's no label at all. Nothing shows whether the value came from the card or from the user.
- **Web:** a labeled "Starts away" list on the Details step, with a checkbox and a state line under each name.
- **Web layout:** `.cg-field` is a vertical flex column, so each checkbox floats on a line of its own between the name and its state text, in every theme and at every width.
- **Confusing wording:** "their Back is kept" is what you see when you pick *off* for a member whose card says *on*. It doesn't say they'll start present.

| | Desktop (Members step) | Web (Details step) |
|---|---|---|
| **Rawhide** | <img src="base-wizard-porch-dark-wide.png" width="420"> | <img src="base-web-wizard-picks-porch-dark-wide.png" width="420"> |
| **This PR** | <img src="pr-wizard-porch-dark-wide.png" width="420"> | <img src="pr-web-wizard-picks-porch-dark-wide.png" width="420"> |
| **This PR, Slate light** | <img src="pr-wizard-slate-light-wide.png" width="420"> | <img src="pr-web-wizard-picks-slate-light-wide.png" width="420"> |

**Fix:** use the same control on both sides, with a visible "Starts away" label and the same state text (or none) on both. The web checkbox should sit on the same row as the member's name, the way Auto-Advance and Director Mode do above it.

The Members-step vs Details-step split isn't new. The voice pickers were already split that way and Starts away follows them on each side. You don't need to fix that here.

### 4. Phone width (400 px): the new switch covers the member's avatar

At 400 px the PR's new switch in the desktop wizard's member row sits on top of the member's avatar. The row also squeezes the member's name into a column one character wide at this width, but Rawhide already does that, so it's not part of this PR's fixes.

| Desktop wizard, Rawhide | Desktop wizard, this PR | Web wizard, this PR | Desktop editor, this PR | Web editor, this PR |
|---|---|---|---|---|
| <img src="base-wizard-porch-dark-phone.png" width="160"> | <img src="pr-wizard-porch-dark-phone.png" width="160"> | <img src="pr-web-wizard-picks-porch-dark-phone.png" width="160"> | <img src="pr-editor-on-porch-dark-phone.png" width="160"> | <img src="pr-web-editor-on-porch-dark-phone.png" width="160"> |

**Fix:** keep the switch off the avatar at narrow widths. Leave the squeezed name column alone here.

### 5. The PR body still needs `## Screenshots`

CLAUDE.md's One UI section asks every UI PR to show each changed screen, desktop and web, in the PR description itself. This body has no `## Screenshots` section. The PR-rules check passed only because it currently runs `main`'s copy of the workflow, which doesn't have the screenshot rule yet. That's a CI gap on my side, but the rule applies here regardless. Please add your own captures of the fixed screens to the body. The images on this page are for reviewing only; please don't link them in place of real captures.

---

**Before merge:** #1 through #5. None of them asks you to fix anything Rawhide already had.
