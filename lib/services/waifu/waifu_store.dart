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
import 'package:front_porch_ai/services/waifu/waifu_jail.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';
import 'package:path/path.dart' as p;

const kWaifuLastFile = 'last_waifu.json';
const kWaifuProjectsFile = 'projects.json';
const kWaifuStoreFolder = 'waifu';

String waifuStoreDirectory(String dataRoot) =>
    p.join(dataRoot, kWaifuStoreFolder);

String waifuSessionSlug(String folderRoot) {
  final n = p.normalize(folderRoot);
  var h = 0;
  for (final c in n.codeUnits) {
    h = (h * 33 + c) & 0x7fffffff;
  }
  final base = p.basename(n).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return '${base}_$h';
}

class WaifuProject {
  const WaifuProject({
    required this.folderRoot,
    required this.title,
    required this.coworker,
    required this.touchedMs,
  });

  final String folderRoot;
  final String title;
  final CharacterCard coworker;
  final int touchedMs;

  String get folderName => p.basename(folderRoot);
}

Map<String, dynamic> _coworkerMap(CharacterCard c) => {
  'name': c.name,
  'personality': c.personality,
  'description': c.description,
  'systemPrompt': c.systemPrompt,
  'mesExample': c.mesExample,
  if (c.imagePath != null) 'imagePath': c.imagePath,
};

CharacterCard _coworkerFrom(Map map) => CharacterCard(
  name: map['name']?.toString() ?? 'Coworker',
  personality: map['personality']?.toString() ?? '',
  description: map['description']?.toString() ?? '',
  systemPrompt: map['systemPrompt']?.toString() ?? '',
  mesExample: map['mesExample']?.toString() ?? '',
  imagePath: map['imagePath']?.toString(),
);

/// JSON under a data dir — not the chat `messages` / `sessions` tables.
class WaifuStore {
  WaifuStore(this.directory);

  final String directory;

  File get _lastFile => File(p.join(directory, kWaifuLastFile));
  File get _indexFile => File(p.join(directory, kWaifuProjectsFile));
  File _sessionFile(String folder) =>
      File(p.join(directory, 'sessions', '${waifuSessionSlug(folder)}.json'));

  Future<void> saveLast(WaifuSession session) async {
    await Directory(directory).create(recursive: true);
    final map = _sessionMap(session);
    await _lastFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(map),
    );
    await Directory(p.join(directory, 'sessions')).create(recursive: true);
    await _sessionFile(
      session.folderRoot,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(map));
    await _upsertIndex(session);
  }

  Future<WaifuSession?> loadLast() async {
    final projects = await listProjects();
    if (projects.isNotEmpty) {
      return loadSession(projects.first.folderRoot);
    }
    return _readSessionFile(_lastFile);
  }

  Future<List<WaifuProject>> listProjects() async {
    await _migrateLastIntoIndex();
    return _readIndex();
  }

  Future<WaifuSession?> loadSession(String folderRoot) async {
    final own = await _readSessionFile(_sessionFile(folderRoot));
    if (own != null) return own;
    final last = await _readSessionFile(_lastFile);
    if (last != null && last.folderRoot == folderRoot) return last;
    return null;
  }

  Future<void> forgetProject(String folderRoot) async {
    final file = _sessionFile(folderRoot);
    if (await file.exists()) await file.delete();
    final projects = await listProjects();
    final next = [
      for (final p in projects)
        if (p.folderRoot != folderRoot) p,
    ];
    await _writeIndex(next);
  }

  Map<String, dynamic> _sessionMap(WaifuSession session) => {
    'title': session.title,
    'folderRoot': session.folderRoot,
    'mode': session.mode.name,
    'pathMode': session.pathMode.name,
    'mcpOptIn': session.mcpOptIn,
    'preserveThinking': session.preserveThinking,
    'coworker': _coworkerMap(session.coworker),
    'transcript': [
      for (final m in session.transcript)
        {
          'isUser': m.isUser,
          'text': m.text,
          if (m.reasoning.isNotEmpty) 'reasoning': m.reasoning,
          if (m.imagePath != null) 'imagePath': m.imagePath,
        },
    ],
  };

  Future<void> _upsertIndex(WaifuSession session) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final projects = await _readIndex();
    final next = <WaifuProject>[
      WaifuProject(
        folderRoot: session.folderRoot,
        title: session.title,
        coworker: session.coworker,
        touchedMs: now,
      ),
      for (final p in projects)
        if (p.folderRoot != session.folderRoot) p,
    ];
    await _writeIndex(next);
  }

  Future<void> _writeIndex(List<WaifuProject> projects) async {
    await Directory(directory).create(recursive: true);
    final list = [
      for (final p in projects)
        {
          'folderRoot': p.folderRoot,
          'title': p.title,
          'touchedMs': p.touchedMs,
          'coworker': _coworkerMap(p.coworker),
        },
    ];
    await _indexFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(list),
    );
  }

  Future<List<WaifuProject>> _readIndex() async {
    if (!await _indexFile.exists()) return const [];
    try {
      final decoded = jsonDecode(await _indexFile.readAsString());
      if (decoded is! List) return const [];
      final out = <WaifuProject>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final folder = e['folderRoot']?.toString() ?? '';
        if (folder.isEmpty) continue;
        final coworker = e['coworker'];
        out.add(
          WaifuProject(
            folderRoot: folder,
            title: e['title']?.toString() ?? '',
            coworker: coworker is Map
                ? _coworkerFrom(coworker)
                : CharacterCard(name: 'Coworker'),
            touchedMs: (e['touchedMs'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      out.sort((a, b) => b.touchedMs.compareTo(a.touchedMs));
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _migrateLastIntoIndex() async {
    if (await _indexFile.exists()) return;
    final last = await _readSessionFile(_lastFile);
    if (last == null) return;
    await _writeIndex([
      WaifuProject(
        folderRoot: last.folderRoot,
        title: last.title,
        coworker: last.coworker,
        touchedMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ]);
    await Directory(p.join(directory, 'sessions')).create(recursive: true);
    final sessionFile = _sessionFile(last.folderRoot);
    if (!await sessionFile.exists()) {
      await sessionFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_sessionMap(last)),
      );
    }
  }

  Future<WaifuSession?> _readSessionFile(File file) async {
    if (!await file.exists()) return null;
    try {
      final map = jsonDecode(await file.readAsString());
      if (map is! Map) return null;
      final coworker = map['coworker'];
      if (coworker is! Map) return null;
      final folder = map['folderRoot']?.toString() ?? '';
      if (folder.isEmpty) return null;
      final modeName = map['mode']?.toString() ?? 'build';
      final mode = WaifuMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => WaifuMode.build,
      );
      final pathModeName = map['pathMode']?.toString() ?? '';
      final pathMode = WaifuPathMode.values.firstWhere(
        (scope) => scope.name == pathModeName,
        orElse: () => WaifuPathMode.folderJail,
      );
      final transcript = <WaifuMessage>[];
      final raw = map['transcript'];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          transcript.add(
            WaifuMessage(
              isUser: e['isUser'] == true,
              text: e['text']?.toString() ?? '',
              reasoning: e['reasoning']?.toString() ?? '',
              imagePath: e['imagePath']?.toString(),
            ),
          );
        }
      }
      return WaifuSession(
        folderRoot: folder,
        coworker: _coworkerFrom(coworker),
        mode: mode,
        pathMode: pathMode,
        title: map['title']?.toString() ?? '',
        transcript: transcript,
        mcpOptIn: map['mcpOptIn'] == true,
        preserveThinking: map['preserveThinking'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}
