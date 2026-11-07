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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/database/database.dart' hide StoryProject;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/services/story_pipeline/story_pipeline.dart';
import 'package:front_porch_ai/services/story_stage_params.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The Chat Distiller (stage 0, both engines): the chat the story grew from
/// becomes a timeline of events.
class StoryChatDistiller {
  StoryChatDistiller(this._ctx, this._llm, this._history);

  final StoryPipelineContext _ctx;
  final StoryLlmCaller _llm;
  final StoryChatHistory _history;

  /// Stage 0: Chat Distiller — raw chat messages → structured event timeline.
  /// Loads all messages from DB, chunks them, and uses the LLM to extract
  /// a chronological timeline of plot-critical events. Result is stored on
  /// `project.distilledTimeline`.
  Future<void> run(StoryProject project) async {
    if (!project.useChatHistory || project.chatHistoryCharacterIds.isEmpty) {
      return;
    }

    _ctx.running = true;
    _ctx.setStatus('Chat Distiller', 'Loading chat messages...');

    try {
      // 1. Load all raw messages from DB. Living Time §4: session-scoped
      // ("turn THIS chat into a story"); an empty session list keeps the
      // historical all-sessions behaviour. A group chat's lines are named
      // by each message's speaker id (StoryChatLines).
      final resolvedIds = await _history.resolveSessionCharacterIds(
        project.chatHistoryCharacterIds,
      );
      debugPrint(
        '[StoryPipeline] Resolved ${project.chatHistoryCharacterIds} -> $resolvedIds',
      );
      final loaded = await _history.lines.load(project, resolvedIds);
      final lines = loaded.lines;
      final sessionIds = loaded.sessionIds;
      final userName = loaded.userName;
      final castSentence = loaded.castSentence();
      debugPrint(
        '[StoryPipeline] ${sessionIds.length} sessions, ${lines.length} '
        'messages, speakers ${loaded.speakers}',
      );

      if (lines.isEmpty) {
        debugPrint('[StoryPipeline] No messages to distill');
        _ctx.running = false;
        _ctx.notify();
        return;
      }

      final memory = await _loadChatMemory(lines, sessionIds, userName);
      debugPrint('[StoryPipeline] Distilling ${lines.length} messages...');

      // 2. Chunk messages into groups of ~50
      const chunkSize = 50;
      final chunks = <List<String>>[];
      for (int i = 0; i < lines.length; i += chunkSize) {
        chunks.add([
          for (final l in lines.sublist(
            i,
            (i + chunkSize).clamp(0, lines.length),
          ))
            l.text,
        ]);
      }

      // 3. Distill each chunk
      final chunkTimelines = <String>[];
      for (int i = 0; i < chunks.length; i++) {
        _ctx.setStatus(
          'Chat Distiller',
          'Distilling chunk ${i + 1}/${chunks.length} (${lines.length} messages total)...',
        );
        final chunkText = chunks[i].join('\n');
        final notes = memory.chunkNotes(
          i * chunkSize,
          i * chunkSize + chunks[i].length,
        );

        final prompt =
            '''You are a story analyst. Read the following conversation${loaded.isGroup ? '' : ' between a user and an AI character'} and extract a CHRONOLOGICAL TIMELINE of plot-significant events.
$castSentence

For each event, write a single concise entry in this format:
[EVENT N] Description of what happened, who was involved, the emotional tone, and any revelations or relationship changes.

RULES:
- Extract ONLY plot-critical events: key actions, decisions, revelations, emotional turning points, relationship changes, conflicts, and resolutions.
- IGNORE: greetings, filler, out-of-character (OOC) discussion, meta-conversation, and small talk.
- Maintain CHRONOLOGICAL ORDER as they appear in the conversation.
- Be SPECIFIC: include character names, locations, and details that matter for storytelling.
- Capture the character's personality, speech patterns, and emotional states.
- Note any world-building details (places, factions, lore, rules of the world).
- Record ONLY what the messages${notes.isEmpty ? '' : ' or the notes below'} show. Do not invent events, and do not carry the story past where the conversation stops.

${notes}CONVERSATION CHUNK (messages ${i * chunkSize + 1}-${(i * chunkSize) + chunks[i].length} of ${lines.length}):
$chunkText

Extract the timeline now. Output ONLY the timeline entries, nothing else.''';

        final response = await _llm.callLLM(
          prompt,
          maxLength: 4096,
          stage: StoryStageParams.distill,
          project: project,
          label: 'Chat Distiller',
        );
        final cleaned = StoryJson.stripThinkTags(response).trim();
        if (cleaned.isNotEmpty) {
          chunkTimelines.add(cleaned);
        }
      }

      // 4. If multiple chunks, do a final merge pass
      String finalTimeline;
      if (chunkTimelines.length > 1) {
        _ctx.setStatus(
          'Chat Distiller',
          'Merging ${chunkTimelines.length} timeline chunks...',
        );
        final mergePrompt =
            '''You are a story analyst. Below are timeline chunks extracted from different parts of a long conversation. Merge them into a SINGLE CHRONOLOGICAL TIMELINE.

Remove any duplicate events and keep every other event: do not drop, shorten away, or add events. Maintain chronological order. Keep the [EVENT N] format and renumber sequentially.

${chunkTimelines.asMap().entries.map((e) => '--- CHUNK ${e.key + 1} ---\n${e.value}').join('\n\n')}

Output the merged, deduplicated, chronologically ordered timeline. Output ONLY the timeline entries.''';

        final mergeResponse = await _llm.callLLM(
          mergePrompt,
          maxLength: 8192,
          stage: StoryStageParams.distillMerge,
          project: project,
          label: 'Chat Distiller (merge)',
        );
        finalTimeline = StoryJson.stripThinkTags(mergeResponse).trim();
      } else {
        finalTimeline = chunkTimelines.isNotEmpty ? chunkTimelines.first : '';
      }

      // 5. Store on project. The closing notes ride on the timeline so every
      // stage that reads canon sees them, and so does the overview card.
      final closing = memory.closingNotes();
      if (finalTimeline.isNotEmpty && closing.isNotEmpty) {
        finalTimeline = '$finalTimeline\n\n$closing';
      }
      project.distilledTimeline = finalTimeline;
      await _ctx.repository.saveProject(project);

      final eventCount = RegExp(
        r'\[EVENT \d+\]',
      ).allMatches(finalTimeline).length;
      debugPrint(
        '[StoryPipeline] Distilled ${lines.length} messages into $eventCount events',
      );
      _ctx.setStatus(
        'Chat Distiller',
        'Distilled $eventCount events from ${lines.length} messages!',
      );
    } catch (e) {
      _ctx.setStatus('Chat Distiller', 'Error: $e');
      rethrow;
    } finally {
      _ctx.running = false;
      _ctx.notify();
    }
  }

