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

/// LLM transport: lanes, the one model call every stage funnels through,
/// and the native tool call. A public-named extension, like the other
/// parts, so story pages and the web facade keep calling it unchanged (the
/// ChatService-parts precedent: a library-private extension would be
/// invisible to importing libraries). Stage 0 (chat context + distiller)
/// is the distill part.
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
    StoryToolSpec? tool,
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
    String text;
    var viaTool = false;
    try {
      await _swapLaneHost(lane.host);
      final hold = lane.hold;
      // Tools first for a structured stage; the tag prompt is the backup.
      final toolText = tool == null || !_toolsWelcome(service)
          ? null
          : await (hold == null
                ? _callTool(service, params, tool)
                : hold<String?>(() => _callTool(service, params, tool)));
      if (toolText != null) {
        text = toolText;
        viaTool = true;
      } else {
        text = hold == null ? await stream() : await hold<String>(stream);
      }
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
        note: viaTool ? 'tool call' : '',
      ),
    );
  }

  /// One native tool call. Null means the host refused the tool (or sent
  /// nothing usable), and the caller falls back to the tag prompt; a refusal
  /// is remembered per host so the run stops asking. Transport failures
  /// (nothing listening, timeouts) throw like any other call.
  Future<String?> _callTool(
    LLMService service,
    GenerationParams params,
    StoryToolSpec tool,
  ) async {
    final resp = await service.generateWithTools(
      GenerationParams(
        prompt: params.prompt,
        maxLength: params.maxLength,
        temperature: params.temperature,
        topP: params.topP,
        minP: params.minP,
        repeatPenalty: params.repeatPenalty,
        toolChoice: tool.name,
      ),
      StoryTools.definitions,
    );
    if (resp == null) {
      _toolsRefused.add(_serviceIdentity(service));
      return null;
    }
    final call = resp.calls.where((c) => c.name == tool.name).firstOrNull;
    if (call == null) {
      // The model answered in prose instead; let the tag path read it if
      // it carries tags, else retry as text.
      final text = resp.text.trim();
      if (text.isNotEmpty && StoryXml.has(text, 'response')) {
        _tokenCount = resp.completionTokens ?? _tokenCount;
        return text;
      }
      return null;
    }
    _tokenCount = resp.completionTokens ?? _tokenCount;
    final text = StoryTools.toTags(tool, call.arguments);
    _streamingText = text;
    _notify();
    return text;
  }

  bool _toolsWelcome(LLMService service) =>
      !_toolsRefused.contains(_serviceIdentity(service));

  String _serviceIdentity(LLMService service) =>
      '${service.backendName}|${service.runtimeType}|${identityHashCode(service)}';

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
    StoryToolSpec? tool,
  }) async {
    final result = await _call(
      prompt,
      maxLength: maxLength,
      stage: stage,
      project: project,
      role: role,
      label: label,
      tool: tool,
    );
    await _log(project, result.entry);
    return result.text;
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
