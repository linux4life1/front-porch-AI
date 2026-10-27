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

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story_narration_service.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// With TTS off every page would synthesize to nothing and the book would
/// flip through in silence. Say so instead (web reader does too).
Future<void> showVoiceOffDialog(BuildContext context) {
  return showWarmDialog<void>(
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
}

/// Read-along (page-by-page TTS narration): buffered stitched-audio
/// generation ahead of a playback loop that advances the reader page by
/// page. The owning page holds one and rebuilds through [run]'s `update`.
class StoryReadAlong {
  bool isReading = false;
  int bufferedPageCount = 0;

  // The ACTIVE page player, so stop() can reach it.
  AudioPlayer? _player;

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
      isCancelled: () => !isReading,
    );
  }

  /// Narrates from [currentPage] to the last of [flipCount] flip pages.
  /// The caller sets [isReading] before calling. [advancePage] turns to the
  /// next page; [update] wraps state changes the reader must rebuild for.
  Future<void> run({
    required TtsService tts,
    required List<StoryCastMember> cast,
    required int flipCount,
    required int Function() currentPage,
    required String Function(int flipPage) pageText,
    required VoidCallback advancePage,
    required bool Function() isMounted,
    required void Function(VoidCallback fn) update,
  }) async {
    const bufferDepth = 3; // How many pages ahead to pre-generate

    // Buffer: map of page index -> single stitched audio file
    final Map<int, File?> audioBuffer = {};
    bufferedPageCount = 0;

    // Background buffer filler — runs concurrently with playback
    int nextPageToBuffer = currentPage();
    bool bufferDone = false;

    Future<void> fillBuffer() async {
      while (isReading && !bufferDone) {
        if (nextPageToBuffer >= flipCount) {
          bufferDone = true;
          break;
        }
        // Only buffer ahead by bufferDepth from current playback position
        if (nextPageToBuffer - currentPage() >= bufferDepth) {
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }
        final pageIdx = nextPageToBuffer;
        nextPageToBuffer++;

        final text = pageText(pageIdx);
        if (text.trim().isEmpty) {
          audioBuffer[pageIdx] = null;
          continue;
        }

        final file = await _generatePageAudio(text, tts, cast);
        if (!isReading) break;
        audioBuffer[pageIdx] = file;
        if (isMounted()) {
          update(() {
            bufferedPageCount =
                audioBuffer.length - 1; // -1 for the page currently playing
          });
        }
      }
    }

    // Start the buffer filler concurrently
    final bufferFuture = fillBuffer();

    // Wait for the first page to be buffered
    while (!audioBuffer.containsKey(currentPage()) && isReading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Playback loop
    while (isReading && currentPage() < flipCount) {
      if (!audioBuffer.containsKey(currentPage())) {
        // Wait for buffer to catch up
        while (!audioBuffer.containsKey(currentPage()) && isReading) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        continue;
      }

      final audioFile = audioBuffer[currentPage()];
      if (audioFile != null &&
          audioFile.existsSync() /* io-ok: read-aloud loop, not build */ ) {
        final segPlayer = await AudioPlayback.create();
        // The reader checks AudioPlayback before starting; never null here
        // unless that check was skipped.
        if (segPlayer == null) break;
        // Publish the ACTIVE player so the stop button can reach it.
        // Field-reported bug: the player was declared and .stop()ed
        // but never assigned — stop only halted the buffer loop while the
        // current page kept playing to its natural end.
        _player = segPlayer;
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
          if (_player == segPlayer) _player = null;
          await segPlayer.dispose();
        }
      }

      if (!isReading) break;

      // Clean up played page from buffer to free memory
      audioBuffer.remove(currentPage());
      if (isMounted()) {
        update(() {
          bufferedPageCount = audioBuffer.length;
        });
      }

      // Advance to next page
      if (currentPage() < flipCount - 1) {
        advancePage();
        await Future.delayed(const Duration(milliseconds: 800));
      } else {
        break; // End of story
      }
    }

    bufferDone = true;
    await bufferFuture; // Clean up the buffer filler

    _player?.stop();
    if (isMounted()) update(() => isReading = false);
  }

  /// Halts the loop and silences the page now playing.
  void stop() {
    isReading = false;
    _player?.stop();
  }

  void dispose() {
    _player?.dispose();
  }
}
