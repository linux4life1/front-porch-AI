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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/database/database.dart' hide StoryProject;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/services/story_pipeline/story_pipeline.dart';

/// The chat history a story is built on: which chats it can start from,
/// what the UI previews, and the canon block the stages read.
class StoryChatHistory {
  StoryChatHistory(this._ctx);

  final StoryPipelineContext _ctx;

  AppDatabase get _db => _ctx.db;

  /// Public method for the UI to preview what chat history will be imported.
  /// Always pulls full messages from the DB (not RAG embeddings which are windowed summaries).
  Future<List<String>> previewMessages(StoryProject project) async {
    if (!project.useChatHistory || project.chatHistoryCharacterIds.isEmpty) {
      return [];
    }
    final messages = <String>[];
    try {
      final resolvedIds = await resolveSessionCharacterIds(
        project.chatHistoryCharacterIds,
      );
      for (final charId in resolvedIds) {
        final sessions = await _db.getSessionsForCharacter(charId);
        for (final session in sessions) {
          // Living Time §4: same session scoping as the distiller and the raw
          // fallback in [context] (keep in sync — all
          // three are "the chat history" for a project, and a preview that
          // shows chats the story will never use is a lie).
          if (project.chatHistorySessionIds.isNotEmpty &&
              !project.chatHistorySessionIds.contains(session.id)) {
            continue;
          }
          final msgs = await _db.getMessagesForSession(session.id);
          for (final msg in msgs) {
            try {
              final swipes = jsonDecode(msg.swipes) as List;
              final text = swipes.isNotEmpty
                  ? swipes[msg.swipeIndex.clamp(0, swipes.length - 1)]
                  : '';
              if (text.toString().trim().isNotEmpty) {
                messages.add('${msg.sender}: $text');
              }
            } catch (_) {}
          }
          messages.add('--- (session break) ---');
        }
      }
    } catch (e) {
      debugPrint('[StoryPipeline] Chat preview error: $e');
    }
    return messages;
  }

  /// Resolve character IDs to actual session characterIds.
  /// The stored IDs might be embed-IDs, DB PKs, or filename-based IDs.
  /// This method cross-references by character name to find ALL session IDs.
  Future<Set<String>> resolveSessionCharacterIds(List<String> storedIds) async {
    final resolved = <String>{};
    resolved.addAll(storedIds);

    try {
      final allChars = await _db.select(_db.characters).get();
      final allSessions = await _db.select(_db.sessions).get();

      for (final storedId in storedIds) {
        // Find this character in the Characters table
        final matchingChar = allChars.where((c) => c.id == storedId);
        if (matchingChar.isEmpty) continue;

        final charName = matchingChar.first.name;

        // Find ALL sessions whose characterId maps to a character with the same name
        for (final sess in allSessions) {
          if (sess.characterId == null) continue;
          final sessChar = allChars.where((c) => c.id == sess.characterId);
          if (sessChar.isNotEmpty && sessChar.first.name == charName) {
            resolved.add(sess.characterId!);
          }
        }
      }
    } catch (e) {
      debugPrint('[StoryPipeline] ID resolution error: $e');
    }

    // Remove the original stored IDs if they don't match any sessions
    // (only keep IDs that actually have sessions)
    return resolved;
  }

  /// Get chat history context for characters.
  /// Uses the distilled timeline when available; falls back to raw messages.
  Future<String> context(StoryProject project) async {
    if (!project.useChatHistory || project.chatHistoryCharacterIds.isEmpty) {
      return '';
    }

    // Prefer the distilled timeline (structured, compressed, LLM-friendly)
    if (project.distilledTimeline.isNotEmpty) {
      debugPrint(
        '[StoryPipeline] Using distilled timeline (${project.distilledTimeline.length} chars)',
      );
      return '\n\n## CANON EVENT TIMELINE (distilled from character chat history)\n'
          'The following is a CHRONOLOGICAL TIMELINE of events extracted from actual conversations '
          'between the user and characters. These events are CANON -- they HAPPENED. The story MUST '
          'be built around this timeline. Each event represents a key plot point, revelation, emotional '
          'beat, or relationship development. The story is a novelization of these events:\n'
          '${project.distilledTimeline}\n';
    }

    // Fallback: raw messages (slower, noisier, but works if distillation hasn't run)
    debugPrint(
      '[StoryPipeline] No distilled timeline, falling back to raw messages',
    );
    try {
      final allMessages = <String>[];
      final resolvedIds = await resolveSessionCharacterIds(
        project.chatHistoryCharacterIds,
      );
      for (final charId in resolvedIds) {
        final sessions = await _db.getSessionsForCharacter(charId);
        if (sessions.isEmpty) continue;
        for (final session in sessions) {
          // Living Time §4: same session scoping as the distiller (keep in
          // sync — both are "the chat history" for a project).
          if (project.chatHistorySessionIds.isNotEmpty &&
              !project.chatHistorySessionIds.contains(session.id)) {
            continue;
          }
          final messages = await _db.getMessagesForSession(session.id);
          for (final msg in messages) {
            try {
              final swipes = jsonDecode(msg.swipes) as List;
              final text = swipes.isNotEmpty
                  ? swipes[msg.swipeIndex.clamp(0, swipes.length - 1)]
                  : '';
              if (text.toString().trim().isNotEmpty) {
                allMessages.add('${msg.sender}: $text');
              }
            } catch (_) {}
          }
          allMessages.add('---');
        }
      }

      if (allMessages.isEmpty) return '';
      final fullHistory = allMessages.join('\n');
      debugPrint(
        '[StoryPipeline] Loaded ${allMessages.length} raw messages as fallback',
      );
      return '\n\n## CANON CHAT HISTORY (raw messages)\n'
          'These events are CANON. The story MUST follow them:\n$fullHistory\n';
    } catch (e) {
      debugPrint('[StoryPipeline] Chat history error: $e');
      return '';
    }
  }

  /// Every 1:1 chat a story can start from, newest first. Chats where the
  /// user never wrote anything are left out: a greeting alone is no story.
  Future<List<StoryChatSourceRow>> chatSources() async {
    final names = {
      for (final c in await _db.select(_db.characters).get()) c.id: c.name,
    };
    final sessions = await _db.select(_db.sessions).get();
    final mine = sessions
        .where(
          (s) =>
              s.groupId == null &&
              s.deletedAt == null &&
              names.containsKey(s.characterId),
        )
        .toList();
    final ids = [for (final s in mine) s.id];
    final rows = <StoryChatSourceRow>[];
    // Batched: one SQL variable per id, and libraries run to thousands.
    const batch = 400;
    final stats = <String, ({int count, int userCount})>{};
    for (var i = 0; i < ids.length; i += batch) {
      final part = await _db.getSessionListStats(
        ids.sublist(i, (i + batch).clamp(0, ids.length)),
      );
      for (final e in part.entries) {
        stats[e.key] = (count: e.value.count, userCount: e.value.userCount);
      }
    }
    for (final s in mine) {
      final stat = stats[s.id];
      if (stat == null || stat.userCount == 0) continue;
      rows.add(
        StoryChatSourceRow(
          characterId: s.characterId!,
          characterName: names[s.characterId]!,
          sessionId: s.id,
          sessionName: s.name ?? '',
          summary: s.summary ?? '',
          createdAt: s.createdAt,
          messageCount: stat.count,
        ),
      );
    }
    rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows;
  }
}
