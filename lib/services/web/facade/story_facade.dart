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
import 'dart:io';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/services/web/facade/story_snapshot_builder.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';
import 'package:front_porch_ai/services/web/facade/story/story_studio.dart';

/// Web adapter for Porch Stories. The generator ([StoryPipelineService]) and the
/// store ([StoryRepository]) are already fully headless, so this is a thin
/// driver: project CRUD, fire-and-forget pipeline stages with progress streamed
/// over the WebSocket hub, and export. No desktop code is reimplemented.
class StoryFacade {
  StoryFacade(
    this._repo,
    this._pipeline,
    this._hub, {
    StorySnapshotBuilder? snapshotBuilder,
    TtsService? tts,
    StorageService? storage,
    LLMProvider? llm,
    ImageGenService? imageGen,
  }) : _snapshotBuilder = snapshotBuilder,
       _tts = tts,
       _storage = storage,
       _llm = llm,
       _imageGen = imageGen;

  final StoryRepository _repo;
  StoryPipelineService _pipeline;
  final StreamHub? _hub;
  final StorySnapshotBuilder? _snapshotBuilder;
  final TtsService? _tts;
  final StorageService? _storage;
  final LLMProvider? _llm;
  final ImageGenService? _imageGen;

  bool _loaded = false;

  /// The pipeline a run started here is on, until it ends: after a backend
  /// switch its status and Stop still go to it, not to the new one.
  StoryPipelineService? _inFlight;

