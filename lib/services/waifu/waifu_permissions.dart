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

/// Ask-dialog types. OpenCode owns permissions; Dart does not decide.
enum WaifuAskDecision { allowOnce, allowAlways, deny }

class WaifuAskRequest {
  const WaifuAskRequest({
    required this.toolName,
    required this.summary,
    this.why = '',
    this.doomLoop = false,
  });

  final String toolName;
  final String summary;
  final String why;
  final bool doomLoop;
}

typedef WaifuAskFn = Future<WaifuAskDecision> Function(WaifuAskRequest request);

/// "Mira wants to run a command": the ask told as her request, with the
/// full command or path shown under it, never trimmed.
String waifuAskHeadline(String name, WaifuAskRequest request) {
  final tool = request.toolName.trim();
  if (request.doomLoop) return '$name keeps reaching for $tool';
  return switch (tool.toLowerCase()) {
    'bash' => '$name wants to run a command',
    'edit' ||
    'write' ||
    'patch' ||
    'multiedit' => '$name wants to change files',
    'read' => '$name wants to read a file',
    'external_directory' => '$name wants to work outside the project folder',
    'webfetch' || 'websearch' => '$name wants to look something up online',
    'task' => '$name wants to hand off a side task',
    _ => '$name wants to use $tool',
  };
}
