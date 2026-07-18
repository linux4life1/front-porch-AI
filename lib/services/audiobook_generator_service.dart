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
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/models/story_project.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/wav_utils.dart';

class FormattedAudiobook {
  final StoryProject project;
  final File file;
  final String format;

  FormattedAudiobook({
    required this.project,
    required this.file,
    required this.format,
  });
}

/// A background compiler that utilizes Kokoro parallel batching to build an audiobook.
/// Stitches WAV chunks using pure Dart — zero external dependencies, zero user setup.
class AudiobookGeneratorService extends ChangeNotifier {
  final TtsService _ttsService;
  final StorageService _storageService;

  bool _isGenerating = false;
  double _progress = 0.0;
  String _status = '';

  bool get isGenerating => _isGenerating;
  double get progress => _progress;
  String get status => _status;

  AudiobookGeneratorService(this._ttsService, this._storageService);

  /// Stop compilation mid-way (aborts loop)
  void stop() {
    if (_isGenerating) {
      _isGenerating = false;
      _status = 'Aborted.';
      notifyListeners();
    }
  }

  /// Builds the full novel into a downloadable `.wav` audio file.
  /// Uses pure Dart WAV concatenation — no ffmpeg or external tools required.
  Future<FormattedAudiobook?> generateAudiobook(StoryProject project) async {
    if (_isGenerating || !_storageService.ttsSettings.ttsEnabled) return null;

    _isGenerating = true;
    _progress = 0.0;
    _status = 'Preparing structured story beats...';
    notifyListeners();

    final compiledAudioParts = <File>[];

    // 1. Gather all prose blocks sequentially
    final sequentialTexts = <String>[];

    // Standard book title sequence
    sequentialTexts.add("${project.title}. A story by Front Porch A I.");
    if (project.cast.isNotEmpty) {
      sequentialTexts.add(
        "Starring ${project.cast.map((c) => c.name).join(', ')}.",
      );
    }

    // Traverse the acts and scenes
    for (int actIdx = 0; actIdx < project.acts.length; actIdx++) {
      final act = project.acts[actIdx];
      sequentialTexts.add("Act ${act.number}. ${act.title}.");

      final scenes = project.scenes[actIdx] ?? [];
      for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
        final beats = project.beats['$actIdx-$sceneIdx'] ?? [];
        for (int beatIdx = 0; beatIdx < beats.length; beatIdx++) {
          final beatProse = project.prose['$actIdx-$sceneIdx-$beatIdx'];
          if (beatProse != null) {
            final text = beatProse.final_ ?? beatProse.draft ?? '';
            if (text.trim().isNotEmpty) {
              sequentialTexts.add(text);
            }
          }
        }
      }
    }

    if (sequentialTexts.isEmpty) {
      _status = 'No prose to generate.';
      _isGenerating = false;
      notifyListeners();
      return null;
    }

    try {
      // 2. Loop and generate TTS chunks to temporary WAV files
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < sequentialTexts.length; i++) {
        if (!_isGenerating) throw Exception('Generation aborted by user.');

        // Calculate ETA from average time per block
        String eta = '';
        if (i > 0) {
          final avgMs = stopwatch.elapsedMilliseconds / i;
          final remainingMs = (avgMs * (sequentialTexts.length - i)).round();
          eta = ' • ~${_formatDuration(remainingMs)} remaining';
        }

        _status =
            'Synthesizing block ${i + 1} of ${sequentialTexts.length}...$eta';
        _progress = (i / sequentialTexts.length) * 0.85;
        notifyListeners();

        final wavPart = await _ttsService.generateAudioFile(sequentialTexts[i]);
        if (wavPart != null && wavPart.existsSync()) {
          compiledAudioParts.add(wavPart);
        }
      }

      if (compiledAudioParts.isEmpty) {
        throw Exception('No audio files generated.');
      }

      // 3. Stitch WAV files using pure Dart — zero external tools!
      _status = 'Stitching ${compiledAudioParts.length} audio segments...';
      _progress = 0.90;
      notifyListeners();

      // Shared, pure-Dart concatenation (same path the TTS/read-along use).
      final stitched = await WavUtils.concatenateWavFiles(compiledAudioParts);
      if (stitched == null) {
        throw Exception('Failed to stitch audio segments.');
      }
      // Give the file a recognizable, title-stamped name for the save dialog.
      // Sanitize the title to a safe slug so it can never escape the temp dir
      // (the web server is internet-exposable and the title is user-supplied).
      final slug = project.title
          .replaceAll(RegExp(r'[^\w.-]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      final outputWav = await stitched.rename(
        p.join(
          Directory.systemTemp.path,
          'audiobook_${slug.isEmpty ? 'story' : slug}_${DateTime.now().millisecondsSinceEpoch}.wav',
        ),
      );

      _progress = 1.0;
      _status = 'Audiobook generation complete!';
      _isGenerating = false;
      notifyListeners();

      // Cleanup temp parts
      _cleanupParts(compiledAudioParts);

      return FormattedAudiobook(
        project: project,
        file: outputWav,
        format: 'wav',
      );
    } catch (e) {
      print('Audiobook Generator Error: $e');
      _status = 'Error: $e';
      _isGenerating = false;
      notifyListeners();
      _cleanupParts(compiledAudioParts);
      return null;
    }
  }

  void _cleanupParts(List<File> parts) {
    for (final f in parts) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  String _formatDuration(int ms) {
    final seconds = (ms / 1000).round();
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes < 60) return '${minutes}m ${secs}s';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m';
  }
}
