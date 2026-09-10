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
String waifuHonestyBody(WaifuPathMode pathMode) {
  final scope = switch (pathMode) {
    WaifuPathMode.folderJail =>
      '**Folder jail is the safer default.** Their files, symlinks, and bash '
          'paths stay inside the project folder you picked.',
    WaifuPathMode.wholeDisk =>
      '**Whole-disk access makes that folder a starting porch, not a fence.** '
          'They can follow absolute paths, ~, .., and cd to read or change '
          'other files anywhere your account can reach.',
  };
  return '$kWaifuCoderName puts real coding tools in your selected coworker’s '
      'hands: read, search, apply_patch, write, bash, tests, and visible '
      'receipts. They work on disk while speaking as the card — not as a '
      'generic assistant.\n'
      '$scope\n'
      'In either mode, hard stops still block secrets, destructive Git, '
      'force-pushes, and wipe-the-machine commands. They are guardrails, not '
      'a backup.\n'
      'This is its own harness — not a promise to match Claude Code, Grok '
      'Build, OpenCode, or Cursor on every model. A model can still be '
      'confidently wrong. **Never use it on a critical codebase**; keep a '
      'throwaway branch, a backup, and an eye on the receipts.';
}

String waifuHonestyCheckbox(WaifuPathMode pathMode) {
  return switch (pathMode) {
    WaifuPathMode.folderJail =>
      'I understand the folder jail is on, guardrails are not a backup, and '
          'I will not use $kWaifuCoderName on code I cannot afford to lose.',
    WaifuPathMode.wholeDisk =>
      'I understand this folder is only a starting porch. $kWaifuCoderName '
          'can read or change files elsewhere on my disk, and I will not use '
          'it on code I cannot afford to lose.',
  };
}

const kWaifuLocalModelWarning =
    'Small local models often skip tools or wreck edits. A remote coding '
    'model works much better.';

const kWaifuHonestySkipped =
    'Honesty is already on file for this scope. You can still switch Jail '
    'or Disk.';

String waifuYoloWarning(WaifuPathMode pathMode) {
  return switch (pathMode) {
    WaifuPathMode.folderJail =>
      'Yolo skips “are you sure?” on writes, commands, and repeats. The '
          'folder jail still holds, and the wipe/secret hard stops stay awake.',
    WaifuPathMode.wholeDisk =>
      'Yolo skips “are you sure?” — including repeats — and this coworker '
          'can walk the whole disk. The wipe/secret hard stops stay awake; '
          'your backup should too.',
  };
}

String waifuPathModeTitle(WaifuPathMode pathMode) => switch (pathMode) {
  WaifuPathMode.folderJail => 'Folder jail (safer default)',
  WaifuPathMode.wholeDisk => 'Whole-disk access',
};

String waifuPathModeBlurb(WaifuPathMode pathMode) => switch (pathMode) {
  WaifuPathMode.folderJail =>
    'Keep their file and bash paths on this project porch. Outside paths and '
        'escaping symlinks are turned away.',
  WaifuPathMode.wholeDisk =>
    'Let them roam like a full coding agent. This folder is the first stop, '
        'not the property line.',
};

String waifuPathModeSessionLine(WaifuPathMode pathMode) => switch (pathMode) {
  WaifuPathMode.folderJail =>
    'Scope: Folder jail — file and bash paths stay on this porch.',
  WaifuPathMode.wholeDisk =>
    'Scope: Whole disk — this porch is the starting folder, not a fence.',
};

String waifuModeLabel(WaifuMode mode) => switch (mode) {
  WaifuMode.plan => 'Plan',
  WaifuMode.build => 'Build',
  WaifuMode.yolo => 'Yolo',
};

/// Compact AppBar / sit-down badge. Full name stays on [waifuPathModeTitle].
String waifuScopeBadgeLabel(WaifuPathMode pathMode) => switch (pathMode) {
  WaifuPathMode.folderJail => 'Jail',
  WaifuPathMode.wholeDisk => 'Disk',
};

String waifuEmptyPrompt(WaifuPathMode pathMode, String coworker) =>
    switch (pathMode) {
      WaifuPathMode.folderJail =>
        'Tell $coworker what to build. Their tools stay on this project porch.',
      WaifuPathMode.wholeDisk =>
        'Tell $coworker what to build. They start from this porch and can '
            'work elsewhere on your disk.',
    };

String waifuMcpScopeWarning(WaifuPathMode pathMode) => switch (pathMode) {
  WaifuPathMode.folderJail =>
    'The folder jail covers Waifu Coder’s own file and bash tools. MCP tools '
        'answer to their server, beyond that fence — only invite servers you '
        'trust.',
  WaifuPathMode.wholeDisk =>
    'Whole-disk access is already open. MCP tools also answer to their own '
        'server — only invite servers you trust.',
};

const kWaifuToolsUnsupported =
    'This model cannot do $kWaifuCoderName. Tool calling is unsupported. '
    'Sit down is blocked — pick a tool-fluent backend in Settings.';
