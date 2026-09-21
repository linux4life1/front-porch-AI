# ComfyUI templates — how Porch rides them

Image Studio Create does **not** own a Porch fork of each Comfy family
graph (SD / Flux / Qwen / Z-Image Turbo). It loads Comfy’s own workflow
JSON and fills Studio knobs with the same token/slot engine Edit BYO uses.

Edit (expression pack) stays Edit-first: `comfyEdit*` presets / instruction
edit. Pack falls back to Create img2img for non-edit models. No ControlNet.

## Where Comfy keeps templates

| Source | Typical location | How Porch finds it |
|--------|------------------|--------------------|
| Built-in frontend templates | Served at `{comfyUrl}/templates/index.json` and `{comfyUrl}/templates/{name}.json` (package `comfyui-workflow-templates`) | `fetchCreateTemplates` / `fetchTemplateJson` |
| Comfy Desktop “Save” | `ComfyUI/user/default/workflows/*.json` (UI format) | `GET /userdata?dir=workflows` then `/userdata/workflows/{file}` |
| Custom-node examples | `GET /api/workflow_templates` | Not listed in Studio (often ControlNet / extras) |
| Escape hatch | User file | Image Studio → **Upload your own…** (API format *or* Desktop Save) |

Point Porch at the **same URL** the Comfy Desktop UI uses
(`http://127.0.0.1:8188` by default). If that install serves the frontend,
the Z-Image Turbo / Qwen / Flux templates appear in the Create family list.

## What we fill

The adapter walks the API graph (converting UI/subgraph JSON first) and maps:

- prompt / negative → CLIP text widgets (`%PROMPT%`, `%NEGATIVE%`)
- seed / steps / CFG / sampler / scheduler / denoise → `KSampler` (Flux CFG
  rides `FluxGuidance`, KSampler cfg stays 1)
- width / height → `EmptyLatentImage` / `EmptySD3LatentImage`
- model files → the right drawer (`diffusion_models`, `text_encoders`, `vae`,
  `checkpoints`)

A workflow that already has `%TOKEN%` placeholders is filled as-is (BYO).

## Bundled starters

When `/templates/` is missing (headless API, old install), Porch uses the
replaceable stock API graphs in `lib/services/image/comfy_starters.dart`
(`image_z_image_turbo`, `image_qwen_image`, `flux_schnell`). **Do not**
rewrite those as Dart node builders. To pick up a new official Qwen/Flux/ZIT
shape:

1. In Comfy Desktop: open the new template → **Workflow → Export (API)**.
2. Replace the matching map in `comfy_starters.dart`, or upload the JSON
   as BYO.
3. Keep the family **id** (`z_image_turbo` / `qwen_image` / `flux`) so
   saved slot choices still apply.

SD / SDXL / Pony still use the existing `CheckpointLoaderSimple` builder.

## What we will not add

ControlNet, inpaint packs, pack-only Comfy graphs, or a permanent Porch
copy of every Comfy template.
