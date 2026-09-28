# Statement of work — replace Image Studio

Status: locked. Date: 2026-09-27.
Branch: `Rawhide`.
One pull request: `feat(image): replace Image Studio`.

This file is the review contract. It supersedes the staged ten-PR plan in the working design draft. A reviewer checks the tree against the lists below. Do not invent a second studio, a feature flag that ships the old panels, or a follow-up PR for CivitAI, GGUF, or graph upload. Those are in this change.

A review against Rawhide on 2026-09-27 found places where an earlier draft of this file could not compile. Those corrections are in the lists below. Where a file is both “kept” and “edited,” the edit is a swap that must not grow the file past 499 lines.

The clickable preview at `docs/design/image-studio-desk-preview.html` shows the desk. It is not product code. Do not import it.

## What the user gets

A person chatting opens Image Studio and makes or changes a portrait. They pick Create or Edit, then one model they can search for. The app chooses a graph whose nodes exist on that ComfyUI and can open that file. Text encoder and VAE follow the graph. LoRAs are judged against the file that will run. Steps, CFG, sampler, and scheduler stay behind Advanced, and each backend keeps its own names. Width and height are editable. ComfyUI, Draw Things, Automatic1111, and remote providers all still generate. The same desk exists on the phone web page.

They can sign in to CivitAI once. That login downloads both models and LoRAs into the picture program’s folders. Adult results use the same login against civitai.red.

## Locked decisions

1. One pull request. The merge result has the new desk as the only desk. Old panels are deleted in that pull request. Rollback is `git revert`.
2. Create or Edit, then one primary file. The family dropdown is gone. Search groups files by family. Quants and GGUF sit under the family. Pony and Illustrious sit under SDXL in the list. Their LoRA badges stay Pony and SDXL.
3. The workflow is chosen for that file. A `.gguf` file never goes through `UNETLoader` or `CheckpointLoaderSimple`. A safetensors file never goes through a GGUF unet loader. A graph whose node classes are not installed is not a candidate. Z-Image stays one text encoder. Flux stays two. The family starter is copied and its loader classes are rewritten to GGUF classes this ComfyUI actually has, including a clip loader discovered from `/object_info` by `clip_name1`…`clip_nameN`.
4. LoRA family is the primary file of this run. The text encoder being Qwen does not make a Z-Image diffusion file a Qwen checkpoint. `image_gen_model` is not the Comfy checkpoint.
5. ComfyUI, Draw Things gRPC, Automatic1111, and remote stay, behind one driver. Draw Things stays on gRPC port 7859. The app does not start ComfyUI.
6. Expression packs stay on the Studio desk and in the avatar creator. The character page only shows emotions already imported.
7. Custom size: width and height, plus the five presets. Local backends snap each side to the nearest multiple of 64, clamped to 256–2048. Remote hosts keep their own allowed sizes.
8. Graph search is its own sheet. Upload accepts Comfy API JSON, Comfy Save JSON, and a PNG with a `prompt` or `workflow` text chunk. A malformed file is refused and not stored. A missing custom node blocks Generate and names the class. Studio does not install custom nodes. An uploaded graph is not retargeted.
9. CivitAI credentials are per Front Porch account, never one key for the whole install. The secure-storage key is `civitai_credential_<accountId>`, where `accountId` is what `SessionStore.validate` returns (`local` today). Account A cannot download with account B’s key. The phone relay uses the cookie’s account and no other. There is no CivitAI client secret and no API key in the repo. A pasted personal API key is the path that works with no registered app. Browser approval, if a client id is configured later, still stores that person’s token under their account id. Scope stays `UserRead | ModelsRead` (decimal 5) and does not include Buzz. PG search needs no login. A download uses that account’s credential. Adult search uses civitai.red with that same credential. A 403 on a locked file is reported and not bypassed.
10. Model downloads and LoRA downloads share that login. The destination folder comes from the sheet plus CivitAI’s file type. See the folder table. Nothing is written into the Kobold models directory or into Draw Things’ sandbox.
11. Connected is not Ready. A rejection names the URL, node id, node class, and Comfy’s detail.
12. Web and desktop ship together. Phone stacks the same blocks. No personal names in user-facing copy or `docs/Rawhide.md`.
13. Handwritten Dart under `lib/` stays under 500 lines. `comfy_workflow_convert.dart` is 499 lines and is not edited. `edit_view.dart` is 499 lines. It is edited only to swap the two widgets it currently builds, and the file must end at or under 499 lines. New logic goes in new files.

