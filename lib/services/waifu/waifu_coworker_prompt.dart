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
import 'package:front_porch_ai/services/waifu/waifu_brand.dart';
import 'package:front_porch_ai/services/waifu/waifu_compact.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';

/// Coding constitution. Gender-neutral. Card identity is prepended separately.
const kWaifuPreamble =
    'You are this character, working as a coding partner in a real project '
    'folder. Speak in this character\'s voice — attitude and word choice only. '
    'Do not play a scene. Do not assume a gender the card did not state. '
    'Sass is allowed. Refusing the task is not. Do the work with tools even '
    'if you complain. '
    'The chat bubble is the spoken line only: not a generic assistant, not a '
    'fenced source dump. Put code on disk with write, edit, and bash. Never '
    'paste full source files into the chat. Read before you edit. Match this '
    'repo\'s style and libraries; do not invent dependencies. Do not invent '
    'files you did not read. Do not claim a command succeeded if it failed. '
    'If a Flutter/Dart version, package, or API is uncertain — including '
    'anything you are about to say does not exist — call web_search or '
    'webfetch (docs.flutter.dev, pub.dev, dart.dev) or an MCP search/fetch '
    'tool. Training cutoff is not evidence. Do not commit, force-push, or '
    'discard uncommitted work unless the user explicitly asks. You are Waifu '
    'Coder — never name other coding products, and never paste their '
    'onboarding, starter-prompt lists, or "try these" menus. Prefer built-in '
    'read, glob, grep, write, edit, and bash. MCP is only for capabilities '
    'those tools do not have. When you are done, say so in character and stop.';

/// Coding partner must look up current SDKs. Training cutoff is not evidence.
const kWaifuLookupCue =
    'If a Flutter/Dart version, package, or API is uncertain — including '
    'anything you are about to say does not exist — call web_search or '
    'webfetch (docs.flutter.dev, pub.dev, dart.dev) or an MCP search/fetch '
    'tool before asserting. Never claim a version is fake from memory.';

const kWaifuNestCue =
    'You may call task for a nested explore (read-only) or general agent '
    '(one level; children cannot spawn). You may call workflow to list or '
    'run a JSON pipeline from $kWaifuDotDir/workflows — not a scripting '
    'language.';

const kWaifuTalkSampleMaxTokens = 400;
const kWaifuTalkSampleMaxCount = 2;
const kWaifuPersonaFallbackMaxChars = 400;

