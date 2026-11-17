# PR 716-719 merged-branch findings

Validation branch: `validation/pr-716-719-merge` (all four of Pacmanincarnate's
settings-redesign PRs merged onto `Rawhide`). This is the punch list for the
fix PR that lands after they merge — nothing here is fixed in those four
branches.

Merged scope: 84 files, +7680 / -1902. One conflict, in
`web_ui/src/styles/settings.css` (717's prompt-slot block vs 719's generation
block, both additive); resolved by keeping both, then dropping a duplicated
`.settings-save button.primary` rule the resolution left behind.

## What is green on the merged tree

- `flutter analyze` on every changed Dart file and on `lib/ui/settings`,
  `lib/ui/widgets`, `lib/services/web`: clean.
- `flutter test test/hygiene/` (includes `one_ui_parity_test` and
  `settings_parity_manifest_test`): 92 passed.
- `flutter test test/ui/settings test/services/web/settings_display_output_test.dart`:
  219 passed.
- `flutter test --exclude-tags golden`: 11,688 passed. The 3 failures are
  `test/services/image/comfy_city96_harden_test.dart` OS process probes —
  `ps` is blocked in this sandbox (`Shell: ps could not start: Operation not
  permitted`), unrelated to these PRs.
- `npm run lint` and `npm test` in `web_ui/`: clean, 1,723 passed / 3 skipped.
- `npm run build`: clean.
- CI per PR: `analyze`, `test`, `e2e-smoke`, `web-tests`, `theme-lint`,
  `io-lint`, `pr-labels` all pass on all four.

## Blockers (CI is red because of these)

1. **716 — `StyledDropdown` goldens never regenerated.** 716 edits
   `lib/ui/widgets/styled_dropdown.dart` and ships no golden update
   (`git diff --name-only <base> origin/pr/716 | grep _goldens` is empty). CI
   `golden` fails: `_goldens/leaf_widgets/styled_dropdown.dark.png` 4.91% /
   1179 px and `.light.png` 4.91% / 1178 px.
2. **719 — `chat_settings` goldens regenerated on the wrong platform.** 719
   does update `_goldens/dialogs_more/chat_settings.{dark,light}.png`, but CI
   renders on Linux and still fails at 0.22% / 1040 px. Windows baselines do
   not survive the Linux image.
   → Both need one Linux regeneration: `./scripts/ci-local.sh update-goldens`,
   with `approved-test-change` and `update-goldens` applied by the maintainer.
3. **717 — the new toggle cards hide their accessible control.** In
   `web_ui/src/styles/settings.css` the `.toggle-switch input` is
   `opacity: 0; width: 0; height: 0`, and `FollowStreamingSettings.tsx` /
   `MessageSideSettings.tsx` put the `aria-label` on that 0×0 input. The
   painted control is the sibling `.toggle-slider` span. E2E consequence:
   `journeys.spec.ts:507` "a setting survives a reload" times out on
   `locator.setChecked` — `element is not visible` for the full 90 s
   (reproduced locally, desktop-chromium and phone-webkit). Human
   consequence: the same is true for assistive tech that targets the input.
   → Make the input the painted pill like the app's existing `input.switch`
   pattern, or give it the standard 1px clip box; keep the `aria-label`.

## One UI violations (same screen, two different surfaces)

4. **718 — the native device-theme select is deleted from the a11y tree.**
   New CSS `.sr-only-select { display: none; }` (`settings.css:210`, absent on
   `Rawhide`) removes `ThemeModeSettings.tsx`'s `<select
   aria-label="Theme on this device">` from layout *and* the accessibility
   tree. `journeys.spec.ts:1751` "the theme follows the desktop, and a device
   can keep its own mode" times out on `selectOption` — reproduced locally;
   the failure snapshot shows `checkbox "Dark mode"` present and no device
   control at all. → Use a visually-hidden clip, not `display: none`.
5. **716/717 — the Porch Life pointer says two different things.** Desktop
   `general_tab/porch_life_pointer_card.dart:50` says "…all live in the Porch
   Life **tab** now…"; the web says "…Porch Life **section** now…", and
   `SettingsPage.parity.test.tsx:307` asserts the web wording. Pick one and
   make the other match (the parity guard currently only pins the web half).
6. **718 — Appearance control shape differs.** Desktop has one 3-way `MODE`
   segment (Dark / Light / Match system). Web has a `Dark mode` switch *plus*
   a 4-chip `On this device` row (Follow the desktop / Dark / Light / Match
   this device). One setting, two control models. Pre-existing split that 718
   rewrote both sides of without converging.
7. **718 — theme gallery loses the card tagline on web.** Desktop paints the
   `AppThemeId` blurb on each card (Classic, Neutral, OLED, Warm, Cozy, Cool,
   AAA); `ThemeGallerySettings.tsx` shows the name only.
8. **718 — label case drift in Chat Appearance.** Desktop "Reading Size",
   "Bubble Opacity"; web "Reading size", "Bubble opacity".
9. **718 — Bubble opacity helper text differs.** Web adds the Ambient-scene
   sentence ("With the Ambient scene on they start at 25%, so the weather
   shows through. The desktop's setting; changing it here changes it there
   too."); 718's new desktop copy is the short "How solid the chat bubbles
   are; the text stays crisp."
10. **718 — scene-sound note is web-only.** "Browsers start sound only once
    you have touched the page, so a tap in the chat may be needed." appears in
    the web Atmosphere card and not on desktop.
11. **719 — Thinking helper line is desktop-only.**
    `thinking_strength_control.dart:141` renders "How hard the model thinks
    before replying. The chips match the levels this model actually accepts."
    The web `Thinking` section has the four chips and no line.
12. **719 — slider value formatting differs.** Desktop shows 0.70 / 0.10 /
    0.90; web shows 0.7 / 0.1 / 0.9 for the same stored values.
13. **719 — stop-sequence rows display the same value two ways.** Desktop
    shows the raw escape (`\nUser:`, `\n###`); web shows the stripped text
    (`User:`, `###`). Same stored string, two renders.
