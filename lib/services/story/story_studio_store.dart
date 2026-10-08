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

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// One model call made on behalf of a story.
class StoryRunEntry {
  final DateTime at;
  final String stage;

  /// 'planning', 'prose' or 'review'.
  final String role;
  final String backend;

  /// The model that answered, when the backend names one.
  final String model;
  final int attempt;

  /// '' (no gate), 'PASS', 'FAIL', 'INVALID' or 'ERROR'.
  String verdict;
  String note;
  final int millis;
  final int tokens;
  final String prompt;
  final String response;

  StoryRunEntry({
    DateTime? at,
    required this.stage,
    required this.role,
    this.backend = '',
    this.model = '',
    this.attempt = 1,
    this.verdict = '',
    this.note = '',
    this.millis = 0,
    this.tokens = 0,
    this.prompt = '',
    this.response = '',
  }) : at = at ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'stage': stage,
    'role': role,
    'backend': backend,
    if (model.isNotEmpty) 'model': model,
    'attempt': attempt,
    'verdict': verdict,
    'note': note,
    'millis': millis,
    'tokens': tokens,
    'prompt': prompt,
    'response': response,
  };

  factory StoryRunEntry.fromJson(Map<String, dynamic> json) => StoryRunEntry(
    at: DateTime.tryParse(json['at']?.toString() ?? ''),
    stage: json['stage']?.toString() ?? '',
    role: json['role']?.toString() ?? '',
    backend: json['backend']?.toString() ?? '',
    model: json['model']?.toString() ?? '',
    attempt: (json['attempt'] as num?)?.toInt() ?? 1,
    verdict: json['verdict']?.toString() ?? '',
    note: json['note']?.toString() ?? '',
    millis: (json['millis'] as num?)?.toInt() ?? 0,
    tokens: (json['tokens'] as num?)?.toInt() ?? 0,
    prompt: json['prompt']?.toString() ?? '',
    response: json['response']?.toString() ?? '',
  );
}

/// Per-story side files that do not belong in the project blob: the run log
/// (every model call, for when a story goes wrong) and the Director's undo
/// snapshot. Both would bloat a blob that is rewritten after every beat.
///
/// With no directory (tests, or storage not ready) everything still works in
/// memory for the life of the process.
class StoryStudioStore {
  StoryStudioStore({this.directory});

  /// Resolved on every use: the storage root can move while the app runs.
  final Directory? Function()? directory;

  static const maxEntries = 300;
  static const maxFieldChars = 16000;

  final Map<String, List<StoryRunEntry>> _logs = {};
  final Map<String, String> _undo = {};

  File? _file(String projectId, String name) {
    final root = directory?.call();
    if (root == null || projectId.isEmpty) return null;
    return File(path.join(root.path, projectId, name));
  }

  static String _clip(String text) => text.length <= maxFieldChars
      ? text
      : '${text.substring(0, maxFieldChars)}\n… (${text.length - maxFieldChars} more characters)';

  Future<List<StoryRunEntry>> entries(String projectId) async {
    final cached = _logs[projectId];
    if (cached != null) return List.unmodifiable(cached);
    final loaded = <StoryRunEntry>[];
    final file = _file(projectId, 'runlog.jsonl');
    try {
      if (file != null && await file.exists()) {
        for (final line in await file.readAsLines()) {
          if (line.trim().isEmpty) continue;
          try {
            loaded.add(
              StoryRunEntry.fromJson(jsonDecode(line) as Map<String, dynamic>),
            );
          } on FormatException {
            // A torn last line from a crash mid-append; skip it.
          }
        }
      }
    } catch (e) {
      debugPrint('[StoryStudioStore] run log read failed: $e');
    }
    _logs[projectId] = loaded;
    return List.unmodifiable(loaded);
  }

  Future<void> add(String projectId, StoryRunEntry entry) async {
    if (projectId.isEmpty) return;
    final list = _logs[projectId] ?? [...await entries(projectId)];
    _logs[projectId] = list;
    final stored = StoryRunEntry(
      at: entry.at,
      stage: entry.stage,
      role: entry.role,
      backend: entry.backend,
      attempt: entry.attempt,
      verdict: entry.verdict,
      note: entry.note,
      millis: entry.millis,
      tokens: entry.tokens,
      prompt: _clip(entry.prompt),
      response: _clip(entry.response),
    );
    list.add(stored);
    final file = _file(projectId, 'runlog.jsonl');
    try {
      if (list.length > maxEntries) {
        list.removeRange(0, list.length - maxEntries);
        if (file != null) {
          await file.parent.create(recursive: true);
          await file.writeAsString(
            '${list.map((e) => jsonEncode(e.toJson())).join('\n')}\n',
          );
        }
      } else if (file != null) {
        await file.parent.create(recursive: true);
        await file.writeAsString(
          '${jsonEncode(stored.toJson())}\n',
          mode: FileMode.append,
        );
      }
    } catch (e) {
      debugPrint('[StoryStudioStore] run log write failed: $e');
    }
  }

  Future<void> clearLog(String projectId) async {
    _logs[projectId] = [];
    try {
      final file = _file(projectId, 'runlog.jsonl');
      if (file != null && await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[StoryStudioStore] run log clear failed: $e');
    }
  }

  /// Keep [projectJson] as the state the next Undo returns to.
  Future<void> saveUndo(String projectId, String projectJson) async {
    _undo[projectId] = projectJson;
    try {
      final file = _file(projectId, 'director_undo.json');
      if (file != null) {
        await file.parent.create(recursive: true);
        await file.writeAsString(projectJson);
      }
    } catch (e) {
      debugPrint('[StoryStudioStore] undo snapshot write failed: $e');
    }
  }

  Future<String?> readUndo(String projectId) async {
    final cached = _undo[projectId];
    if (cached != null) return cached;
    try {
      final file = _file(projectId, 'director_undo.json');
      if (file != null && await file.exists()) return await file.readAsString();
    } catch (e) {
      debugPrint('[StoryStudioStore] undo snapshot read failed: $e');
    }
    return null;
  }

  Future<void> clearUndo(String projectId) async {
    _undo.remove(projectId);
    try {
      final file = _file(projectId, 'director_undo.json');
      if (file != null && await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[StoryStudioStore] undo snapshot clear failed: $e');
    }
  }

  /// Remove every side file for a deleted story.
  Future<void> deleteProject(String projectId) async {
    _logs.remove(projectId);
    _undo.remove(projectId);
    try {
      final root = directory?.call();
      if (root == null || projectId.isEmpty) return;
      final dir = Directory(path.join(root.path, projectId));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('[StoryStudioStore] side-file cleanup failed: $e');
    }
  }
}
