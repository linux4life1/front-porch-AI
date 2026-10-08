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

part of 'story_reader_page.dart';

/// Read-along (page-by-page TTS narration) for [_StoryReaderPageState]:
/// per-page text extraction, buffered stitched-audio generation/playback,
/// and the AppBar action that surfaces it. Extracted from the inline
/// build()/state methods; direct state access preserves behavior.
/// AppColors + warm-porch accents, except the buffer-pill status colors
/// (marked `theme-keep: status` below) which must stay semantically
/// green-vs-orange regardless of app theme.
extension _StoryReaderReadAlong on _StoryReaderPageState {
  /// Get the text content for a given flip-page index.
  String _getPageText(int flipPage) {
    if (_pages == null) return '';
    final width = MediaQuery.of(context).size.width;
    final isTwoPageSpread = width > 800;

    if (isTwoPageSpread) {
      final leftIdx = flipPage * 2;
      final rightIdx = leftIdx + 1;
      final buf = StringBuffer();
      if (leftIdx < _pages!.length) {
        buf.write('${_pages![leftIdx].title}. ${_pages![leftIdx].body}\n\n');
      }
      if (rightIdx < _pages!.length) {
        buf.write('${_pages![rightIdx].title}. ${_pages![rightIdx].body}');
      }
      return buf.toString();
    } else {
      if (flipPage < _pages!.length) {
        return '${_pages![flipPage].title}. ${_pages![flipPage].body}';
      }
      return '';
    }
  }

  /// Generate audio for a page, using per-character voices for dialogue
  /// segments, stitched into one WAV. Delegates to the shared
  /// [StoryNarrationService] (the same engine the web read-to-me uses).
  Future<File?> _generatePageAudio(
    String pageText,
    TtsService tts,
    List<StoryCastMember> cast,
  ) {
    return StoryNarrationService.synthesizeStitchedWav(
      pageText,
      cast,
      tts,
      isCancelled: () => !_isReadingAlong,
    );
  }

  Future<void> _startReadAlong() async {
    if (_isReadingAlong || _pages == null) return;
    final tts = Provider.of<TtsService>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    if (!storage.ttsSettings.ttsEnabled) {
      // With TTS off every page would synthesize to nothing and the book
      // would flip through in silence. Say so instead (web reader does too).
      await showWarmDialog<void>(
        context,
        title: 'Voice is off',
        icon: Icons.volume_off_outlined,
        content: const Text(
          'Reading aloud needs the voice engine. Turn it on under '
          'Settings → Voice & Media → Text-to-Speech, then tap Read to me '
          'again.',
        ),
        actions: [warmDialogCancel(context, label: 'OK')],
      );
      return;
    }
    rebuildState(() => _isReadingAlong = true);

    final repo = Provider.of<StoryRepository>(context, listen: false);
    final project = repo.getById(widget.projectId);
    final cast = project?.cast ?? [];

    final flipCount = _getFlipPageCount();
    const bufferDepth = 3; // How many pages ahead to pre-generate

    // Buffer: map of page index -> single stitched audio file
    final Map<int, File?> audioBuffer = {};
    _bufferedPageCount = 0;

    // Background buffer filler — runs concurrently with playback
    int nextPageToBuffer = _currentPage;
    bool bufferDone = false;

    Future<void> fillBuffer() async {
      while (_isReadingAlong && !bufferDone) {
        if (nextPageToBuffer >= flipCount) {
          bufferDone = true;
          break;
        }
        // Only buffer ahead by bufferDepth from current playback position
        if (nextPageToBuffer - _currentPage >= bufferDepth) {
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }
        final pageIdx = nextPageToBuffer;
        nextPageToBuffer++;

        final text = _getPageText(pageIdx);
        if (text.trim().isEmpty) {
          audioBuffer[pageIdx] = null;
          continue;
        }

        final file = await _generatePageAudio(text, tts, cast);
        if (!_isReadingAlong) break;
        audioBuffer[pageIdx] = file;
        if (mounted) {
          rebuildState(() {
            _bufferedPageCount =
                audioBuffer.length - 1; // -1 for the page currently playing
          });
        }
      }
    }

    // Start the buffer filler concurrently
    final bufferFuture = fillBuffer();

    // Wait for the first page to be buffered
    while (!audioBuffer.containsKey(_currentPage) && _isReadingAlong) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Playback loop
    while (_isReadingAlong && _currentPage < flipCount) {
      if (!audioBuffer.containsKey(_currentPage)) {
        // Wait for buffer to catch up
        while (!audioBuffer.containsKey(_currentPage) && _isReadingAlong) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        continue;
      }

      final audioFile = audioBuffer[_currentPage];
      if (audioFile != null && audioFile.existsSync()) {
        final segPlayer = AudioPlayer();
        // Publish the ACTIVE player so the stop button can reach it.
        // Field-reported bug: _readAlongPlayer was declared and .stop()ed
        // but never assigned — stop only halted the buffer loop while the
        // current page kept playing to its natural end.
        _readAlongPlayer = segPlayer;
        final completer = Completer<void>();
        final sub = segPlayer.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) completer.complete();
        });
        // Manual stop() emits PlayerState.stopped, NOT onPlayerComplete —
        // without this listener the loop would hang on the completer even
        // after the audio was silenced.
        final stopSub = segPlayer.onPlayerStateChanged.listen((state) {
          if (state == PlayerState.stopped && !completer.isCompleted) {
            completer.complete();
          }
        });

        try {
          await segPlayer.play(DeviceFileSource(audioFile.path));
          await completer.future;
        } catch (e) {
          debugPrint('[ReadAlong] Playback error: $e');
        } finally {
          await sub.cancel();
          await stopSub.cancel();
          if (_readAlongPlayer == segPlayer) _readAlongPlayer = null;
          await segPlayer.dispose();
        }
      }

      if (!_isReadingAlong) break;

      // Clean up played page from buffer to free memory
      audioBuffer.remove(_currentPage);
      if (mounted) {
        rebuildState(() {
          _bufferedPageCount = audioBuffer.length;
        });
      }

      // Advance to next page
      if (_currentPage < flipCount - 1) {
        // In scroll mode there is no flip widget to advance the page.
        if (_flipKey.currentState != null) {
          _flipKey.currentState!.nextPage();
        } else {
          rebuildState(() => _currentPage++);
        }
        await Future.delayed(const Duration(milliseconds: 800));
      } else {
        break; // End of story
      }
    }

    bufferDone = true;
    await bufferFuture; // Clean up the buffer filler

    _readAlongPlayer?.stop();
    if (mounted) rebuildState(() => _isReadingAlong = false);
  }

  void _stopReadAlong() {
    _isReadingAlong = false;
    _readAlongPlayer?.stop();
    Provider.of<TtsService>(context, listen: false).stop();
    rebuildState(() {});
  }

  /// The AppBar "Read to me" / in-progress / Stop action. Extracted from the
  /// inline `Consumer<TtsService>` in build()'s AppBar actions so the shell
  /// build() and this file both stay under the line cap.
}