14. **719 — preset empty-state copy differs.** Desktop
    `generation_preset_bar.dart:224`: "No saved presets yet" / "Load a
    preset…"; web `genPresets/GenPresetBar.tsx:92`: "No presets saved yet" /
    "Choose a preset…".
15. **Web has a `Save settings` button on Appearance and Generation; desktop
    auto-saves.** Pre-existing, but every One UI pass over these tabs reopens
    it — decide one behaviour and ship it.

## Structure and hygiene

16. **716 — dead duplicate barrel and a broken convention.** 716 adds
    `lib/ui/settings/tabs/general_tab/general_tab.dart` (23 lines: re-exports
    `about_license_card`, `app_system_section`, `chat_behavior_section`,
    `porch_life_pointer_card`, `prompts_section`). Nothing imports it —
    `grep -rn "tabs/general_tab/general_tab.dart" lib test` is empty — while
    the real widget lives in the *sibling file* `lib/ui/settings/tabs/general_tab.dart`,
    which imports its section files directly instead of the barrel. Two files
    named `general_tab.dart` a path apart, and CLAUDE.md's barrel rule
    inverted. This harness tripped on it: importing
    `tabs/general_tab/general_tab.dart` gets you no `GeneralTab`.
    → Delete the dead barrel or make it the only way in, and have the tab file
    import it.
17. **718 — PR body cites files that do not exist.** The body's line-count
    list names `chat_typography_section.dart` and its test run cites
    `web_ui/src/components/AppearanceSettings.test.tsx`; neither is in the
    diff or the tree. The work is fine, the evidence trail is not.
18. **716 — PR body says `general_tab.dart` is 56 lines.** It is 134 on the
    merged tree. Under the 500 cap, so no ratchet risk; just don't trust the
    number later.
19. **No golden or parity coverage for the settings tabs themselves.** The
    redesigns are guarded by section-level widget tests and the manifest, but
    nothing renders General / Appearance / Generation as a whole on desktop,
    so pixel drift inside a tab cannot fail CI. A `group_sidebar_parity`-style
    golden per tab, plus a web twin, is the durable fix.

## Not drift — do not "fix" these

Capability gating makes the two surfaces look different at first glance, and
both sides gate on the same rule:

- DRY, XTC, Dynamic Temperature and Banned phrases appeared only in the
  desktop render because the held app's backend was local and the web run's
  was not. Web gates with `shown('dry')` / `shown('bannedPhrases')`; desktop
  with `knobs.contains(SamplerKnob.dry)`. Same list from the same host.
- Context-size ceilings match: web `isLocal ? 131072 : 500000`, desktop
  `isRemote ? 500000 : 131072`.
- The desktop hides the whole Generation preset card when
  `genPresetsOf(storage)` returns null; the web does not show it for that
  backend either.

## Notes for the follow-up PR body

The author drove a model that is not strong at code. Blame the model, never
the author: they shipped desktop and web twins, tests, and screenshots on all
four PRs, which is more than most change requests carry. The snark aims at the
tool that wrote `display: none` on a labelled control, not at the person who
reviewed the screenshots and saw nothing wrong with them. No contributor
handle in the joke. Keep it dry and one line, not a bit.

Approved register, from the maintainer, is the dry technical jab that names the
bad idea rather than the person who trusted it — e.g. "`aria-label` went on the
input; the input got `width: 0`. That is the model rediscovering the
invisible-button-with-a-visible-span, a trick we already ship correctly three
files over as `input.switch`", and "the goldens were regenerated on Windows and
then asked to pass on Linux, which is a bold theory of pixel rendering."

## Not a defect

- 716's only Playwright failure (`journeys.spec.ts:552`, HTTP 500 on
  `/api/characters/<id>/avatar`) is a CI flake: it passes locally on both
  projects.
