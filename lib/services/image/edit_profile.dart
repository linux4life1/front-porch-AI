// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The field-tested Draw Things edit recipe (Qwen-Image-Edit-2509/2511-i8).
//
// These are DEFAULTS, not overrides. The Edit tab keeps its OWN edit-scoped
// copy of the Generation Settings (steps / CFG / sampler / shift / seed-mode),
// separate from the Create/txt2img knobs, so tuning an edit never clobbers the
// user's txt2img sampler/CFG/steps — the two model families want very
// different values. On first use that edit-scoped copy is SEEDED from the
// constants below, and the "Use recommended edit settings" button writes them
// back. After that, every knob the user sees on the Edit tab is honored
// verbatim by ImageGenService — nothing here silently rewrites the request.
//
// Why these particular values: Qwen-Image-Edit returns a BLANK image ("no
// images") outside the UniPC sampler + a moderate CFG. A good txt2img combo
// (DDIM / high CFG) yields nothing on the edit model, which is exactly the
// footgun these seeds avoid on the first edit.

/// Draw Things sampler int for **UniPC Trailing** — the sampler the edit model
/// needs to produce an image at all (see `_drawThingsSamplers`: 17).
const int kEditRecommendedSamplerInt = 17;

/// Moderate guidance. High CFG makes the edit model produce no image.
const double kEditRecommendedCfg = 3.5;

/// Model-family shift. Backends without a shift knob ignore it.
const double kEditRecommendedShift = 3.0;

/// Draw Things SeedMode SCALE_ALIKE (2) — stable edit result across sizes.
const int kEditRecommendedSeedMode = 2;

/// A sane step count for a non-lightning edit pass.
const int kEditRecommendedSteps = 20;

/// Default for the "How much should change?" slider. Instruction-edits with
/// multi-change prompts come out under-driven below this, so the default is
/// "do what I asked"; the user dials DOWN for subtle, identity-preserving edits.
const double kEditRecommendedStrength = 1.0;
