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

import 'package:front_porch_ai/models/story_project.dart';
import 'package:front_porch_ai/services/audiobook_generator_service.dart';
import 'package:front_porch_ai/services/epub_generator_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/story_narration_service.dart';
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// Host-bound Porch Stories artifacts: EPUB ebook, stitched-TTS audiobook, and
/// per-scene "read to me" narration. These wrap the *existing* desktop generator
/// services ([EpubGeneratorService], [AudiobookGeneratorService],
/// [StoryNarrationService]) and stream/serve the result to the browser — there
/// is no client-side synthesis.
///
/// Security: every artifact is keyed off a validated project [id]; the browser
/// never supplies a file path or free narration text. The audiobook download
/// serves only the temp file this facade generated (asserted to live under the
/// system temp dir), and read-to-me only speaks the story's own prose selected
/// by bounds-checked act/scene indices.
class StoryExportFacade {
  StoryExportFacade(this._repo, this._tts, this._storage, this._hub)
    : _audiobookService = AudiobookGeneratorService(_tts, _storage) {
    _audiobookService.addListener(_onAudiobookProgress);
  }

  final StoryRepository _repo;
  final TtsService _tts;
  final StorageService _storage;
  final StreamHub? _hub;
  final AudiobookGeneratorService _audiobookService;

  bool _loaded = false;

  /// Finished audiobook temp files, keyed by project id. Only files in here are
  /// servable; each is deleted before a regeneration overwrites it.
  final Map<String, File> _audiobooks = {};

  /// Which project the in-flight audiobook belongs to (for status reporting).
  String? _generatingId;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    await _repo.loadProjects();
    _loaded = true;
  }

  // ── eBook (.epub) ──────────────────────────────────────────────────────────

  /// Generate the EPUB bytes for [id], or null for an unknown story / empty book.
  Future<List<int>?> epub(String id) async {
    await _ensureLoaded();
    final p = _repo.getById(id);
    if (p == null) return null;
    final book = await EpubGeneratorService.generateEpub(p);
    return book?.bytes;
  }

  // ── Audiobook (.wav) ────────────────────────────────────────────────────────

  /// Whether the *server* can produce audio at all (TTS enabled).
  bool get ttsAvailable => _storage.ttsEnabled;

  /// Kick off audiobook compilation for [id] in the background. Returns false
  /// for an unknown story, TTS off, or a compile already running. Progress is
  /// pushed over the hub as `story_audiobook_status`; completion as
  /// `story_audiobook_ready {id}` (or `story_audiobook_error {id, error}`).
  Future<bool> startAudiobook(String id) async {
    await _ensureLoaded();
    final p = _repo.getById(id);
    if (p == null || !_storage.ttsEnabled) return false;
    if (_audiobookService.isGenerating) return false;

    _generatingId = id;
    // Drop any prior artifact for this project so a stale download can't leak.
    await _disposeAudiobook(id);

    unawaited(() async {
      try {
        final book = await _audiobookService.generateAudiobook(p);
        if (book != null) {
          _audiobooks[id] = book.file;
          _hub?.broadcast({'event': 'story_audiobook_ready', 'id': id});
        } else {
          _hub?.broadcast({
            'event': 'story_audiobook_error',
            'id': id,
            'error': _audiobookService.status,
          });
        }
      } catch (e) {
        _hub?.broadcast({
          'event': 'story_audiobook_error',
          'id': id,
          'error': '$e',
        });
      } finally {
        _generatingId = null;
      }
    }());
    return true;
  }

  /// Live audiobook compilation status (also pushed over the hub).
  Map<String, dynamic> audiobookStatus() => {
    'generating': _audiobookService.isGenerating,
    'progress': _audiobookService.progress,
    'status': _audiobookService.status,
    'id': _generatingId,
    'ready': _generatingId == null,
  };

  /// The finished audiobook WAV for [id], or null if not generated yet. Asserts
  /// the file lives under the system temp dir (defense against a path swap).
  File? audiobookFile(String id) {
    final f = _audiobooks[id];
    if (f == null || !f.existsSync()) return null;
    if (!_isUnderSystemTemp(f)) return null;
    return f;
  }

  /// Abort an in-flight audiobook compile.
  void cancelAudiobook() => _audiobookService.stop();

  // ── Read to me (per-scene narration) ────────────────────────────────────────

  /// Synthesize one scene's prose to a stitched WAV using per-character voices.
  /// The prose is reconstructed server-side from validated [actIndex]/[sceneIndex]
  /// — the client never supplies the text to synthesize. Returns null for an
  /// unknown story, out-of-range indices, TTS off, or an empty/unwritten scene.
  Future<File?> narrateScene(String id, int actIndex, int sceneIndex) async {
    await _ensureLoaded();
    if (!_storage.ttsEnabled) return null;
    final p = _repo.getById(id);
    if (p == null) return null;
    if (actIndex < 0 || actIndex >= p.acts.length) return null;
    final scenes = p.scenes[actIndex] ?? const [];
    if (sceneIndex < 0 || sceneIndex >= scenes.length) return null;

    final text = _sceneProse(p, actIndex, sceneIndex);
    if (text.trim().isEmpty) return null;
    return StoryNarrationService.synthesizeStitchedWav(text, p.cast, _tts);
  }

  // ── internals ───────────────────────────────────────────────────────────────

  /// Assemble a scene's written prose (final → draft) in beat order.
  String _sceneProse(StoryProject p, int actIndex, int sceneIndex) {
    final beats = p.beats['$actIndex-$sceneIndex'] ?? const [];
    final buffer = StringBuffer();
    for (int b = 0; b < beats.length; b++) {
      final prose = p.prose['$actIndex-$sceneIndex-$b'];
      final text = prose?.final_ ?? prose?.draft ?? '';
      if (text.trim().isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write('\n\n');
        buffer.write(text);
      }
    }
    return buffer.toString();
  }

  void _onAudiobookProgress() {
    _hub?.broadcast({
      'event': 'story_audiobook_status',
      'id': _generatingId,
      'generating': _audiobookService.isGenerating,
      'progress': _audiobookService.progress,
      'status': _audiobookService.status,
    });
  }

  Future<void> _disposeAudiobook(String id) async {
    final old = _audiobooks.remove(id);
    if (old != null && old.existsSync() && _isUnderSystemTemp(old)) {
      try {
        await old.delete();
      } catch (_) {}
    }
  }

  bool _isUnderSystemTemp(File f) =>
      f.absolute.path.startsWith(Directory.systemTemp.absolute.path);
}
