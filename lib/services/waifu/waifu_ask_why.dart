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

/// Plain-English reason the Build ask dialog is on screen.
///
/// Normies do not know `rm -rf`. Say what happens, not the flag alphabet.
String waifuAskWhy({
  required String name,
  required Map<String, dynamic> args,
  bool doomLoop = false,
}) {
  if (doomLoop) {
    return 'She already ran this exact step twice. A third time is often '
        'a stuck loop changing the same thing over and over.';
  }
  final canon = canonicalWaifuToolName(name);
  if (canon == kWaifuToolSkillInstall) {
    return 'This would download and install a skill onto this computer.';
  }
  if (canon == kWaifuToolWrite ||
      canon == kWaifuToolEdit ||
      canon == kWaifuToolApplyPatch) {
    final path = waifuToolPathArg(args) ?? 'a file';
    return 'This would change $path, which is outside the project folder '
        'you sat down on.';
  }
  if (canon == kWaifuToolBash) {
    return waifuAskWhyBash(
      args['command']?.toString() ?? args['cmd']?.toString() ?? '',
    );
  }
  return 'This would change files on your computer.';
}

String waifuAskWhyBash(String command) {
  final lower = command.toLowerCase();
  final recursiveRm =
      RegExp(r'\brm\b').hasMatch(lower) &&
      (RegExp(r'(^|\s)-[a-z]*r').hasMatch(lower) ||
          lower.contains('--recursive') ||
          lower.contains('-rf') ||
          lower.contains('-fr'));
  if (recursiveRm) {
    return 'This would permanently delete files and folders. '
        'You cannot undo that from here.';
  }
  if (RegExp(r'\brm\b').hasMatch(lower) ||
      RegExp(r'\brmdir\b').hasMatch(lower) ||
      RegExp(r'\bunlink\b').hasMatch(lower)) {
    return 'This would delete a file. You cannot undo that from here.';
  }
  if (RegExp(r'\b(mv|move)\b').hasMatch(lower)) {
    return 'This would move or rename files.';
  }
  if (RegExp(r'\b(cp|copy)\b').hasMatch(lower)) {
    return 'This would copy files, and can overwrite ones that already exist.';
  }
  if (RegExp(r'\bmkdir\b').hasMatch(lower)) {
    return 'This would create a new folder.';
  }
  if (RegExp(r'\bchmod\b').hasMatch(lower) ||
      RegExp(r'\bchown\b').hasMatch(lower)) {
    return 'This would change who is allowed to read or change files.';
  }
  if (RegExp(r'\bgit\b').hasMatch(lower) &&
      RegExp(
        r'\b(commit|add|push|checkout|reset|merge|rebase|stash)\b',
      ).hasMatch(lower)) {
    return 'This would change git history or the saved snapshot of this project.';
  }
  if (RegExp(
    r'\b(npm|pnpm|yarn|pip|pip3|cargo|gem|composer|brew)\b',
  ).hasMatch(lower)) {
    return 'This would install or update software using the terminal.';
  }
  if (lower.contains('>>') ||
      lower.contains('>') ||
      RegExp(r'\btee\b').hasMatch(lower)) {
    return 'This would create or overwrite a file using the terminal.';
  }
  return 'This terminal command can change files, not just look at them.';
}