## Out of scope

- Chat, prompt-builder distillation, Realism, Needs, Journal, Growth, Pockets, RAG.
- ControlNet, inpaint, outpaint, a queue of generations.
- Starting or killing ComfyUI or Automatic1111.
- Spending CivitAI Buzz, or a CivitAI password field.
- Writing files into Draw Things.
- Merging closed PR 310.
- A Drift migration.
- Installing Comfy custom nodes.

## Behavior a reviewer can test

### Desk

Wide: picture and prompt on the left, stove on the right. Narrow and the phone Models page: one column, Generate stuck to the bottom.

Stove order: connection, model, workflow, support files, LoRA, size, Advanced, Generate.

Connection prints the URL it probed. If 8188, 8189, and 8190 were checked and none answered, it says that. If another ComfyUI answered, it names that URL and Generate keeps using the saved one until the user presses Use this port.

Ready requires every node class installed, every required file filled, no leftover token, and no certain LoRA mismatch. Generate is disabled otherwise.

### Model and graph

Change model searches installed files. Families with nothing on disk are omitted. Change graph searches text-to-image graphs in Create and instruction-edit graphs in Edit. An Image Edit graph does not appear as a Create row. Saved Comfy workflows come from `GET /userdata?dir=workflows` and are classified from the adapted graph, not from a title stamp.

Picking a model clears a custom graph and runs the resolver. Picking a graph or dropping a file sets that graph and skips ranking.

Drop or choose a file:

- Not JSON and not a PNG with `prompt` or `workflow` text: refused. “That file isn’t a ComfyUI graph.” or “That image has no ComfyUI workflow saved inside it.”
- Parses, then a class is absent from `/object_info`: stored, not Ready, class named.
- `/object_info` cannot be read: unreachable, not a guess that the class is missing.
- No text-encode node after adapt: `noWorkflow`.
- UI-format conversion is called with the live `/object_info` so installed nodes get real widget names.

### GGUF

A `.gguf` primary file ranks only graphs that can load it, then retargets the family starter onto `UnetLoaderGGUF`, else `UnetLoaderGGUFAdvanced`, else any installed class whose name contains `GGUF` and whose inputs include `unet_name`. Clip loaders follow the file extension and the count: one, two (`DualCLIPLoader` / `DualCLIPLoaderGGUF`), three, or four. A later GGUF class is discovered from input names in a new file. If no GGUF unet class is installed, Generate stays off: “This ComfyUI can’t run a GGUF model. Install the GGUF nodes in ComfyUI, or pick the regular weights.”

### LoRA

Up to eight slots, four on screen. Main list: match, Pony/SDXL soft pair, unknown, name-only likely. Other bases: certain mismatch only. Certain blocks Generate until Use anyway. Use anyway clears when the family changes. The banner names the primary filename.

### Size and sampler

Presets: `512x512`, `768x768`, `1024x1024`, `1536x1024`, `1024x1536`. Typed width and height snap as above on Comfy, Draw Things, and Automatic1111. A size set on the desk is not swapped by the portrait flag.

Comfy and Automatic1111: two dropdowns, names from that server, stored as `samplerName` and `scheduler`. Draw Things: one dropdown of the existing integer labels (`Euler a Trailing` is 10, `DDIM Trailing` is 16, `UniPC Trailing` is 17). No translation table. Knobs are stored per mode, family, and backend.

### CivitAI

The download credential is the signed-in person’s own CivitAI API key, pasted once and stored under their Front Porch account id. Sign out deletes that account’s entry only. Another account on the same Mac still has its own. The phone asks the desktop relay. The relay loads the credential for the cookie’s account and does not log it. Browser OAuth is not required for this pull request. If it is added later, the loopback listener and `url_launcher` stay as already specified, and the resulting token is still stored per account id, not as an app-wide secret. Re-check CivitAI’s download docs on the day that code is written. The user-visible rule does not move: no password field, no Buzz scope, adult search only while that account has a credential.

