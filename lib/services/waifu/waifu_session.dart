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

class WaifuToolChip {
  const WaifuToolChip({
    required this.name,
    required this.detail,
    required this.ok,
  });

  final String name;
  final String detail;
  final bool ok;
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
  });

  final bool isUser;
  final String text;
  final List<WaifuToolChip> chips;
  final String reasoning;
  final int? thinkingStartMs;
  final int thinkingMs;
  final String? imagePath;

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
    this.activePlanPath,
    ChatThemeOverrides? themeOverrides,
    Set<String>? suggestedLangs,
    List<WaifuMessage>? transcript,
  }) : suggestedLangs = suggestedLangs ?? <String>{},
       transcript = transcript ?? <WaifuMessage>[],
       themeOverrides = themeOverrides ?? ChatThemeOverrides();

  final String folderRoot;
  final CharacterCard coworker;
  WaifuMode mode;
  final WaifuPathMode pathMode;
  String title;
  WaifuLangRuntime? langs;
  final Set<String> suggestedLangs;
  final List<WaifuMessage> transcript;
  WaifuWriteRecord? lastWrite;
  bool running = false;
  bool mcpOptIn;
  bool preserveThinking;
  String? activePlanPath;
  ChatThemeOverrides themeOverrides;
  final ChatGenerationSettings genSettings = ChatGenerationSettings();
  int contextBudget = 8192;
  int tokensUsed = 0;
  int compactPasses = 0;

  List<WaifuToolChip> get toolChips => [for (final m in transcript) ...m.chips];
}
