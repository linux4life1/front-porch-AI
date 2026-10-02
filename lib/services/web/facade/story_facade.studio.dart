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

part of 'story_facade.dart';

/// Studio additions to the web adapter: Stop, the Director, continuity-fix
/// undo, lore uploads and search, the run log, and the read-only helpers
/// the Engine step and the writer's chips need (quality, lenses, pacing,
/// lane labels). The PWA computes nothing of this itself.
extension StoryFacadeStudio on StoryFacade {
  /// Ask the running operation to stop at its next safe point.
  Map<String, dynamic> stop() {
    _pipeline.requestStop();
    return status();
  }

  Future<StoryProject?> _project(String id) async {
    await _ensureLoaded();
    return _repo.getById(id);
  }

  Future<bool> directorAction(String id, int index, bool enabled) async {
    final p = await _project(id);
    if (p == null) return false;
    await _pipeline.setDirectorActionEnabled(p, index, enabled);
    return true;
  }

  Future<bool> directorProtect(String id, bool protect) async {
    final p = await _project(id);
    if (p == null) return false;
    await _pipeline.setDirectorProtection(p, protect);
    return true;
  }

  Future<bool> directorDiscard(String id) async {
    final p = await _project(id);
    if (p == null) return false;
    await _pipeline.discardDirectorPlan(p);
    return true;
  }

  /// False when there is no snapshot to go back to.
  Future<bool> directorUndo(String id) async {
    final p = await _project(id);
    if (p == null) return false;
    return _pipeline.undoDirectorPlan(p);
  }

  Future<bool> undoFix(String id, int act, int scene, int beat) async {
    final p = await _project(id);
    if (p == null) return false;
    await _pipeline.undoContinuityFix(p, act, scene, beat);
    return true;
  }

  /// Add an uploaded text file to the story's lore; returns entries added.
  Future<int?> addLore(String id, String name, String text) async {
    final p = await _project(id);
    if (p == null) return null;
    return _pipeline.addLoreDocument(p, name, text);
  }

  Future<List<Map<String, dynamic>>?> searchLore(
    String id,
    String query, {
    int? act,
    int? scene,
  }) async {
    final p = await _project(id);
    if (p == null) return null;
    final hits = await _pipeline.searchLore(p, query, act: act, index: scene);
    return [
      for (final h in hits)
        {
          'score': h.score,
          'topic': h.entry.topic,
          'detail': h.entry.detail,
          'semantic': _pipeline.loreSearchIsSemantic,
        },
    ];
  }

  /// Paint a portrait for [name] with the image engine and keep it on the
  /// cast member. Throws a plain-language error when nothing can paint.
  Future<bool> generatePortrait(String id, String name) async {
    final p = await _project(id);
    final member = p?.castByName(name);
    if (p == null || member == null) return false;
    final igs = _imageGen;
    if (igs == null || !igs.isConfigured) {
      throw StateError(
        'Image generation isn\'t set up. Pick an image engine under '
        'Settings → Images first.',
      );
    }
    final bytes = await igs.generateImage(
      prompt: StoryPipelineStudioBible.portraitPrompt(p, member),
      isPortrait: true,
    );
    final path = await igs.saveAvatarToDisk(bytes, characterName: member.name);
    if (path == null) throw StateError('The image could not be saved.');
    member.portrait = path;
    await _repo.saveProject(p);
    return true;
  }

  /// The portrait file a cast member's `portrait` path points at, if any.
  Future<File?> portraitFile(String id, String name) async {
    final p = await _project(id);
    final path = p?.castByName(name)?.portrait;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    return await file.exists() ? file : null;
  }

  Future<List<Map<String, dynamic>>> runLog(String id) async {
    final entries = await _pipeline.store.entries(id);
    return [for (final e in entries) e.toJson()];
  }

  Future<void> clearRunLog(String id) => _pipeline.store.clearLog(id);

  /// Quality chips for a passage, same numbers the desktop writer shows.
  Map<String, dynamic> quality(String text, List<String> banned) =>
      StoryQuality.analyze(text, bannedPhrases: banned).toJson();

  /// Built-in narrative lenses with their glyphs.
  List<Map<String, String>> lenses() => [
    for (final l in StoryLenses.builtIn)
      {
        'id': l.id,
        'name': l.name,
        'context': l.context,
        'glyph': StoryLenses.glyph(l.id),
      },
  ];

  /// The scene/beat budget a target length produces.
  Map<String, dynamic> pacing(int targetWords) {
    final p = StoryPacing.forTarget(targetWords);
    return {
      'summary': p.summary,
      'scenes_min': p.scenesMin,
      'scenes_max': p.scenesMax,
      'beats_min': p.beatsMin,
      'beats_max': p.beatsMax,
      'words_per_beat': StoryPacing.wordsPerBeat,
    };
  }

  /// "Main model · …" / "Worker model · …" for the Engine step.
  Map<String, String?> lanes() {
    final storage = _storage;
    final llm = _llm;
    if (storage == null || llm == null) {
      return {'main': 'Main model', 'worker': null};
    }
    final labels = storyLaneLabelsFor(storage, llm);
    return {'main': labels.main, 'worker': labels.worker};
  }
}