A downloaded name is the file’s basename only. Reject empty names, names that contain `/`, `\`, or `..`, and names that are absolute. The write path is `join(chosenRoot, slotFolder, basename)`. After the join, the path must still start with the models root the user chose. No other directory is writable from the phone relay.

Get a model from CivitAI and Get a LoRA from CivitAI are both on the stove. Same session.

| Download | Comfy folder | Automatic1111 folder |
|---|---|---|
| Checkpoint | `checkpoints` | `models/Stable-diffusion` |
| GGUF diffusion | `diffusion_models` | not offered |
| LoRA | `loras` | `models/Lora` |
| Text encoder | `text_encoders` | not this slot |
| VAE | `vae` | `models/VAE` |

The sheet and CivitAI’s type must agree. A LoRA is not written into a diffusion folder. The first download asks for that program’s models root and remembers it. `DownloadManager` is reused with `targetDir` set to that folder, not `StorageService.modelsDir`. After the file appears in the loader list, a matching-family model becomes the primary file and a GGUF file runs the GGUF retarget. A LoRA is added and judged against the current primary file.

### Expression packs and avatar

Pack setup is on the desk. The avatar create strip shows the Create model and opens the Create sheet. The avatar edit row shows the pack route: Edit if that section is Ready, otherwise Create img2img, otherwise disabled. Portrait generation still uses Create. `startExpressionPack` does not exist today. Add it on `ImageGenService` in `image_gen_service.studio.dart`. It holds the single-flight lock and calls the driver. It does not call `generateImage` per emotion. The phone can read and cancel a desktop-started pack when `SessionStore.validate` returns the same local web account id (`local` today). A different account gets 404. Pack status returns filenames and QC verdicts, not image bytes.

### Errors

`_runWorkflow` today keeps only `error.message`. The replacement parses `error.details` and `node_errors`, and history `status.messages` as `["execution_error", { node_id, node_type, exception_message }]`. The banner shows URL, node id, class, and detail, capped at 240 characters.

## Files to create

Dart services:

- `lib/services/image/studio_recipe.dart`
- `lib/services/image/studio_recipe_migrate.dart`
- `lib/services/image/studio_catalog.dart`
- `lib/services/image/studio_workflow_resolve.dart`
- `lib/services/image/comfy_gguf_loaders.dart`
- `lib/services/image/image_driver.dart`
- `lib/services/image/comfy_image_driver.dart`
- `lib/services/image/drawthings_image_driver.dart`
- `lib/services/image/a1111_image_driver.dart`
- `lib/services/image/remote_image_driver.dart`
- `lib/services/image/studio_job.dart`
- `lib/services/image/image_submit_error.dart`
- `lib/services/image/expression_pack_route.dart`
- `lib/services/image/civitai_client.dart`
- `lib/services/image/civitai_oauth.dart`
- `lib/services/image/civitai_download.dart`
- `lib/services/image/draw_things_samplers.dart`
- `lib/services/image_gen_service.studio.dart` (part of `image_gen_service.dart`)
- `lib/services/web/facade/image_facade_studio.dart`

Dart UI:

- `lib/ui/image_studio/studio_desk.dart`
- `lib/ui/image_studio/studio_stove.dart`
- `lib/ui/image_studio/studio_connection_card.dart`
- `lib/ui/image_studio/model_search_sheet.dart`
- `lib/ui/image_studio/graph_search_sheet.dart`
- `lib/ui/image_studio/lora_search_sheet.dart`
- `lib/ui/image_studio/studio_advanced.dart`
- `lib/ui/image_studio/studio_size_fields.dart`
- `lib/ui/image_studio/civitai_sheet.dart`
- `lib/ui/image_studio/expression_pack_setup_v2.dart` — this file declares `class ExpressionPackSetup`, the same public name the dialog already builds
- `lib/ui/image_studio/studio_edit_pane.dart` — the Edit-mode stove and graph controls that `edit_view.dart` currently builds inline
- `lib/ui/avatar_creation/avatar_studio_line.dart`

Web:

- `web_ui/src/components/models/StudioDesk.tsx`
- `web_ui/src/components/models/ModelSearch.tsx`
- `web_ui/src/components/models/GraphSearch.tsx`
- `web_ui/src/components/models/LoraSearch.tsx`
- `web_ui/src/components/models/StudioConnection.tsx`
- `web_ui/src/components/models/CivitaiSearch.tsx`
- `web_ui/src/components/models/PackGrid.tsx`
- Matching `*.test.ts` or `*.test.tsx` files beside those components.

Tests, all new files:

- `test/services/image/studio_recipe_migrate_test.dart`
- `test/services/image/studio_template_mode_test.dart`
- `test/services/image/studio_workflow_resolve_test.dart`
- `test/services/image/studio_job_dispatch_test.dart`
- `test/services/image/lora_primary_file_test.dart`
- `test/services/image/lora_buckets_test.dart`
- `test/services/image/image_submit_error_test.dart`
- `test/services/image/civitai_client_test.dart`
- `test/services/web/image_studio_step_up_test.dart`
- `test/ui/image_studio/studio_desk_test.dart`
- `integration_test/image_studio_desk_test.dart` — one journey: open Studio, switch Create and Edit, open model search, confirm Generate stays off when a required file is empty. One file per `flutter test` invocation.

`civitai_client_test.dart` parses fixture strings passed into pure functions. It does not bind a server, and it does not feed canned HTTP responses through `civitai_client.dart`. A live test is a separate file, tagged `live`, and skips when `CIVITAI_TOKEN` is absent. CI has no token, so that skip is the expected CI result. No toy HTTP server that invents JSON.

Export new service files from `lib/services/image/image.dart`.

## Files to edit

Only these, and only for the reason given. Re-count before adding a line. If an edit would reach 500 lines, move the new code into one of the new files instead.

| File | Why |
|---|---|
| `lib/services/image/image.dart` | Export the new libraries. |
| `lib/services/image_gen_service.dart` | Add the `studio` part. Keep `generateImage` as a one-line forwarder on the class. |
| `lib/services/image_gen_service.generate.dart` | One call into the studio part. File is 407 lines. Stop if the edit would reach 500. |
| `lib/services/comfy_ui_service.dart` | Call the new error parser from `_runWorkflow`. File is 472 lines. If the call does not fit under 499, add part `comfy_ui_service.errors.dart` and move the throw there. |
| `lib/services/comfy_ui_service.catalog.dart` | Union GGUF unet and clip loaders into the catalog. Re-count first. |
| `lib/services/image/comfy_workflow_adapt.dart` | Call `comfy_gguf_loaders.dart` for unknown GGUF classes. File is 318 lines. Do not add a new switch arm per class. |
| `lib/ui/image_studio/image_studio.dart` | Build `StudioDesk` instead of the old shell. File is 469 lines. If the swap does not fit, the swap is a one-line widget in a new file. |
| `lib/ui/image_studio/edit_view.dart` | 499 lines. It imports `comfy_edit_panel.dart` and `settings_panel.dart` and builds both (around lines 267 and 279). Replace those two constructions with `StudioEditPane`. Remove the two imports. Add one import. The file must finish at or under 499 lines. Do not add features here. |
| `lib/ui/image_studio/expression_pack_dialog.dart` | 473 lines. It imports `expression_pack_setup.dart` and builds `ExpressionPackSetup` (around line 409). Change that import to `expression_pack_setup_v2.dart`. The class name stays `ExpressionPackSetup`. Do not add lines. |
| `lib/ui/image_studio/studio_view.dart` | It imports `settings_panel.dart`. Point the body at `StudioDesk`, or delete this file if nothing else constructs `StudioView`. |
| `lib/ui/avatar_creation/engine_strip.dart` | 267 lines. Replace `ComfyCreatePanel()` with `AvatarStudioLine`. Remove the `model_slot_dropdown.dart` import and every use of that widget. It also opens `ImageGenSettingsDialog` (around line 82). That class stays; see the dialog row. |
| `lib/ui/avatar_creation/expressions_section.dart` | 347 lines. Same replacement: `ComfyCreatePanel` and `model_slot_dropdown.dart`. |
| `lib/ui/avatar_creation/portrait_section.dart` | 423 lines. It opens `ImageGenSettingsDialog` at about line 196. Leave the call. The dialog’s body changes, not this call site, unless the constructor changes. |
| `lib/ui/dialogs/image_gen_settings_dialog.dart` | 82 lines. Keep the class. Its body stops embedding `GenerationOptionsTab` and shows the new stove. Callers are `portrait_section.dart`, `engine_strip.dart`, and the golden test. |
| `lib/services/image/edit_profile.dart` | 54 lines. Update the comment that points at `_drawThingsSamplers` so it points at `draw_things_samplers.dart`. |
| `lib/services/web/facade/image_facade.dart` | One-line forwarders only if the file stays ≤ 499 (it is 444). Otherwise register `ImageStudioFacade` from `backend_routes.dart` and do not edit this file. |
| `lib/services/web/` route registration (`backend_routes.dart` or the image route file) | Register studio catalog, CivitAI search, CivitAI download, OAuth start, pack status. Re-count. Extract a part before 500. |
| `lib/services/storage/settings/image_gen_settings.dart` and its load part | Read the new recipe key. Do not grow the legacy setters. Migration lives in `studio_recipe_migrate.dart`. |
| `web_ui/src/components/models/ImageGen.tsx` | Render `StudioDesk` instead of `ComfyCreateFields` / `ComfyEditFields`. |
| `docs/design/comfy-templates.md` | Point at the resolver. Remove the four-bucket dropdown as the product. |
| `docs/image-studio.md` | User-facing desk, sign-in, folders. No personal names. |
| `docs/user-guide.md` | Same. |
| `docs/faq.md` | Connection, GGUF, CivitAI sign-in, adult switch. |
| `docs/web-phone.md` | Remove “full Image Studio is desktop-only.” |
| `README.md` | Same sentence, if present. |
| `docs/Rawhide.md` | One short bullet. No personal names. No commit log. |

After any `web_ui/` change, rebuild `assets/web_app` with `npm run build` in `web_ui/`.

`flutter_secure_storage` is already in `pubspec.yaml`. Do not add a dependency. Do not bump the version in `pubspec.yaml`.

## Files to delete

Delete only after the new desk builds and the grep for the old symbol is empty.

| File | Reason |
|---|---|
| `lib/ui/image_studio/comfy_create_panel.dart` | Family dropdown and JSON-only upload. |
| `lib/ui/image_studio/comfy_edit_panel.dart` | Old edit graph picker. |
| `lib/ui/image_studio/comfy_edit_panel.readiness.dart` | Part of that panel. |
| `lib/ui/image_studio/comfy_edit_catalog.dart` | Old edit list. Delete only if no remaining caller. |
| `lib/ui/image_studio/generation_options_tab.dart` | Old settings stack. |
| `lib/ui/image_studio/generation_options_tab.advanced.dart` | Part of that tab. Move `_drawThingsSamplers` out first. |
| `lib/ui/image_studio/generation_options_tab.local_panel.dart` | Passes `imageGenModel` into the LoRA board. |
| `lib/ui/image_studio/generation_options_tab.shared_fields.dart` | Part of that tab. |
| `lib/ui/image_studio/generation_options_tab.source.dart` | Part of that tab. |
| `lib/ui/image_studio/lora_picker.dart` | Old mismatch banner. |
| `lib/ui/image_studio/lora_slot_board.dart` | Old slot dropdown. |
| `lib/ui/image_studio/model_slot_dropdown.dart` | Old model dropdown. |
| `lib/ui/image_studio/settings_panel.dart` | Wraps `GenerationOptionsTab`. |
| `lib/ui/image_studio/expression_pack_setup.dart` | Embeds `ComfyCreatePanel`. Deleted only after `expression_pack_dialog.dart` imports the v2 file and `rg ExpressionPackSetup` no longer names this path. |
| `web_ui/src/components/models/ComfyCreateFields.tsx` | Old web create form. |
| `web_ui/src/components/models/ComfyEditFields.tsx` | Old web edit form. |

Keep, and call from the new desk:

- `prompt_workspace.dart`, `style_preview.dart`, `subject_picker.dart`, `studio_mode_tabs.dart`, `studio_prompt_craft.dart`
- `reference_image_picker.dart`, `edit_source_well.dart` (the call moves into `studio_edit_pane.dart`; `edit_view.dart` only swaps which child it builds)
- `image_gen_settings_dialog.dart` (class stays; body is replaced)
- `result_view.dart`, `generation_history.dart`, `generation_panel.dart`
- `expression_pack_dialog.dart` (473 lines; import path only), `expression_pack_grid.dart`, `expression_pack_qc_ui.dart`, `expression_pack_prompt_editor.dart`, `expression_pack_dialog.base.dart`
- `remote_image_host_chips.dart`, `vision_gate.dart`, `mode_info_card.dart`, `studio_helpers.dart`, `backend_catalog.dart`
- `image_studio.subject.dart`

`studio_view.dart` is deleted if `StudioDesk` replaces it and no test or route still names `StudioView`. Otherwise it becomes a one-line call to `StudioDesk`.

Service files that stay, unmodified unless the edit table says otherwise:

- `comfy_workflow_convert.dart` (do not edit)
- `comfy_subgraph_widgets.dart`
- `comfy_starters.dart` (read by the resolver; do not rewrite the JSON by hand)
- `comfy_create_presets.dart`, `comfy_edit_presets.dart` (resolver may still read tokens and starter ids; do not delete until `rg` shows no callers)
- `comfy_create_workflow.dart`, `comfy_edit_workflow.dart`
- `model_family.dart`, `image_job.dart`, `edit_profile.dart`, `image_gen_lora_slots.dart`
- `image_studio_remote.dart`, `image_surface.dart`, `nano_catalog.dart`, `comfy_catalog.dart`, `comfy_template_index.dart`

`planImageJob` stays as a wrapper if any caller remains. Do not change a test that calls it unless that test is in the edit list and the pull request carries `approved-test-change`.

## Do not edit

- `lib/services/image/comfy_workflow_convert.dart`
- `lib/ui/avatar_creation/avatar_creation_run.dart` (it already calls `generateImage` with no model)
- `pubspec.yaml` except that no version bump and no new dependency are allowed. `url_launcher` and `flutter_secure_storage` are already there. Do not add `app_links` or another deep-link package.
- `analysis_options.yaml`
- `lib/database/database.dart` and migration parts
- `lib/main.dart`
- Existing tests, except the ones named in the test section, and only with `approved-test-change`

`edit_view.dart` and `expression_pack_dialog.dart` are edited only as the edit table says. They are not free surfaces.

## Data

New prefs key: `image_studio_recipe` (prefixed `beta_` on nightly, via the existing settings prefix). One JSON blob: Create section, Edit section, backend, size, LoRA slots, knob map keyed by mode + family + backend, CivitAI models-root paths, support-file choices.

Legacy keys are read once by `migrateImageStudioRecipe`. The migration must not delete them, clear them, or write them back. `git revert` of this pull request then still finds the old desk’s settings. The new key is additive.

- `image_gen_model` is the Comfy primary file only when the old workflow id is `sd`. A Z-Image workflow must not inherit a leftover Qwen name from that slot.
- `comfy_create_workflow_id`, `comfy_create_model_choices`, `comfy_create_uploaded_workflow`
- `comfy_edit_workflow_id`, `comfy_edit_model_choices`, `comfy_edit_uploaded_workflow`
- `image_gen_loras` and the edit twin
- `image_gen_size`, steps, cfg, sampler, scheduler, Draw Things sampler int

`customWorkflow` is true only for an uploaded file (`__uploaded__`). A live `comfy:default:` or `comfy:userdata:` id is not custom.

Support-file copy, per section, never across Create and Edit:

1. The new workflow id, if that slot already has a file.
2. Else the previous workflow id.
3. Else the legacy workflow id, only while previous is empty.

Then set previous to the stem just chosen. A text encoder changed under `image_z_image_turbo` survives the next stem. Edit’s CLIP does not land on Create.

Uploaded workflow JSON over 512 KiB is a file under app support: `image_studio/custom_create.json` and `custom_edit.json`.

The CivitAI credential is not in that blob. It is in secure storage under `civitai_credential_<accountId>`.

## Tests that must change

These assert the old surface. They change in this same pull request. That needs the `approved-test-change` label. The rationale is: the dropdown desk is gone.

- `test/ui/image_studio/generation_options_tab_test.dart` — retarget at `StudioDesk`, or delete if the widget is gone.
- `test/ui/image_studio/remote_image_host_chips_test.dart` — it imports `settings_panel.dart`. Retarget the import at the widget that still hosts the chips.
- `test/golden/widget/dialogs_remaining_golden_test.dart` — it snapshots `ImageGenSettingsDialog`. The dialog body changes, so this golden changes. Update it only inside the Linux golden image (`./scripts/ci-local.sh update-goldens`). macOS `flutter test` does not run goldens. The label is still required.
- `test/services/image/comfy_create_presets_test.dart` — keep token and starter pins that are still true. Remove assertions that the four preset ids are the catalog.
- `test/services/image/comfy_one_path_test.dart` — stop requiring `ComfyCreateFields.tsx` as the web create form.
- `test/services/storage_service_test.dart` — the `image_gen_size` pin stays true. Migration reads that key and does not clear it. Do not weaken this assertion.

Do not edit:

- `test/services/image/comfy_workflow_convert_test.dart`
- `test/services/image/gguf_loader_suite_test.dart`
- `test/services/image/gguf_review_regression_test.dart`
- `test/services/image/gguf_uploaded_prompt_test.dart`
- `test/services/image/gguf_workflow_compat_test.dart`
- `test/services/image/comfy_saved_gguf_edit_test.dart`
- `test/services/comfy_ui_service_test.dart`
- `test/services/image/model_family_test.dart`
- `test/services/image/lora_base_filter_test.dart`
- `test/services/image/lora_slots_test.dart`

New guards, each proved red then green:

- Migration of a Z-Image workflow does not read `image_gen_model` when that string is a Qwen filename.
- A template title containing both “Text to Image” and “Image Edit” is absent from Create.
- A `.gguf` primary file is not submitted with `class_type` `UNETLoader`.
- Support-file copy does not take Edit’s `%MODEL_CLIP%` onto Create, and a changed Create encoder survives the next stem.
- Error JSON with node id 28 yields that id, the class, and the detail.
- LoRA family for primary `z_image_turbo_bf16.safetensors` plus support `qwen_3_4b.safetensors` is Z-Image.
- CivitAI model type `LORA` is not assigned the diffusion folder. Type `Checkpoint` is not assigned `loras`.

## Acceptance

- `flutter analyze` is clean on every Dart file this change touches.
- New Dart files are under 500 lines. `comfy_workflow_convert.dart` has no diff.
- `flutter test` on the new test files and the labeled updated tests passes.
- `web_ui` lint and tests pass, and `assets/web_app` is rebuilt.
- Desktop and phone both show Create, Edit, model search, graph search, graph upload, LoRA search, size fields, CivitAI sign-in, Get a model, Get a LoRA, and the adult switch.
- A Z-Image diffusion file with text encoder `qwen_3_4b.safetensors` and LoRA `z-image-turbo-realism` does not show a Qwen checkpoint warning.
- A GGUF Z-Image file does not submit `UNETLoader`.
- A PNG without a workflow chunk is refused.
- A graph whose class is missing does not enable Generate.
- CivitAI sign-out removes only that account’s credential. A second account’s key is still there. Adult rows do not appear for an account with no credential.
- A downloaded LoRA is in the `loras` folder. A downloaded checkpoint is not.
- A CivitAI name of `../../x.safetensors` is refused, and the models root is unchanged.
- After `git revert`, the old settings keys are still present.
- `integration_test/image_studio_desk_test.dart` passes on its own, one file per invocation.
- The Draw Things sampler table lives in `draw_things_samplers.dart`, including `Euler a Trailing` = 10, `DDIM Trailing` = 16, and `UniPC Trailing` = 17, and `generation_options_tab.advanced.dart` is gone.

## Reviewer notes

The working draft at the temp design path still mentions a flag and PR 9 / PR 10. Ignore that split. This statement of work is the one the maintainer locked: one pull request, old panels deleted, CivitAI sign-in included, models and LoRAs both downloaded.

A second review found compile breaks in an earlier copy of this file. Those are closed here: `edit_view.dart` and `expression_pack_dialog.dart` get surgical edits, `ImageGenSettingsDialog` stays, the Draw Things sampler table moves before its old file is deleted, legacy keys are not cleared, CivitAI writes cannot escape the chosen models root, and one integration journey is required.
