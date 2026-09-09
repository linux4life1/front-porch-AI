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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu_jail.dart';
import 'package:front_porch_ai/services/waifu/waifu_lang_runtime.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';
import 'package:front_porch_ai/services/waifu/waifu_todos.dart';

class WaifuToolChip {
  const WaifuToolChip({
    required this.name,
    required this.detail,
    required this.ok,
    this.pending = false,
  });

  final String name;
  final String detail;
  final bool ok;

  /// Live attempt — [ok] is ignored until the tool settles.
  final bool pending;
}

class WaifuWriteRecord {
  const WaifuWriteRecord({
    required this.relativePath,
    required this.before,
    required this.after,
  });

  final String relativePath;
  final String before;
  final String after;
}

class WaifuMessage {
  const WaifuMessage({
    required this.isUser,
    required this.text,
    this.chips = const [],
    this.reasoning = '',
    this.thinkingStartMs,
    this.thinkingMs = 0,
    this.imagePath,
    this.hidden = false,
  });

  final bool isUser;
  final String text;
  final List<WaifuToolChip> chips;
  final String reasoning;
  final int? thinkingStartMs;
  final int thinkingMs;
  final String? imagePath;

  /// Prompt-only (session recap). Not painted as a bubble.
  final bool hidden;

  /// Same shape chat bubbles parse: `<think>` + spoken line.
  ChatMessage toChatMessage(String coworkerName) {
    final think = reasoning.trim();
    final raw = think.isEmpty ? text : '<think>$think</think>\n$text';
    final msg = ChatMessage(
      text: raw,
      sender: isUser ? 'You' : coworkerName,
      isUser: isUser,
      metadata: imagePath == null
          ? null
          : {'is_user_image': true, 'image_path': imagePath},
    );
    msg.thinkingStartTime = thinkingStartMs;
    if (thinkingMs > 0) msg.thinkingDurationMs = thinkingMs;
    return msg;
  }
}

/// In-memory Waifu Coder session. Not a chat `sessions` row.
class WaifuSession {
  WaifuSession({
    required this.folderRoot,
    required this.coworker,
    this.mode = WaifuMode.build,
    this.pathMode = WaifuPathMode.folderJail,
    this.title = '',
    this.langs,
    this.mcpOptIn = false,
    this.preserveThinking = false,
    this.toolsSupported = true,
    this.activePlanPath,
    ChatThemeOverrides? themeOverrides,
    Set<String>? suggestedLangs,
    List<WaifuMessage>? transcript,
    WaifuTodos? todos,
  }) : suggestedLangs = suggestedLangs ?? <String>{},
       transcript = transcript ?? <WaifuMessage>[],
       themeOverrides = themeOverrides ?? ChatThemeOverrides(),
       todos = todos ?? WaifuTodos();

  final String folderRoot;
  final CharacterCard coworker;
  WaifuMode mode;
  final WaifuPathMode pathMode;
  String title;
  WaifuLangRuntime? langs;
  final Set<String> suggestedLangs;
  final List<WaifuMessage> transcript;
  final WaifuTodos todos;
  WaifuWriteRecord? lastWrite;

  /// Writes landed on the current send. Cleared at the start of [send].
  final List<WaifuWriteRecord> turnWrites = [];

  /// Mutated paths that got a verify receipt this send.
  final List<String> turnVerifyPaths = [];
  bool running = false;
  bool mcpOptIn;
  bool preserveThinking;

  /// Sit-down / live probe. False fail-closes the loop — no silent coding.
  bool toolsSupported;
  String? activePlanPath;
  ChatThemeOverrides themeOverrides;
  final ChatGenerationSettings genSettings = ChatGenerationSettings();
  int contextBudget = 8192;
  int tokensUsed = 0;

  /// True when [tokensUsed] came from the last API `usage` block.
  bool tokensFromApi = false;
  int compactPasses = 0;

  /// Tool results kept across sends (OpenCode/Claude). Pruned when old.
  final List<String> toolTraces = [];

  List<WaifuToolChip> get toolChips => [for (final m in transcript) ...m.chips];
}
