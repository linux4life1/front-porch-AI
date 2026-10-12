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

/// Where the card's portrait comes from in the "Portrait & Avatars" step.
enum PortraitSource { upload, generate, none }

/// Stage of the creator generation run (drives the progress list).
///
/// [portraitReview] is the veto gate: after the base portrait generates and a
/// pack is pending, the run PAUSES here so the user can regenerate (after
/// tweaking the prompt) or accept it before the expensive expression pass.
enum AvatarRunStage {
  idle,
  saving,
  portrait,
  portraitReview,
  switching,
  pack,
  qc,
  importing,
  done,
  failed,
}
