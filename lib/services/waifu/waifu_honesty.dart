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

import 'package:front_porch_ai/services/waifu/waifu_brand.dart';

/// Sit-down honesty gate — safety copy, not onboarding.
///
/// Spec: docs/superpowers/specs/2026-09-05-waifu-coding-design.md §3.
const kWaifuHonestyBody =
    '$kWaifuCoderName is **not** a replacement for Claude Code, Grok Build, '
    'OpenCode, or Cursor. It will not be as reliable. **Never use it on a '
    'critical codebase** — not this app, not work, not anything you cannot '
    'afford to lose.\n'
    'This is a **fun** tool. It will *attempt* a task while staying in your '
    'character’s personality. She may sass you and still try. She may also '
    'skip a tool, half-edit a file, or be wrong. You picked the folder. You '
    'are responsible for it.';

const kWaifuHonestyCheckbox =
    'I understand. I will not use $kWaifuCoderName on code I cannot afford '
    'to lose.';

const kWaifuLocalModelWarning =
    'Small local models often skip tools or wreck edits. A remote coding '
    'model works much better.';

const kWaifuYoloWarning =
    'Yolo skips “are you sure?” on writes and commands. The folder jail '
    'still holds. Still not for critical repos.';

const kWaifuToolsUnsupported =
    'This model cannot do $kWaifuCoderName. Tool calling is unsupported. '
    'Sit down is blocked — pick a tool-fluent backend in Settings.';
