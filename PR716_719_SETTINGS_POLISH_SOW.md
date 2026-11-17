# SOW — Settings Polish After the 716-719 Redesigns

**Project:** Front Porch AI (Rawhide)
**Feature:** Post-merge fix pass on the four settings-redesign PRs (#716
General, #717 prompts/side, #718 Appearance, #719 Generation)
**Status:** Approved for implementation — maintainer directive 2026-11-17
**Owner:** Agent (fix PR branch `fix/settings-polish-716-719`)
**Reviewers:** Maintainer

Evidence base: `docs/design/pr716-719-merged-findings.md` (19 items, each
with file:line, verified on the merged validation tree
`validation/pr-716-719-merge`). This SOW converts that punch list into
scope; read the findings doc for the proof, this one for the plan.

---

## 0. What the four PR bodies claimed vs what the tree says

Four redesigns, one model, and the drift shows. The author's part — desktop
and web twins, tests, screenshots on all four — shipped; the model's part
is what this pass cleans up.

| Claim (PR body) | What the tree says | Resolution here |
|---|---|---|
| 716: "Modularized `general_tab.dart` from 242 lines down to 56" | The real `GeneralTab` file is 134 lines, and a second dead 23-line `general_tab/general_tab.dart` barrel exists that nothing imports | §5, one file, one name |
| 718 cites `chat_typography_section.dart` and `AppearanceSettings.test.tsx` | Neither file exists in the diff or the tree | Corrected in this PR body; no code change |
| 716: "100% compliance with settings-parity-manifest" | True — the manifest checks that markers exist, not that they are visible. Two redesigns put the label on a control the CSS then deleted from the a11y tree | §2 blockers 2-3; §6 adds a coverage class that cannot miss this again |
| 719: `chat_settings` goldens "updated" | Updated on Windows; the Linux runner still fails them at 0.22% | §6, regenerated on the exact runner image via `update-goldens.yml` |

## 1. Scope

In: every accessibility defect, every red CI job, every copy/format drift
between desktop and web introduced or exposed by #716-#719, the dead barrel,
and a golden-coverage class that pins the three redesigned tabs.

Out: pre-existing drift older than these PRs (tracked in §7), product
decisions the maintainer owns (§8), and any behaviour change not listed
here. One room at a time: this is a fix pass, not a redesign of a redesign.

## 2. Blockers — the four red CI jobs

### 2.1 `StyledDropdown` goldens stale (716)

716 edited `lib/ui/widgets/styled_dropdown.dart` and shipped zero golden
updates. CI: `_goldens/leaf_widgets/styled_dropdown.{dark,light}.png` fail
at 4.91% (~1178 px) on both modes.

**Fix:** none to code — the change was intentional. Regenerate baselines
via §6 flow.

### 2.2 `chat_settings` goldens made on the wrong OS (719)

719 regenerated `_goldens/dialogs_more/chat_settings.{dark,light}.png` on
Windows; pixel baselines are runner-image-locked, and CI renders Linux.

**Fix:** same — §6 flow. One regeneration covers 2.1 and 2.2 together.

### 2.3 Hidden accessible toggle (717) — real user defect, not a test bug

`web_ui/src/styles/settings.css` gives `.toggle-switch input`
`opacity: 0; width: 0; height: 0`, and both new cards
(`FollowStreamingSettings.tsx`, `MessageSideSettings.tsx`) put the
`aria-label` on that 0×0 input while the painted control is the sibling
`.toggle-slider` span. Playwright: `journeys.spec.ts:507` times out 90 s on
`setChecked` — "element is not visible" (desktop-chromium and
phone-webkit). A screen reader is offered a zero-area control; a click
target exists only by the CSS accident that the label wraps it.

**Fix:** make the input the painted control — the app already ships this
correctly as `input.switch` (`settings.css:846`, used by
`ThemeModeSettings.tsx` "Dark mode"). Adopt the same idiom in the toggle
cards; keep every `aria-label` byte-identical. Do not edit the spec to
accommodate the component.

### 2.4 Device-theme select deleted from the a11y tree (718)

New CSS `.sr-only-select { display: none; }` (`settings.css:210`, absent on
Rawhide) removes `ThemeModeSettings.tsx`'s `<select aria-label="Theme on
this device">` from layout **and** the accessibility tree. Playwright:
`journeys.spec.ts:1751` can never resolve the label; the failure snapshot
shows the control simply absent.

**Fix:** visually-hidden clip, not `display: none`:

```css
.sr-only-select {
  position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
  overflow: hidden; clip-path: inset(50%); white-space: nowrap; border: 0;
}
```

## 3. Parity convergence — copy and formats

Maintainer ruling (2026-11-17): **when in doubt about UX drift, the Dart app
is the UX to mirror.** Every canonical below is therefore the desktop side;
the web moves. Labels, case and value formats must match exactly. Web unit
and parity test assertions that pin the old web strings move with them
(`approved-test-change`).

| # | Item | Canonical (always desktop) | Changes |
|---|---|---|---|
| 3.1 | Porch Life pointer: desktop "Porch Life **tab** now" vs web "**section** now" | **tab** — both surfaces show a tab strip labelled Porch Life | `web_ui/src/pages/SettingsPage.tsx` copy + its assertion in `SettingsPage.parity.test.tsx:307` |
| 3.2 | "Reading Size" / "Bubble Opacity" (desktop) vs "Reading size" / "Bubble opacity" (web) | **Title Case as desktop spells it** — the ruling beats house-style taste | web labels in `BubbleOpacitySettings.tsx` and the reading-size control, incl. `aria-label`s and every test query that matches them |
| 3.3 | Bubble-opacity helper: desktop short line vs web's longer Ambient-scene line | **desktop short line** as the shared core; the browser autoplay nuance stays web-only under §4 | web `BubbleOpacitySettings.tsx:127` core sentence reworded to match desktop |
| 3.4 | Slider value format: desktop `0.70` vs web `0.7` | **fixed two decimals** (desktop) — column alignment while dragging | web slider readouts in `GenerationSettingsFields.tsx` |
| 3.5 | Stop sequences: desktop shows raw `\nUser:` vs web stripped `User:` | **raw escapes** (desktop) — shows the bytes actually sent to the sampler | web `OutputPipelineEditors.tsx` render |
| 3.6 | Preset empty state: desktop "No saved presets yet"/"Load a preset..." vs web "No presets saved yet"/"Choose a preset…" | **desktop wording** — the ruling overrides "reads better"; desktop shipped on the host everyone shares | web `genPresets/GenPresetBar.tsx:92` + `GenPresetBar.test.tsx` assertions |

## 4. Platform-nuance rule (new, documented so it stops being drift-by-argument)

Copy that describes genuinely different platform behaviour may differ
**only** in the sentence naming that behaviour, and must contain the shared
core sentence byte-for-byte. Approves: web's scene-sound autoplay note (718
item 10) and web's ambient 25%-override clause (3.3). Anything else that
differs is a bug, not a nuance.

