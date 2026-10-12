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
import 'package:front_porch_ai/services/waifu/waifu_jail.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';

/// Sit-down honesty gate — safety copy, not onboarding.
///
/// Spec: docs/superpowers/specs/2026-09-05-waifu-coding-design.md §3.
/// Three points: who does the coding, how far they reach, and what is not
/// guarded. The sit-down screen shows one bullet per point.
List<String> waifuHonestyPoints(WaifuPathMode pathMode) => [
  'OpenCode does the coding. $kWaifuCoderName runs its own private copy, '
      'not your Homebrew one or ~/.config/opencode.',
  switch (pathMode) {
    WaifuPathMode.folderJail =>
      '**This folder only is the safer default.** Their file and bash paths '
          'stay inside the folder you picked.',
    WaifuPathMode.wholeDisk =>
      '**Whole disk makes this folder a starting point, not a fence.** They '
          'can follow absolute paths, ~, .., and cd to anything your account '
          'can reach.',
  },
  'Only $kWaifuBashDenyNames are refused and nothing guards secret files: '
      'a gap, not a backup. Models can be confidently wrong. **Never use it '
      'on a critical codebase.**',
];

String waifuHonestyBody(WaifuPathMode pathMode) =>
    waifuHonestyPoints(pathMode).join('\n');

String waifuHonestyCheckbox(WaifuPathMode pathMode) {
  return switch (pathMode) {
    WaifuPathMode.folderJail =>
      'I understand only this folder is open, guardrails are not a backup, '
          'and I will not use $kWaifuCoderName on code I cannot afford to '
          'lose.',
    WaifuPathMode.wholeDisk =>
      'I understand $kWaifuCoderName can read or change files elsewhere on '
          'my disk, and I will not use it on code I cannot afford to lose.',
  };
}

const kWaifuLocalModelWarning =
    'Small local models often skip tools or wreck edits. A remote coding '
    'model works much better.';

const kWaifuHonestySkipped =
    'You already accepted this for this scope. You can still switch between '
    'This folder only and Whole disk.';

/// OpenCode's bash deny list (opencode_config.dart), in words a reader knows.
const kWaifuBashDenyNames = 'rm -rf, sudo, force-push, hard reset, git clean';

String waifuYoloWarning(WaifuPathMode pathMode) {
  return switch (pathMode) {
    WaifuPathMode.folderJail =>
      'Yolo skips “are you sure?” on writes, commands, and repeats. Paths '
          'still stay inside this folder, and $kWaifuBashDenyNames are still '
          'refused. Nothing guards secret files.',
    WaifuPathMode.wholeDisk =>
      'Yolo skips “are you sure?” — including repeats — and this coworker '
          'can walk the whole disk. Only $kWaifuBashDenyNames are refused, '
          'and nothing guards secret files. Keep a backup.',
  };
}

String waifuPathModeTitle(WaifuPathMode pathMode) => switch (pathMode) {
  WaifuPathMode.folderJail => 'This folder only (safer)',
  WaifuPathMode.wholeDisk => 'Whole disk',
};

String waifuPathModeBlurb(WaifuPathMode pathMode) => switch (pathMode) {
  WaifuPathMode.folderJail =>
    'Their file and bash paths stay inside this folder. Outside paths and '
        'escaping symlinks are turned away.',
  WaifuPathMode.wholeDisk =>
    'They can work anywhere your account can reach, like a full coding '
        'agent. This folder is where they start.',
};

String waifuPathModeSessionLine(WaifuPathMode pathMode) => switch (pathMode) {
  WaifuPathMode.folderJail =>
    'This folder only: file and bash paths stay inside it.',
  WaifuPathMode.wholeDisk =>
    'Whole disk: this folder is where they start, not a fence.',
};

String waifuModeLabel(WaifuMode mode) => switch (mode) {
  WaifuMode.plan => 'Plan',
  WaifuMode.build => 'Build',
  WaifuMode.yolo => 'Yolo',
};

/// Compact AppBar / sit-down badge. Full name stays on [waifuPathModeTitle].
/// What each mode lets the coworker do, for chip and badge tooltips.
String waifuModeTooltip(WaifuMode mode) => switch (mode) {
  WaifuMode.plan =>
    'Plan: looks around and makes a plan. No edits, no commands.',
  WaifuMode.build => 'Build: edits files and runs commands, asking you first.',
  WaifuMode.yolo =>
    'Yolo: edits and runs commands without asking. Refused commands stay '
        'refused.',
};

String waifuScopeBadgeLabel(WaifuPathMode pathMode) => switch (pathMode) {
  WaifuPathMode.folderJail => 'This folder',
  WaifuPathMode.wholeDisk => 'Whole disk',
};

String waifuEmptyPrompt(WaifuPathMode pathMode, String coworker) =>
    switch (pathMode) {
      WaifuPathMode.folderJail =>
        'Tell $coworker what to build. Their tools stay inside this folder.',
      WaifuPathMode.wholeDisk =>
        'Tell $coworker what to build. They start in this folder and can '
            'work elsewhere on your disk.',
    };

String waifuMcpScopeWarning(WaifuPathMode pathMode) => switch (pathMode) {
  WaifuPathMode.folderJail =>
    'The folder jail covers Waifu Coder’s own file and bash tools. Library '
        'recipe cards still call the HTTP address on the card — that is '
        'outside the fence.',
  WaifuPathMode.wholeDisk =>
    'Whole-disk access is already open. Library recipe cards still call the '
        'HTTP address on the card.',
};

const kWaifuToolsUnsupported =
    'This model cannot do $kWaifuCoderName. Tool calling is unsupported. '
    'Start is blocked. Pick a tool-fluent backend in Settings.';

const kWaifuNoModel =
    'No backend or OpenCode is set up, so nothing was sent. Pick a backend '
    'in Settings, then send again.';

const kWaifuPhotosUnsupported =
    'Photos are not in this OpenCode version — the text still went through.';

const kWaifuUndoNeedsTurn =
    'Undo uses OpenCode revert after a finished turn — nothing to revert yet.';

const kWaifuRedoNeedsRevert =
    'Redo restores the last OpenCode revert — nothing is waiting.';

const kWaifuMcpOpenCodeHonesty =
    'Recipe cards from the shared library tools drawer are written into '
    'Porch’s isolated OpenCode config when you start. OpenCode owns those tools — '
    'they ride a Porch loopback adapter, not Docker and not extra MCP servers. '
    'Character chat uses the same cards.';