  /// The Journal cards and Growth Rings of the distilled chats, placed
  /// against [lines]. Strictly those sessions — neither table crosses
  /// chats. A failure here costs the notes, not the distill.
  Future<StoryChatMemory> _loadChatMemory(
    List<DistillLine> lines,
    List<String> sessionIds,
    String userName,
  ) async {
    final cards = <JournalMemoryData>[];
    final rings = <GrowthRingData>[];
    final names = <String, String>{};
    try {
      // Both tables key their owner by stableGroupId, not characters.id.
      for (final c in await _ctx.db.select(_ctx.db.characters).get()) {
        names[stableGroupIdFrom(c.imagePath, c.name)] = c.name;
      }
      for (final id in sessionIds) {
        cards.addAll(await _ctx.db.getJournalCardsForSession(id));
        rings.addAll(await _ctx.db.getGrowthRingsForSession(id));
      }
    } catch (e) {
      debugPrint('[StoryPipeline] Journal / Growth Rings load failed: $e');
    }
    debugPrint(
      '[StoryPipeline] Chat memory: ${cards.length} journal cards, '
      '${rings.length} growth rings',
    );
    return StoryChatMemory.place(
      lines: lines,
      cards: cards,
      rings: rings,
      names: names,
      userName: userName,
    );
  }
}
