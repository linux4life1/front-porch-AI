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

import 'package:front_porch_ai/services/waifu/waifu_tools.dart';

/// After this many project file writes, the send ends with a spoken line.
/// Small tasks never hit it. Not a Keep-going dialog.
const kWaifuCheckInEvery = 6;

const kWaifuCheckInCue =
    'Do not one-shot a large job in silence. After a handful of project '
    'file writes, stop adding files, re-read what you changed, and run a '
    'real test/analyze. If it fails, fix and run it again. Only then speak '
    'in character: where you are and what is next. Never invent a passing '
    'test or a write that has no receipt. That spoken line ends this turn. '
    'Use question only for a real fork, never a keep-going prompt.';

const kWaifuCheckInTurnCue =
    'TURN CONTRACT: Stop adding files. Re-read the files you changed, then '
    'run a real test/analyze. If it fails, fix them and test again. Speak '
    'one in-character line only after that check passes — that line ends '
    'this turn. Never invent a passing test or a write that has no receipt.';

const kWaifuCheckInTools = {
  kWaifuToolEdit,
  kWaifuToolApplyPatch,
  kWaifuToolWrite,
};

bool waifuCheckInDue(int mutationsSinceCheckIn) =>
    mutationsSinceCheckIn >= kWaifuCheckInEvery;

bool waifuCheckInCounts(String toolName) =>
    kWaifuCheckInTools.contains(canonicalWaifuToolName(toolName));
