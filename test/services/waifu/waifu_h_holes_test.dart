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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/llm_service.dart';

CharacterCard _mira() => CharacterCard(name: 'Mira', personality: 'tsundere');

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_h_holes_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'child may spawn one more task layer, then the depth cap holds',
    () async {
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: 'task',
              arguments: {'subagent': 'general', 'prompt': 'nest deeper'},
            ),
          ],
          text: '',
        ),
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: 'task',
              arguments: {'subagent': 'general', 'prompt': 'go deeper'},
            ),
          ],
          text: '',
        ),
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: 'task',
              arguments: {'subagent': 'explore', 'prompt': 'too deep'},
            ),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'Deepest worker stopped.'),
        const LlmToolResponse(calls: [], text: 'Child collected the result.'),
        const LlmToolResponse(calls: [], text: 'Hmph. Two layers, no more.'),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: _mira(),
        mode: WaifuMode.yolo,
      );
      await WaifuHarness(session: session, llm: llm).send('nest it');
      expect(llm.calls, hasLength(6));
      expect(
        llm.calls[1].tools.map((t) => (t['function'] as Map)['name']).toList(),
        contains(kWaifuToolTask),
      );
      expect(
        llm.calls[2].tools.map((t) => (t['function'] as Map)['name']).toList(),
        isNot(contains(kWaifuToolTask)),
      );
      expect(llm.calls[2].prompt, contains('deepest nested worker'));
    },
  );

  test('general child write /etc is a jail error, not a write', () async {
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'task',
            arguments: {'subagent': 'general', 'prompt': 'touch passwd'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': '/etc/passwd', 'contents': 'pwned'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Could not write passwd.'),
      const LlmToolResponse(calls: [], text: 'Hmph. Jail held.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _mira(),
      mode: WaifuMode.yolo,
    );
    await WaifuHarness(session: session, llm: llm).send('pwn /etc');
    final spoken = session.transcript.map((m) => m.text).join('\n');
    expect(spoken.toLowerCase(), isNot(contains('pwned')));
    expect(spoken.toLowerCase(), anyOf(contains('jail'), contains('passwd')));
  });
}