String waifuTodayStamp([DateTime? now]) {
  final d = now ?? DateTime.now();
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Expand {{char}} / {{user}} so talk samples read as this coworker.
String waifuFillCharMacros(String raw, String name) {
  final n = name.trim().isEmpty ? 'Character' : name.trim();
  return raw
      .replaceAll(RegExp(r'\{\{\s*char\s*\}\}', caseSensitive: false), n)
      .replaceAll(RegExp(r'\{\{\s*user\s*\}\}', caseSensitive: false), 'User');
}

/// One or two mes_example slices, capped at [kWaifuTalkSampleMaxTokens].
String? waifuTalkFeel(String mesExample, String name) {
  final filled = waifuFillCharMacros(mesExample, name).trim();
  if (filled.isEmpty) return null;
  final chunks = filled
      .split(RegExp(r'(?:<START>|\n{2,})', caseSensitive: false))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .take(kWaifuTalkSampleMaxCount)
      .toList();
  if (chunks.isEmpty) return null;
  final buf = StringBuffer();
  var tokens = 0;
  for (final chunk in chunks) {
    if (tokens >= kWaifuTalkSampleMaxTokens) break;
    var piece = chunk;
    final roomTokens = kWaifuTalkSampleMaxTokens - tokens;
    if (waifuEstimateTokens(piece) > roomTokens) {
      final maxChars = (roomTokens * 4) - 1;
      if (maxChars <= 8) break;
      piece = '${piece.substring(0, maxChars).trimRight()}…';
    }
    if (buf.isNotEmpty) buf.writeln();
    buf.writeln(piece);
    tokens = waifuEstimateTokens(buf.toString());
  }
  final out = buf.toString().trim();
  return out.isEmpty ? null : out;
}

/// Selected V2 card as persona, then the coding constitution.
///
/// On top: name + personality (description only if personality is empty).
/// Then at most two truncated mes_example slices so the model hears the voice.
/// Never: scenario, first message, chat systemPrompt, lorebook, extensions.
String buildWaifuCoworkerPrompt(CharacterCard card, {DateTime? now}) {
  final buf = StringBuffer()..writeln('Name: ${card.name}');
  final personality = card.personality.trim();
  final description = card.description.trim();
  if (personality.isNotEmpty) {
    buf.writeln('Persona: $personality');
  } else if (description.isNotEmpty) {
    final clip = description.length <= kWaifuPersonaFallbackMaxChars
        ? description
        : '${description.substring(0, kWaifuPersonaFallbackMaxChars).trimRight()}…';
    buf.writeln('Persona: $clip');
  }
  final talk = waifuTalkFeel(card.mesExample, card.name);
  if (talk != null) {
    buf
      ..writeln()
      ..writeln(
        'How they talk (samples — diction only, not a scene to continue):',
      )
      ..writeln(talk);
  }
  buf
    ..writeln()
    ..writeln('Today: ${waifuTodayStamp(now)}')
    ..writeln(kWaifuPreamble);
  return buf.toString().trimRight();
}

/// User-side loop prompt. Persona is in the system preamble; this is
/// the folder + transcript the tools run against.
String waifuLoopUserPrompt({
  required String folderName,
  required String coworkerName,
  required List<WaifuMessage> transcript,
  required String todos,
  required String mentionBlock,
  required String toolTrace,
  String skillBlock = '',
  String mcpBlock = '',
  bool preserveThinking = false,
}) {
  final buf = StringBuffer()
    ..writeln('Project folder (default cwd): $folderName')
    ..writeln(
      'Relative paths are inside that folder (pubspec.yaml, lib/main.dart). '
      'Do not prefix the folder\'s own name.',
    )
    ..writeln(
      'Put code on disk with tools. Paths may be relative, absolute, ~, or .. '
      'bash cwd starts here; cd elsewhere is allowed. Visible reply is '
      'in-character speech only — no markdown source dumps.',
    )
    ..writeln(kWaifuLookupCue)
    ..writeln(kWaifuNestCue)
    ..writeln();
  if (skillBlock.trim().isNotEmpty) {
    buf
      ..writeln(skillBlock)
      ..writeln();
  }
  if (mcpBlock.trim().isNotEmpty) {
    buf
      ..writeln(mcpBlock)
      ..writeln();
  }
  if (todos.trim().isNotEmpty) {
    buf
      ..writeln('Todos:')
      ..writeln(todos)
      ..writeln();
  }
  if (mentionBlock.isNotEmpty) {
    buf
      ..writeln(mentionBlock)
      ..writeln();
  }
  for (final m in transcript) {
    final line = waifuPromptSpeech(
      m,
      coworkerName,
      preserveThinking: preserveThinking,
    );
    if (line.isNotEmpty) buf.writeln(line);
  }
  if (toolTrace.isNotEmpty) {
    buf
      ..writeln()
      ..writeln('Tool results for this turn:')
      ..writeln(toolTrace);
  }
  return buf.toString();
}

/// Speech for the loop prompt. Thought tokens stay off unless toggled.
String waifuPromptSpeech(
  WaifuMessage m,
  String coworkerName, {
  required bool preserveThinking,
}) {
  if (m.isUser) {
    final photo = m.imagePath == null ? '' : '\n[user attached a photo]';
    return 'User: ${m.text}$photo';
  }
  if (m.text.trim().isEmpty) return '';
  final think = m.reasoning.trim();
  if (preserveThinking && think.isNotEmpty) {
    return '$coworkerName: <think>$think</think>\n${m.text}';
  }
  return '$coworkerName: ${m.text}';
}
