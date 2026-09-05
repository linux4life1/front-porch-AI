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

import 'dart:convert';
import 'dart:io';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk_session.dart';
import 'package:front_porch_ai/services/desk/desk_sit_down.dart';
import 'package:path/path.dart' as p;

const kDeskLastFile = 'last_desk.json';
const kDeskStoreFolder = 'desk';

String deskStoreDirectory(String dataRoot) =>
    p.join(dataRoot, kDeskStoreFolder);

/// JSON under a data dir — not the chat `messages` / `sessions` tables.
class DeskStore {
  DeskStore(this.directory);

  final String directory;

  File get _file => File(p.join(directory, kDeskLastFile));

  Future<void> saveLast(DeskSession session) async {
    await Directory(directory).create(recursive: true);
    final map = {
      'title': session.title,
      'folderRoot': session.folderRoot,
      'mode': session.mode.name,
      'coworker': {
        'name': session.coworker.name,
        'personality': session.coworker.personality,
        'description': session.coworker.description,
        'systemPrompt': session.coworker.systemPrompt,
      },
      'transcript': [
        for (final m in session.transcript)
          {'isUser': m.isUser, 'text': m.text},
      ],
    };
    await _file.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }

  Future<DeskSession?> loadLast() async {
    if (!await _file.exists()) return null;
    try {
      final map = jsonDecode(await _file.readAsString());
      if (map is! Map) return null;
      final coworker = map['coworker'];
      if (coworker is! Map) return null;
      final folder = map['folderRoot']?.toString() ?? '';
      if (folder.isEmpty) return null;
      final modeName = map['mode']?.toString() ?? 'build';
      final mode = DeskMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => DeskMode.build,
      );
      final transcript = <DeskMessage>[];
      final raw = map['transcript'];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          transcript.add(
            DeskMessage(
              isUser: e['isUser'] == true,
              text: e['text']?.toString() ?? '',
            ),
          );
        }
      }
      return DeskSession(
        folderRoot: folder,
        coworker: CharacterCard(
          name: coworker['name']?.toString() ?? 'Coworker',
          personality: coworker['personality']?.toString() ?? '',
          description: coworker['description']?.toString() ?? '',
          systemPrompt: coworker['systemPrompt']?.toString() ?? '',
        ),
        mode: mode,
        title: map['title']?.toString() ?? '',
        transcript: transcript,
      );
    } catch (_) {
      return null;
    }
  }
}
