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

part of 'story_pipeline_service.dart';

/// LLM transport, chat-history context assembly, and the Chat Distiller
/// stage. Extracted verbatim from `story_pipeline_service.dart` (Cluster E
/// of the god-file split) as a public-named extension so story pages and the
/// web facade — which call `runChatDistiller` — keep working unchanged (the
/// ChatService-parts precedent: a library-private extension would be
/// invisible to importing libraries).
extension StoryPipelineLlm on StoryPipelineService {
  /// Which service a [role] runs on for [project], and how to hold the GPU
  /// for it. The worker lane is used only when the story asks for it and a
  /// worker is actually live; a host lane the story picked itself is used
  /// when it can be built. The last retry of a planning job ([escalate])
  /// always goes to the chat model.
  _Lane _laneFor(
    StoryProject? project,
    StoryRole role, {
    bool escalate = false,
  }) {
    final chat = _Lane(_llmService, hold: null, host: null);
    if (project == null || escalate) return chat;
    final wanted = switch (role) {
      StoryRole.planning => project.planningLane,
      StoryRole.prose => project.proseLane,
      StoryRole.review => project.reviewLane,
    };
    switch (wanted.lane) {
      case StoryModelLane.main:
        return chat;
      case StoryModelLane.worker:
        final worker = _lanes?.worker();
        if (worker != null && worker.isReady) {
          return _Lane(worker, hold: _lanes!.hold, host: null);
        }
        return chat;
      case StoryModelLane.host:
        final host = _lanes?.host(wanted);
        if (host == null) return chat;
        return _Lane(host.service, hold: host.hold, host: host);
    }
  }

  /// A local lane model that is not the one about to run is put back
  /// first, so two local engines never fight for the GPU.
  Future<void> _swapLaneHost(LaneHost? next) async {
    final prev = _activeLaneHost;
    if (prev != null && !identical(prev, next)) {
      await prev.restore();
    }
    _activeLaneHost = next;
  }

  /// Called when a run ends: put the chat model back.
  Future<void> restoreLaneHosts() async {
    final prev = _activeLaneHost;
    _activeLaneHost = null;
    if (prev != null) await prev.restore();
  }

  /// One model call: streams tokens to `_streamingText` for the UI and
  /// returns the text with an unsaved run-log entry for it.
  ///
  /// Every story stage funnels through here, so this is also where backend
  /// availability is enforced: the story pages and the web client surface
  /// pipeline errors verbatim, and a raw SocketException ("The remote computer
  /// refused the network connection" on Windows) tells users nothing. Guard
  /// up-front and translate connection failures into a plain-language
  /// [LlmUnavailableException] instead.
  Future<({String text, StoryRunEntry entry})> _call(
    String prompt, {
    int maxLength = 4096,
    StoryStageParams stage = StoryStageParams.planning,
    StoryProject? project,
    StoryRole role = StoryRole.planning,
    String label = '',
    int attempt = 1,
    bool escalate = false,
  }) async {
    if (_stopRequested) throw StoryStoppedException();
    final lane = _laneFor(project, role, escalate: escalate);
    final service = lane.service;
    if (!service.isReady) {
      throw LlmUnavailableException(
        'The AI backend (${service.backendName}) isn\'t ready. Stories '
        'use the same AI engine as chat — start it and load a model in '
        'Settings (or set up your remote API), then try again.',
      );
    }

    // Prepend an anti-thinking instruction for reasoning models
    final fullPrompt =
        'Do NOT use <think> tags or chain-of-thought reasoning. Respond directly.\n\n$prompt';

    final params = GenerationParams(
      prompt: fullPrompt,
      maxLength: maxLength,
      temperature: stage.temperature,
      topP: stage.topP,
      minP: stage.minP,
      repeatPenalty: stage.repeatPenalty,
    );

    _streamingText = '';
    _tokenCount = 0;
    _notify();

    Future<String> stream() async {
      final buffer = StringBuffer();
      int notifyCounter = 0;
      await for (final token in service.generateStream(params)) {
        buffer.write(token);
        _streamingText = buffer.toString();
        _tokenCount++;
        notifyCounter++;
        // Throttle UI updates to every 3 tokens to avoid jank
        if (notifyCounter >= 3) {
          notifyCounter = 0;
          _notify();
        }
      }
      return buffer.toString();
    }

    final started = DateTime.now();
    final String text;
    try {
      await _swapLaneHost(lane.host);
      final hold = lane.hold;
      text = hold == null ? await stream() : await hold<String>(stream);
    } catch (e) {
      // Stop aborts the HTTP client, which surfaces here as a socket error.
      if (_stopRequested) throw StoryStoppedException();
      if (looksLikeBackendUnreachable(e)) {
        throw LlmUnavailableException(
          'Couldn\'t reach the AI backend (${service.backendName}) — '
          'nothing answered at its address, or it stopped responding '
          'mid-generation. Make sure the engine is running with a model '
          'loaded (stories use the same AI backend as chat), then try again.',
        );
      }
      rethrow;
    }
    if (_stopRequested) throw StoryStoppedException();
    // Final update
    _streamingText = text;
    _notify();
    return (
      text: text,
      entry: StoryRunEntry(
        at: started,
        stage: label,
        role: role.name,
        backend: service.backendName,
        attempt: attempt,
        millis: DateTime.now().difference(started).inMilliseconds,
        tokens: _tokenCount,
        prompt: prompt,
        response: text,
      ),
    );
  }

  Future<void> _log(StoryProject? project, StoryRunEntry entry) async {
    final id = project?.dbId;
    if (id != null) await store.add(id, entry);
  }

