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
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:path/path.dart' as p;

CharacterCard _mira() => CharacterCard(name: 'Mira', personality: 'tsundere');

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desk_h_holes_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('general child cannot spawn a grandchild generate', () async {
    final llm = ScriptedDeskLlm([
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
      const LlmToolResponse(calls: [], text: 'Child stopped nesting.'),
      const LlmToolResponse(calls: [], text: 'Hmph. Stayed one deep.'),
    ]);
    final session = DeskSession(
      folderRoot: root.path,
      coworker: _mira(),
      mode: DeskMode.yolo,
    );
    await DeskHarness(session: session, llm: llm).send('nest it');
    // parent + child-task + child-final + parent-final. A grandchild
    // send would consume a fifth generate.
    expect(llm.calls, hasLength(4));
    expect(
      llm.calls[1].tools.map((t) => (t['function'] as Map)['name']).toList(),
      isNot(contains(kDeskToolTask)),
    );
  });

  test('general child write /etc is a jail error, not a write', () async {
    final llm = ScriptedDeskLlm([
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
    final session = DeskSession(
      folderRoot: root.path,
      coworker: _mira(),
      mode: DeskMode.yolo,
    );
    await DeskHarness(session: session, llm: llm).send('pwn /etc');
    final spoken = session.transcript.map((m) => m.text).join('\n');
    expect(spoken.toLowerCase(), isNot(contains('pwned')));
    expect(spoken.toLowerCase(), anyOf(contains('jail'), contains('passwd')));
  });
}
