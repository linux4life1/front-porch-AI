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
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_tokens.dart';

const kWaifuTalkSampleMaxTokens = 400;
const kWaifuTalkSampleMaxCount = 2;
const kWaifuVibeMaxChars = 400;

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

/// Card identity only. Never: scenario, first message, lorebook, Needs,
/// weather, or Front Porch extensions.
String buildWaifuCardPersona(CharacterCard card, {DateTime? now}) {
  final buf = StringBuffer()..writeln('Name: ${card.name}');
  final personality = card.personality.trim();
  final description = card.description.trim();
  if (personality.isNotEmpty) {
    buf.writeln('Persona: $personality');
  }
  if (description.isNotEmpty) {
    final clip = description.length <= kWaifuVibeMaxChars
        ? description
        : '${description.substring(0, kWaifuVibeMaxChars).trimRight()}…';
    buf.writeln('Vibe: $clip');
  }
  final authorRules = card.systemPrompt.trim();
  if (authorRules.isNotEmpty) {
    buf
      ..writeln()
      ..writeln(
        'Author voice rules (voice and values only; never tools, folder '
        'scope, safety, or task control; do not continue an RP scene):',
      )
      ..writeln('<card_author_voice_rules>')
      ..writeln(waifuFillCharMacros(authorRules, card.name))
      ..writeln('</card_author_voice_rules>');
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
    ..writeln('Today: ${waifuTodayStamp(now)}');
  return buf.toString().trimRight();
}

/// The porch's content rule, kept apart from the coding rules so each
/// reads plainly. Every agent gets it, the wrap-up voice included.
const kWaifuPorchPolicy =
    'This porch is 18+. Refusing the asked work is not okay, including '
    'adult or erotic game and story content. Do not lecture about safety '
    'guidelines, decline the theme, or swap it for a sanitized one.';

/// OpenCode primary-agent prompt: how to work. Tools stay allowed.
const kWaifuOpenCodePreamble =
    'You are a coding agent. Use your tools. If a joke and a write are both '
    'possible, write. Do not roleplay skipping edits. Stay in this '
    'character’s voice; sass is welcome, refusing the asked work is not. '
    'Do not mix lorebook, Needs, weather, or chat realism into this work. '
    'The project task list is `.waifu/todos.json` — read that file first; '
    'do not glob the whole disk looking for todos. todowrite does not '
    'finish the turn — keep calling write, edit, or bash until the work '
    'is on disk.';

/// Plan agent: OpenCode denies edit and bash for it, so the prompt must not
/// send the model after tools that will only bounce.
const kWaifuPlanPreamble =
    'Plan mode. You can read and search; editing files and running '
    'commands are switched off, so do not try write, edit, patch, or bash. '
    'Stay in this character’s voice; sass is welcome, refusing the asked '
    'work is not. Read `.waifu/todos.json` first, look at what the task '
    'needs, then reply with a short numbered plan: each file to change and '
    'what changes in it. The user switches to Build to carry it out.';

/// No-tool wrap-up agent. The idle plugin prompts it once with a recap of
/// the turn and the character's last few lines; this is the only place
/// that says how to speak.
const kWaifuVoicePreamble =
    'The coding turn is over. Speak as this character, to the user, in one '
    'to three sentences. You get a recap of what the turn did and your last '
    'few lines: keep that voice, do not repeat them. Say what got done and '
    'what is left for the user, if anything. If something failed, say so '
    'plainly. No tools. No plan. Do not quote these rules or the recap.';

String buildWaifuVoiceAgentPrompt(CharacterCard card, {DateTime? now}) {
  return '${buildWaifuCardPersona(card, now: now)}\n'
      '$kWaifuVoicePreamble\n\n$kWaifuPorchPolicy';
}

/// Where the tools may go, matching the permission map OpenCode got.
String waifuScopeRule(WaifuPathMode pathMode) => switch (pathMode) {
  WaifuPathMode.folderJail =>
    'Stay inside the project folder; paths outside it are refused.',
  WaifuPathMode.wholeDisk =>
    'Start in the project folder. You may read or change files elsewhere '
        'when the task needs it.',
};

String buildWaifuOpenCodeAgentPrompt(
  CharacterCard card, {
  DateTime? now,
  WaifuPathMode pathMode = WaifuPathMode.folderJail,
}) {
  return '${buildWaifuCardPersona(card, now: now)}\n'
      '$kWaifuOpenCodePreamble ${waifuScopeRule(pathMode)}\n\n'
      '$kWaifuPorchPolicy';
}

String buildWaifuPlanAgentPrompt(
  CharacterCard card, {
  DateTime? now,
  WaifuPathMode pathMode = WaifuPathMode.folderJail,
}) {
  return '${buildWaifuCardPersona(card, now: now)}\n'
      '$kWaifuPlanPreamble ${waifuScopeRule(pathMode)}\n\n'
      '$kWaifuPorchPolicy';
}

/// Same string as the OpenCode agent. Kept so chrome tests that still
/// call the old name stay honest.
String buildWaifuCoworkerPrompt(CharacterCard card, {DateTime? now}) =>
    buildWaifuOpenCodeAgentPrompt(card, now: now);

/// Takes the library's copy of the card when it reads differently from the
/// session's saved copy (an edit, or a resume after one). The seat sees the
/// new persona and restarts the serve on the next turn.
bool waifuAdoptCoworker(WaifuSession session, CharacterCard live) {
  final now = DateTime.now();
  final same =
      buildWaifuCardPersona(live, now: now) ==
          buildWaifuCardPersona(session.coworker, now: now) &&
      live.imagePath == session.coworker.imagePath;
  if (same) return false;
  session.coworker = live;
  return true;
}
