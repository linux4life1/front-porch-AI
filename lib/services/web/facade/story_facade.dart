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

import 'package:front_porch_ai/models/story_project.dart';
import 'package:front_porch_ai/services/story_pipeline_service.dart';
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/web/facade/story_snapshot_builder.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

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
  }) : _snapshotBuilder = snapshotBuilder,
       _tts = tts;

  final StoryRepository _repo;
  final StoryPipelineService _pipeline;
  final StreamHub? _hub;
  final StorySnapshotBuilder? _snapshotBuilder;
  final TtsService? _tts;

  bool _loaded = false;

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
        'sceneCount': sceneCount,
        'proseCount': proseCount,
        'hasConcept': p.concept.trim().isNotEmpty,
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
      updated.characterCardSnapshots = _snapshotBuilder.build(
        updated,
        requestRoles: roles,
        previous: previous,
      );
    }
    await _repo.saveProject(updated);
    await _repo.loadProjects();
    return true;
  }

  Future<bool> delete(String id) async {
    await _ensureLoaded();
    if (_repo.getById(id) == null) return false;
    await _repo.deleteProject(id);
    return true;
  }

  /// Current pipeline progress (also pushed live over the hub during a run).
  Map<String, dynamic> status() => {
    'running': _pipeline.isRunning,
    'step': _pipeline.currentStep,
    'status': _pipeline.statusMessage,
    'tokens': _pipeline.tokenCount,
  };

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
  }) async {
    await _ensureLoaded();
    final p = _repo.getById(id);
    if (p == null) return false;
    final job = _dispatch(p, stage, actIndex, sceneIndex, beatIndex);
    if (job == null) return false;

    // Scope the progress listener to this job's lifetime so nothing leaks across
    // server restarts (the pipeline is a long-lived singleton; the hub is not).
    void onProgress() =>
        _hub?.broadcast({'event': 'story_status', ...status()});
    _pipeline.addListener(onProgress);
    unawaited(
      job
          .then((_) async {
            await _repo.loadProjects();
            _hub?.broadcast({'event': 'story_updated', 'id': id});
          })
          .catchError((Object e) {
            _hub?.broadcast({'event': 'story_error', 'id': id, 'error': '$e'});
          })
          .whenComplete(() => _pipeline.removeListener(onProgress)),
    );
    return true;
  }

  Future<void>? _dispatch(
    StoryProject p,
    String stage,
    int? a,
    int? s,
    int? b,
  ) {
    switch (stage) {
      case 'chat-distiller':
        return _pipeline.runChatDistiller(p);
      case 'story-architect':
        return _pipeline.runStoryArchitect(p);
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

  /// Quick-concept archetype chips for the setup wizard (genre/style/concept
  /// seeds). Mirrors the desktop "Quick concepts" + Refresh.
  List<Map<String, String>> archetypes({int count = 6}) =>
      StoryPipelineService.generateArchetypes(count: count);
}
