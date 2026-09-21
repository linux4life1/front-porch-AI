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

// THE DEAD-SURFACE RATCHET.
//
// Everything listed here was deleted because nothing called it. That is a
// one-way door on purpose: dead code in this repository has always come back
// the same way, as a file or helper somebody writes, exports through a barrel,
// and then never wires to a caller. The compiler cannot object — an exported
// symbol with no callers is perfectly legal Dart — so nothing announces it.
//
// This is not a behaviour guard and does not pretend to be one. It is the same
// shape as the god-file ratchet: a list that may only shrink, and only on
// purpose. If one of these names is genuinely needed again, bring it back
// WITH its caller and delete its entry here in the same change. An entry
// disappearing silently is the failure mode this exists to make loud.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files deleted as unused. A path returning means dead code came back.
const List<String> kDeletedFiles = [
  // Tool-chip caption helpers for Waifu Coder. The chrome builds its own
  // labels; these two were exported from the barrel and called by nobody.
  'lib/services/waifu/waifu_chips.dart',
  // Auto-saving field wrapper written during the creator extraction. The
  // creator steps use AppTextField / creator_hint_field instead.
  'lib/ui/character_creator/widgets/styled_text_field.dart',
];

/// Declarations deleted as unused, and what to reach for instead. Matched as
/// whole words, so a live longer name that merely starts the same (for example
/// streamOpenAiChatToolsWithStyleRetry) is not a hit.
const Map<String, String> kDeletedSymbols = {
  'decodeFpWorldString': 'decodeFpWorld takes the already-decoded map',
  'kEvalWallClockTimeout': 'kFusedEvalBudget is the budget the evals use',
  'streamOpenAiChatTools': 'streamOpenAiChatToolsWithStyleRetry is the door',
  'remoteApiUrlIsOmlx': 'oMLX is selected by BackendType.omlx, not by URL',
  'kWaifuLegacyDotDir': 'kWaifuDotDir; the .desk migration is long done',
  'waifuPromptSpeech': 'OpenCode owns its session; the app replays no history',
  'waifuClipPreservedThinking': 'went with waifuPromptSpeech, its only caller',
  'kWaifuPreserveThinkMaxChars': 'ditto',
  'WaifuJail': 'OpenCode enforces path scope; WaifuPathMode tells it which',
  'WaifuJailHit': 'ditto',
  'waifuStripRedundantProjectPrefix': 'was internal to the deleted resolver',
  'waifuQuestionFromArgs': 'WaifuQuestionRequest is built by the ask dialog',
  'kWaifuTodosRel': 'waifuTodosFile joins the path',
  'waifuTodoStatusIsDone': 'waifuTodoCanonicalStatus / waifuTodoMark',
  'waifuTodoWriteError': 'OpenCode validates its own todowrite payload',
  'kWaifuReadClipChars': 'OpenCode clips tool output',
  'waifuShouldCompact': 'the context bar compares fill against kWaifuCompactAt',
  'worldLoreEntryToolSchema': 'worldLoreBatchToolSchema is the live schema',
  'getModeLabel': 'the studio labels its own selector',
  'decodeWorldRefList': 'resolveWorldRefsToIds takes the list',
  'encodeWorldRefList': 'callers jsonEncode at the write site',
};

void main() {
  test('deleted files stay deleted', () {
    final returned = kDeletedFiles.where((p) => File(p).existsSync()).toList();
    expect(
      returned,
      isEmpty,
      reason:
          'these files were deleted as unused and are back:\n'
          '${returned.join('\n')}\n'
          'If one is genuinely needed, land it with a caller and drop its '
          'entry from kDeletedFiles in the same change.',
    );
  });

  test('no barrel still exports a deleted file', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final deleted in kDeletedFiles) {
        final name = deleted.split('/').last;
        if (RegExp("export\\s+'[^']*$name'").hasMatch(source) ||
            RegExp("import\\s+'[^']*$name'").hasMatch(source)) {
          offenders.add('${entity.path} still references $name');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a deleted file is still referenced, so the tree will not '
          'build:\n${offenders.join('\n')}',
    );
  });

  test('deleted declarations stay deleted', () {
    final patterns = {
      for (final name in kDeletedSymbols.keys)
        name: RegExp('\\b${RegExp.escape(name)}\\b'),
    };
    final returned = <String>{};

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      patterns.forEach((name, pattern) {
        if (pattern.hasMatch(source)) {
          returned.add('$name is back in ${entity.path}');
        }
      });
    }

    expect(
      returned.toList(),
      isEmpty,
      reason:
          'these declarations were deleted as unused:\n'
          '${returned.join('\n')}\n'
          'Each one has a live replacement — see kDeletedSymbols. If the '
          'replacement genuinely does not fit, bring the name back with its '
          'caller and drop its entry here in the same change.',
    );
  });
}