## 5. Structure

- **Dead barrel (716):** delete `lib/ui/settings/tabs/general_tab/general_tab.dart`
  (23 lines, zero importers — `grep -rn "tabs/general_tab/general_tab.dart" lib test`
  is empty). Two files named `general_tab.dart` a path apart, where one
  exports nothing anybody uses, is how a scratch harness ends up importing
  the wrong one and finding no `GeneralTab`.
- **Thinking helper (719):** `thinking_strength_control.dart:141` renders a
  helper line desktop-only; web `Thinking` shows four chips bare. Port the
  line to web verbatim.

## 6. Golden coverage so this class of drift fails CI, not a human

Today nothing renders General / Appearance / Generation as a whole on
desktop; pixel drift inside a tab cannot fail CI, which is exactly how 2.1
happened.

- Add `test/golden/widget/settings_tabs_golden_test.dart` following the
  `group_sidebar_parity` pattern: three tabs × light+dark, Porch palette.
- Baselines: push the branch with `[update-goldens]` in the head-commit
  message — `update-goldens.yml` regenerates on the exact runner image and
  uploads changed PNGs as an artifact; download, drop in, commit. Never
  regenerate on the Mac ("a bold theory of pixel rendering" — the antialiasing
  differs and CI is right, you are wrong).
- Labels on this PR: `approved-test-change` (edits existing baselines) —
  applied via `gh` at PR open.