  /// [_call] for stages with no gate: the call is logged as it stands.
  Future<String> _callLLM(
    String prompt, {
    int maxLength = 4096,
    StoryStageParams stage = StoryStageParams.planning,
    StoryProject? project,
    StoryRole role = StoryRole.planning,
    String label = '',
  }) async {
    final result = await _call(
      prompt,
      maxLength: maxLength,
      stage: stage,
      project: project,
      role: role,
      label: label,
    );
    await _log(project, result.entry);
    return result.text;
  }

  /// Get chat history context for characters.
  /// Uses the distilled timeline when available; falls back to raw messages.
  Future<String> _getChatHistoryContext(StoryProject project) async {
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
      final resolvedIds = await _resolveSessionCharacterIds(
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

  // ── CHAT DISTILLER ─────────────────────────────────────────────

  /// Stage 0: Chat Distiller — raw chat messages → structured event timeline.
  /// Loads all messages from DB, chunks them, and uses the LLM to extract
  /// a chronological timeline of plot-critical events. Result is stored on
  /// `project.distilledTimeline`.
  Future<void> _chatDistiller(StoryProject project) async {
    if (!project.useChatHistory || project.chatHistoryCharacterIds.isEmpty) {
      return;
    }

    _isRunning = true;
    _setStatus('Chat Distiller', 'Loading chat messages...');

    try {
      // 1. Load all raw messages from DB
      final allMessages = <String>[];
      final resolvedIds = await _resolveSessionCharacterIds(
        project.chatHistoryCharacterIds,
      );
      debugPrint(
        '[StoryPipeline] Resolved ${project.chatHistoryCharacterIds} -> $resolvedIds',
      );

      for (final charId in resolvedIds) {
        final sessions = await _db.getSessionsForCharacter(charId);
        debugPrint(
          '[StoryPipeline] Found ${sessions.length} sessions for "$charId"',
        );
        for (final session in sessions) {
          // Living Time §4: session-scoped distill ("turn THIS chat into a
          // story") — empty list keeps the historical all-sessions behavior.
          if (project.chatHistorySessionIds.isNotEmpty &&
              !project.chatHistorySessionIds.contains(session.id)) {
            continue;
          }
          final msgs = await _db.getMessagesForSession(session.id);
          debugPrint(
            '[StoryPipeline] Session ${session.id}: ${msgs.length} messages',
          );
          for (final msg in msgs) {
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
        }
      }

      if (allMessages.isEmpty) {
        debugPrint('[StoryPipeline] No messages to distill');
        _isRunning = false;
        _notify();
        return;
      }

      debugPrint(
        '[StoryPipeline] Distilling ${allMessages.length} messages...',
      );

      // 2. Chunk messages into groups of ~50
      const chunkSize = 50;
      final chunks = <List<String>>[];
      for (int i = 0; i < allMessages.length; i += chunkSize) {
        chunks.add(
          allMessages.sublist(i, (i + chunkSize).clamp(0, allMessages.length)),
        );
      }

      // 3. Distill each chunk
      final chunkTimelines = <String>[];
      for (int i = 0; i < chunks.length; i++) {
        _setStatus(
          'Chat Distiller',
          'Distilling chunk ${i + 1}/${chunks.length} (${allMessages.length} messages total)...',
        );
        final chunkText = chunks[i].join('\n');

        final prompt =
            '''You are a story analyst. Read the following conversation between a user and an AI character and extract a CHRONOLOGICAL TIMELINE of plot-significant events.

For each event, write a single concise entry in this format:
[EVENT N] Description of what happened, who was involved, the emotional tone, and any revelations or relationship changes.

RULES:
- Extract ONLY plot-critical events: key actions, decisions, revelations, emotional turning points, relationship changes, conflicts, and resolutions.
- IGNORE: greetings, filler, out-of-character (OOC) discussion, meta-conversation, and small talk.
- Maintain CHRONOLOGICAL ORDER as they appear in the conversation.
- Be SPECIFIC: include character names, locations, and details that matter for storytelling.
- Capture the character's personality, speech patterns, and emotional states.
- Note any world-building details (places, factions, lore, rules of the world).

CONVERSATION CHUNK (messages ${i * chunkSize + 1}-${(i * chunkSize) + chunks[i].length} of ${allMessages.length}):
$chunkText

Extract the timeline now. Output ONLY the timeline entries, nothing else.''';

        final response = await _callLLM(
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
        _setStatus(
          'Chat Distiller',
          'Merging ${chunkTimelines.length} timeline chunks...',
        );
        final mergePrompt =
            '''You are a story analyst. Below are timeline chunks extracted from different parts of a long conversation. Merge them into a SINGLE CHRONOLOGICAL TIMELINE.

Remove any duplicate events. Maintain chronological order. Keep the [EVENT N] format and renumber sequentially.

${chunkTimelines.asMap().entries.map((e) => '--- CHUNK ${e.key + 1} ---\n${e.value}').join('\n\n')}

Output the merged, deduplicated, chronologically ordered timeline. Output ONLY the timeline entries.''';

        final mergeResponse = await _callLLM(
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

      // 5. Store on project
      project.distilledTimeline = finalTimeline;
      await _repository.saveProject(project);

      final eventCount = RegExp(
        r'\[EVENT \d+\]',
      ).allMatches(finalTimeline).length;
      debugPrint(
        '[StoryPipeline] Distilled ${allMessages.length} messages into $eventCount events',
      );
      _setStatus(
        'Chat Distiller',
        'Distilled $eventCount events from ${allMessages.length} messages!',
      );
    } catch (e) {
      _setStatus('Chat Distiller', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  }
}

/// A resolved lane: the service, an optional GPU hold, and the host it came
/// from (null for the chat model and the worker).
class _Lane {
  const _Lane(this.service, {required this.hold, required this.host});
  final LLMService service;
  final Future<T> Function<T>(Future<T> Function() work)? hold;
  final LaneHost? host;
}
