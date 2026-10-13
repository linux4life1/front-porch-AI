# KoboldCpp preset chat template selection

The preset editor can select a local `.jinja` file or return to the template
embedded in the GGUF. The selection is saved as `jinjatemplate` in the preset;
Jinja while preserving tool-formatting settings are enabled for a selected custom template.
Other preset settings survive save, copy and clear.

The web Models page offers the same override for a selected host-owned preset.
Upload transfers the template text to a content-addressed folder on the desktop
host, retaining its filename. Clear removes the override from the preset.
The API accepts only ordinary non-staged `.kcpps` files in the engine folder,
rejects binary/empty/oversized uploads, and rechecks the selected preset before
writing. External presets remain editable through the desktop editor.

Both interfaces explain that saving changes the preset and a full KoboldCpp
stop/start is needed to activate a changed template. They do not claim an
in-place model reload has replaced the startup-loaded custom template.

This UI feature is independent of the reasoning/grammar crash workaround.
It has no profile migration, inference change, new dependency or version bump.

## Verification and poke

New tests exercise selection, save/copy/clear, exact uploaded contents,
preserving unrelated fields, rejecting outside/staged presets, upload limits
and an overtaken selection. The new save guard was deliberately disabled,
failed, and restored before the passing run. A desktop widget interaction
chooses and clears a synthetic path. A new real-app browser journey uploads,
reloads, verifies persistence and clears on Chromium and WebKit.

1. In an isolated profile, open the KoboldCpp preset editor and choose a
   synthetic `.jinja` file; save, reopen and copy the preset.
2. Select the preset on the web Models page, upload a template and reload;
   clear it and confirm the model/context settings are unchanged.
3. Stop/start the isolated backend and check its custom-template startup
   message; clear the override and repeat the stop/start.

The browser journey verifies UI/API persistence, not inference quality for
an arbitrary uploaded template. The desktop screenshot is a component
preview with synthetic data. No primary-profile data is used.

## Path-complete checklist

Turn-event and prompt matrices: N/A; this changes preset configuration and
file selection, not chat state, prompt builders, rewind or orchestration.
Desktop and web both expose the setting. Backend activation retains its
existing lifecycle and explicitly requires a restart for template changes.

## Review verification

Desktop imports copy the selected text into the same content-addressed engine-owned
directory as web uploads. The picked source can be deleted without breaking the
saved template. Native tool formatting is preserved, not forced by this feature.
The facade delegates to a real `ChatTemplateSettings` class, with no new parts.
The wide editor retains Extras as well as the template controls. All 51 targeted
Dart/editor/hygiene tests, web lint/build, 925 Vitest tests and the migrated
real-app template journey in Chromium and WebKit pass on current Rawhide.