## 7. Explicitly NOT drift — do not "fix"

Capability gating makes the surfaces look different at first glance; both
sides gate on the same host-supplied list:

- DRY / XTC / Dynamic Temperature / Banned phrases visibility: web
  `shown('dry')` ≡ desktop `knobs.contains(SamplerKnob.dry)`.
- Context-size ceilings: web `isLocal ? 131072 : 500000` ≡ desktop
  `isRemote ? 500000 : 131072`.
- Whole-preset-card suppression when `genPresetsOf()` is null.

Pre-existing (older than these PRs, out of scope): spell-check helper
wording, theme-card taglines absent on web, `Save settings` button
asymmetry, preset empty-state copy on Rawhide.

## 8. Out of scope for this pass — shape changes the ruling pre-approves

The 2026-11-17 ruling ("mirror the Dart app") pre-decides both questions;
they stay out of this fix PR only because a control-model change and an
autosave audit are a second PR's surface, and a fix pass that also redesigns
stops being reviewable in one sitting.

- **Appearance mode control shape** — desktop ships one 3-way `MODE`
  segment; web ships a `Dark mode` switch + 4-chip device row. Mirror target:
  the desktop segment becomes the control on web; the device-local override
  keeps working underneath it but stops being a separate control model.
- **Web `Save settings` vs desktop auto-save** — mirror target: auto-save on
  change, as the desktop does and as web's own `input.switch` "Dark mode"
  row already does. Needs a dirty-state audit of the remaining web forms
  (there is an `unsaved-edits.spec.ts` that lives off the Save flow) before
  it can be scoped honestly.

## 9. Verification and gates

| Gate | How | Where |
|---|---|---|
| Dart analyze | `flutter analyze` on every changed file + `lib/ui/settings` | local |
| Hygiene ratchets | `flutter test test/hygiene/` (incl. `one_ui_parity_test`, `settings_parity_manifest_test`) | local + CI |
| Settings suites | `flutter test test/ui/settings test/services/web/` | local + CI |
| Web unit + lint + build | `npm run lint && npm test && npm run build` in `web_ui/` | local + CI |
| E2E regressions | `-g "a setting survives a reload|theme follows the desktop|switches Realism and Needs"` against a held sandbox app (`FPAI_E2E_HOLD=1` recipe in findings doc) | local, then full sweep on CI |
| Pixels | full golden suite on ubuntu-latest | CI only — this Mac cannot certify Linux pixel bytes |
| Screenshots | re-run the render harness + `shots.mjs` after fixes: 3 tabs × 1440/400 × light/dark × Porch/Midnight; both grids in the PR body `## Screenshots` | local |
| Hostile review | `reviewer` PASS on the exact tree before push | gate |

Known-unexplained: `journeys.spec.ts:2537` (`page.goto: Target page,
context or browser has been closed`, reproduces standalone). If the
toggle/select fixes don't clear it, trace inspection is the next step and
it is a blocker for this PR's "green" — not deferred.

## 10. Order of execution

1. Branch from fresh `origin/Rawhide` (after 716-719 merge).
2. Blockers §2.3, §2.4 first (red + real), then §5, then §3 rows, then §6
   golden test + baseline artifact flow.
3. Local gate battery (§9), reviewer PASS, push, PR with `approved-test-change`.
4. CI loop: watch goldens + Playwright; `journeys:2537` diagnosis if still red.
5. Merge when green.