  /// The pipeline the app uses now: it makes a new one when the chat backend
  /// switches (a pipeline binds its backend when it is made).
  set pipeline(StoryPipelineService value) => _pipeline = value;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    await _repo.loadProjects();
    _loaded = true;
  }

  /// Library list (lightweight rows for the dashboard). Carries enough state for
  /// the card's genre/mood line, granular status, and tier badge so the client
  /// renders the same info the desktop home cards do.
  Future<List<Map<String, dynamic>>> list() async {
    await _ensureLoaded();
    return _repo.projects.map((p) {
      final sceneCount = p.scenes.values.fold<int>(
        0,
        (sum, s) => sum + s.length,
      );
      final proseCount = p.prose.values.where((b) => b.final_ != null).length;
      return {
        'id': p.dbId,
        'title': p.title,
        'concept': p.concept,
        'actCount': p.acts.length,
        'hasProse': p.prose.isNotEmpty,
        'updatedAt': p.updatedAt.toIso8601String(),
        'genre': p.style.genre,
        'mood': p.style.mood,
        'tier': p.promptTier.name,
        'engine': p.engineMode.name,
        'sceneCount': sceneCount,
        'proseCount': proseCount,
        'hasConcept': p.concept.trim().isNotEmpty,
        // The shelf (sketch H): one wording for desktop and web.
        'setupStep': p.setupStep,
        'wordCount': p.wordCount,
        'targetWords': p.targetWords,
        'genreLine': storyGenreLine(p),
        'worldName': p.worldName,
        'shelf': () {
          final st = storyShelfStatus(p);
          return {
            'status': st.status,
            'fraction': st.fraction,
            'done': st.done,
            'setup': st.setup,
          };
        }(),
      };
    }).toList();
  }

  /// The full project JSON (everything the editor/reader needs), or null.
  Future<Map<String, dynamic>?> get(String id) async {
    await _ensureLoaded();
    final p = _repo.getById(id);
    if (p == null) return null;
    return p.toJson()..['id'] = p.dbId;
  }

  Future<Map<String, dynamic>> create(String title) async {
    final p = await _repo.createProject(
      title: title.trim().isEmpty ? 'Untitled Story' : title.trim(),
    );
    _loaded = true; // createProject inserted into the in-memory list.
    return {'id': p.dbId, 'title': p.title};
  }

  /// Overwrite a project from the client's full JSON (bible/setup edits). The
  /// pipeline mutates the same in-memory reference, so reload to resync.
  ///
  /// `character_card_snapshots` are NOT trusted from the client — the web has no
  /// card text. When a snapshot builder is wired, they are reconstructed
  /// server-side from the selected character ids + an optional `character_roles`
  /// map (charDbId → role) + the user persona, so "seed from chats" and "include
  /// persona" actually carry card data into the pipeline.
  Future<bool> save(String id, Map<String, dynamic> json) async {
    await _ensureLoaded();
    final previous = _repo.getById(id);
    if (previous == null) return false;
    final updated = StoryProject.fromJson(json)..dbId = id;
    if (_snapshotBuilder != null) {
      final roles = <String, String>{};
      final raw = json['character_roles'];
      if (raw is Map) {
        raw.forEach((k, v) => roles[k.toString()] = v.toString());
      }
      // A story from a group chat: the members' cards come from the group's
      // own rows, so the client cannot write a member's text either.
      final groupId = updated.chatGroupId;
      updated.characterCardSnapshots = _snapshotBuilder.build(
        updated,
        requestRoles: roles,
        previous: previous,
        members: groupId == null
            ? const []
            : await _pipeline.groupRoster(groupId),
      );
    }
    await _repo.saveProject(updated);
    await _repo.loadProjects();
    return true;
  }

  /// Record the reader's page without touching the rest of the project — a
  /// full-project save from the reader would overwrite pipeline output or
  /// desktop edits made since the reader loaded. Same write as the desktop
  /// reader's page-flip.
  Future<bool> saveReadingPosition(
    String id,
    int? pageIndex, {
    String? mode,
    double? scroll,
  }) async {
    await _ensureLoaded();
    final project = _repo.getById(id);
    if (project == null) return false;
    if (pageIndex != null) {
      project.lastReadPageIndex = pageIndex < 0 ? 0 : pageIndex;
    }
    if (mode == 'book' || mode == 'scroll') project.readerMode = mode!;
    if (scroll != null) project.readerScroll = scroll.clamp(0.0, 1.0);
    await _repo.saveProject(project);
    return true;
  }

  Future<bool> delete(String id) async {
    await _ensureLoaded();
    if (_repo.getById(id) == null) return false;
    await _repo.deleteProject(id);
    return true;
  }

  /// Current pipeline progress (also pushed live over the hub during a run,
  /// from the pipeline the run started on, [of]).
  Map<String, dynamic> status([StoryPipelineService? of]) {
    final p = of ?? _inFlight ?? _pipeline;
    return {
      'running': p.isRunning,
      'stopping': p.stopRequested,
      'step': p.currentStep,
      'status': p.statusMessage,
      'tokens': p.tokenCount,
      // The beat being written streams in place on the Write screen. The
      // pipeline notifies every ~3 tokens, so this rides the same cadence.
      'streamingText': p.streamingText,
    };
  }

  /// Kick off one pipeline [stage] in the background. Progress streams as
  /// `story_status`; on completion `story_updated {id}` (or `story_error`) tells
  /// the client to refetch. Returns false synchronously only for an unknown
  /// project or stage / missing indices.
  Future<bool> runStage(
    String id,
    String stage, {
    int? actIndex,
    int? sceneIndex,
    int? beatIndex,
    Map<String, dynamic> args = const {},
  }) async {
    await _ensureLoaded();
    final p = _repo.getById(id);
    if (p == null) return false;
    final job = _dispatch(p, stage, actIndex, sceneIndex, beatIndex, args);
    if (job == null) return false;

    // Scope the progress listener to this job's lifetime so nothing leaks across
    // server restarts (the pipeline is a long-lived singleton; the hub is not).
    // The run reports from, and its listener comes off, the pipeline it
    // started on, even if the app has switched to a new one meanwhile.
    final pipeline = _inFlight = _pipeline;
    void onProgress() =>
        _hub?.broadcast({'event': 'story_status', ...status(pipeline)});
    pipeline.addListener(onProgress);
    unawaited(
      job
          .then((_) async {
            await _repo.loadProjects();
            _hub?.broadcast({'event': 'story_updated', 'id': id});
          })
          .catchError((Object e) {
            _hub?.broadcast({'event': 'story_error', 'id': id, 'error': '$e'});
          })
          .whenComplete(() {
            pipeline.removeListener(onProgress);
            if (identical(_inFlight, pipeline)) _inFlight = null;
          }),
    );
    return true;
  }

  Future<void>? _dispatch(
    StoryProject p,
    String stage,
    int? a,
    int? s,
    int? b,
    Map<String, dynamic> args,
  ) {
    String text(String key) => args[key]?.toString() ?? '';
    switch (stage) {
      case 'write-next':
        return _pipeline.writeNextScene(p);
      case 'plan-sequence':
        final n = args['sequence'];
        return n is int ? _pipeline.planSequenceScenes(p, n) : null;
      case 'rewrite-beat':
        return (a == null || s == null || b == null)
            ? null
            : _pipeline.rewriteBeat(p, a, s, b, directive: text('directive'));
      case 'interview':
        return text('name').isEmpty
            ? null
            : _pipeline.runCharacterInterview(p, text('name'));
      case 'director-plan':
        return text('directive').isEmpty
            ? null
            : _pipeline.runDirectorPlan(
                p,
                text('directive'),
                protectWrittenProse: args['protect'] != false,
                refinement: text('refinement'),
              );
      case 'director-apply':
        return _pipeline.applyDirectorPlan(p);
      case 'chat-distiller':
        return _pipeline.runChatDistiller(p);
      case 'story-architect':
        return _pipeline.runStoryArchitect(p);
      case 'story-arc':
        return _pipeline.runStoryArc(p);
      case 'act-structure':
        return _pipeline.runActStructurer(p);
      case 'scene-weaver':
        return a == null ? null : _pipeline.runSceneWeaver(p, a);
      case 'beat-director':
        return (a == null || s == null)
            ? null
            : _pipeline.runBeatDirector(p, a, s);
      case 'draft-edit':
        return (a == null || s == null || b == null)
            ? null
            : _pipeline.runDraftAndEdit(p, a, s, b);
      case 'auto-write-scene':
        return (a == null || s == null)
            ? null
            : _pipeline.autoWriteScene(p, a, s);
      case 'regenerate-scene':
        return (a == null || s == null)
            ? null
            : _pipeline.regenerateSceneProse(p, a, s);
      case 'full-act':
        return a == null ? null : _pipeline.generateFullAct(p, a);
      case 'autopilot':
        return _pipeline.runAutopilot(p);
      default:
        return null;
    }
  }

  /// Export the assembled prose as plain text or markdown.
  Future<String?> export(String id, String format) async {
    await _ensureLoaded();
    final p = _repo.getById(id);
    if (p == null) return null;
    return format == 'markdown'
        ? _pipeline.exportAsMarkdown(p)
        : _pipeline.exportAsText(p);
  }

  /// Preview the chat history that would seed a story (for the setup wizard).
  Future<List<String>> chatPreview(String id) async {
    await _ensureLoaded();
    final p = _repo.getById(id);
    if (p == null) return const [];
    return _pipeline.getChatPreviewMessages(p);
  }

  /// TTS voices for the per-character read-along voice picker — the same list the
  /// desktop binds in the bible dashboard. Empty when TTS isn't wired.
  List<Map<String, String>> voices() {
    final tts = _tts;
    if (tts == null) return const [];
    return tts.activeVoices
        .map((v) => {'id': v.id, 'name': v.name, 'engine': v.engine})
        .toList();
  }

  /// The chats a story can start from: the desktop picker's own list.
  Future<List<Map<String, dynamic>>> chatSources() async => [
    for (final row in await _pipeline.chatSources()) row.toJson(),
  ];

  /// What the PWA says about a story's world (`GET /api/stories/world`): by
  /// the place the story starts at, or by the chat it starts from (that
  /// chat's Setting). `ok: false` when there is no such place.
  Future<Map<String, dynamic>> worldSummary({
    String? place,
    String? session,
  }) async {
    var placeId = place?.trim() ?? '';
    if (placeId.isEmpty && session != null && session.trim().isNotEmpty) {
      placeId = await _pipeline.chatSettingId(session.trim()) ?? '';
    }
    final brief = _pipeline.worldBriefFor(placeId);
    return StoryWorldSummary.of(brief).toJson(brief);
  }

  /// Quick-concept archetype chips for the setup wizard (genre/style/concept
  /// seeds). Mirrors the desktop "Quick concepts" + Refresh.
  List<Map<String, String>> archetypes({int count = 6}) =>
      StoryPipelineService.generateArchetypes(count: count);

  // ── Studio (see [StoryStudio]) ───────────────────────────────────────────
  late final StoryStudio _studio = StoryStudio(
    _repo,
    pipeline: () => _pipeline,
    project: _project,
    imageGen: _imageGen,
    storage: _storage,
    llm: _llm,
  );

  /// Ask the running operation to stop at its next safe point.
  Map<String, dynamic> stop() {
    (_inFlight ?? _pipeline).requestStop();
    return status();
  }

  Future<StoryProject?> _project(String id) async {
    await _ensureLoaded();
    return _repo.getById(id);
  }

  Future<bool> directorAction(String id, int index, bool enabled) =>
      _studio.directorAction(id, index, enabled);
  Future<bool> directorProtect(String id, bool protect) =>
      _studio.directorProtect(id, protect);
  Future<bool> directorDiscard(String id) => _studio.directorDiscard(id);
  Future<bool> directorUndo(String id) => _studio.directorUndo(id);
  Future<bool> undoFix(String id, int act, int scene, int beat) =>
      _studio.undoFix(id, act, scene, beat);
  Future<int?> addLore(String id, String name, String text) =>
      _studio.addLore(id, name, text);
  Future<Map<String, dynamic>?> refreshWorld(String id) =>
      _studio.refreshWorld(id);
  Future<List<Map<String, dynamic>>?> searchLore(
    String id,
    String query, {
    int? act,
    int? scene,
  }) => _studio.searchLore(id, query, act: act, scene: scene);
  Future<bool> generatePortrait(String id, String name) =>
      _studio.generatePortrait(id, name);
  Future<File?> portraitFile(String id, String name) =>
      _studio.portraitFile(id, name);
  Future<List<Map<String, dynamic>>> runLog(String id) => _studio.runLog(id);
  Future<void> clearRunLog(String id) => _studio.clearRunLog(id);
  Map<String, dynamic> quality(String text, List<String> banned) =>
      _studio.quality(text, banned);
  List<Map<String, String>> lenses() => _studio.lenses();
  Map<String, dynamic> pacing(int targetWords) => _studio.pacing(targetWords);
  Map<String, dynamic> lanes() => _studio.lanes();
  String laneLabel(Map<String, dynamic> json) => _studio.laneLabel(json);
  Future<List<Map<String, String>>> hostModels(String type, String url) =>
      _studio.hostModels(type, url);
  Future<bool> rename(String id, String title) => _studio.rename(id, title);
  Future<void> saveHostKey(String type, String url, String key) =>
      _studio.saveHostKey(type, url, key);
}
