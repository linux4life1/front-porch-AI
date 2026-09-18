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

part of 'tts_service.dart';

/// Piper in-process helpers, audio file utilities, and text sanitization —
/// shared support code for the speak/streaming pipelines. Extracted
/// verbatim from tts_service.dart, zero behaviour change.
extension TtsServiceSupport on TtsService {
  // ---- Piper (in-process sherpa vits) ----

  /// Makes sure the sherpa re-export for [voice] is on disk (downloading it
  /// on first use). Returns false — with [_lastError] set and the failure
  /// tallied — when the voice can't be played: there is no legacy piper
  /// binary anymore, so a voice with no sherpa export (e.g. a hand-made
  /// custom voice) simply cannot speak.
  Future<bool> _ensurePiperVoice(String voice) async {
    final root = _storageService.rootPath;
    if (root == null) return false;
    try {
      final ok = await SherpaPiperEngine.ensureVoice(root, voice);
      if (!ok) {
        _lastError =
            'The voice "$voice" has no engine model on this machine. '
            'Official voices re-download from the Voice Model Browser; a '
            'custom voice can be re-imported there via "Add custom voice".';
        EngineHealth.instance.reportFailure(
          EngineHealth.piper,
          'no sherpa export for "$voice"',
          expected: true,
        );
      }
      return ok;
    } catch (e) {
      _lastError = 'Piper voice download failed: $e';
      EngineHealth.instance.reportFailure(
        EngineHealth.piper,
        'voice download failed: $e',
      );
      return false;
    }
  }

  /// Generates one chunk of [text] with the in-process sherpa engine.
  /// Callers run [_ensurePiperVoice] first (once per utterance).
  Future<File?> _piperGenerateWav(
    String voice,
    String text,
    int index,
    double speed,
  ) async {
    try {
      final wav = await _piperNative.generate(
        root: _storageService.rootPath!,
        voiceKey: voice,
        text: text,
        speed: speed,
        outputPath: p.join(
          Directory.systemTemp.path,
          'piper_tts_${DateTime.now().millisecondsSinceEpoch}_$index.wav',
        ),
      );
      EngineHealth.instance.reportNative(EngineHealth.piper);
      return wav;
    } catch (e) {
      print('[TTS-Native] piper generation failed: $e');
      EngineHealth.instance.reportFailure(
        EngineHealth.piper,
        'generation failed: $e',
      );
      return null;
    }
  }

  // ---- Audio utilities ----

  void _cleanupFiles(List<File> files) {
    for (final file in files) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }

  /// Delete the cached audio file and reset cache state.
  void _clearCache() {
    if (_cachedWav != null) {
      try {
        _cachedWav!.deleteSync();
      } catch (_) {}
      _cachedWav = null;
    }
    _cachedMessageId = null;
    _cachedTextHash = null;
    _cachedVoice = null;
    _cachedEngine = null;
  }

  /// Play a WAV file.
  /// On macOS, uses the built-in `afplay` command for reliability
  /// (audioplayers has platform channel bugs on macOS).
  /// On other platforms, uses the audioplayers plugin.
  Future<void> _playWavFile(File wavFile) async {
    if (Platform.isMacOS) {
      // Use macOS built-in afplay for reliable playback
      try {
        _afplayProcess = await Process.start('afplay', [wavFile.path]);
        final exitCode = await _afplayProcess!.exitCode;
        _afplayProcess = null;
        if (exitCode != 0) {
          print('afplay exited with code $exitCode');
        }
      } catch (e) {
        _afplayProcess = null;
        print('afplay failed: $e');
      }
    } else {
      final completer = Completer<void>();
      void finish() {
        if (!completer.isCompleted) completer.complete();
      }

      final sub = _audioPlayer.onPlayerComplete.listen((_) => finish());
      // Manual stop() emits PlayerState.stopped, NOT onPlayerComplete — so
      // without this second listener, hanging up (or pressing Stop) mid-
      // sentence leaves this await hanging forever on Windows/Linux: the
      // caller's loop never returns, its temp WAVs are never cleaned up, and
      // the orphaned subscription fires into the NEXT session. macOS never
      // sees it because that platform plays through afplay above. Same guard
      // as the read-along player in story_reader_page.readalong.dart.
      final stopSub = _audioPlayer.onPlayerStateChanged.listen((state) {
        if (state == PlayerState.stopped) finish();
      });

      try {
        await _audioPlayer.play(DeviceFileSource(wavFile.path));
        await completer.future;
      } finally {
        await sub.cancel();
        await stopSub.cancel();
      }
    }
  }

  // ---- Text processing ----

  /// Sanitize text for TTS: apply narration filters, remove think tags, markdown, emotes, OOC, etc.
  String _sanitizeText(String text) {
    var result = text;

    // ── Replace curly quotation marks with straight ones (must run before narration filters) ──
    if (_storageService.ttsSettings.ttsReplaceCurlyQuotes) {
      result = result
          .replaceAll('\u201C', '"')
          .replaceAll('\u201D', '"')
          .replaceAll('\u2018', "'")
          .replaceAll('\u2019', "'");
    }

    // ── Narration filters (SillyTavern-style) ──
    // Step 1: If ignoreAsterisks, remove all *...* blocks (including content inside them)
    if (_storageService.ttsSettings.ttsIgnoreAsterisks) {
      // Handle multi-line action blocks: *action across\nmultiple lines*
      result = result.replaceAll(RegExp(r'\*[^*]+\*', dotAll: true), ' ');
    }
    // Step 2: If narrateQuotedOnly, extract only text within quotes (straight or curly)
    if (_storageService.ttsSettings.ttsNarrateQuotedOnly) {
      // Robust extraction for spoken dialogue in "..." or “...” (curly quotes)
      // We deliberately avoid single quotes here because they are too ambiguous with apostrophes.
      final quotePattern = RegExp(r'["“]([^"”]+)["”]', dotAll: true);
      final matches = quotePattern.allMatches(result);
      final extracted = matches
          .map((m) => m.group(1)?.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      result = extracted.isNotEmpty ? extracted.join('. ') : '';
    }

    // ── Standard cleanup ──
    // Reasoning-tag debris (paired/unclosed/orphan-close) must never be
    // spoken — Kokoro tokenizes stray tags as prose.
    result = stripThinkTags(result);
    result = result.replaceAll(
      RegExp(r'\(OOC:.*?\)', caseSensitive: false),
      '',
    );
    result = result.replaceAll(
      RegExp(r'\[OOC:.*?\]', caseSensitive: false),
      '',
    );
    result = result.replaceAll(RegExp(r'\*'), '');
    result = result.replaceAll(RegExp(r'#{1,6}\s'), '');
    result = result.replaceAll(RegExp(r'[_~`]'), '');
    result = result.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^\)]+\)'),
      (m) => m[1]!,
    );
    result = result.replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '');
    result = result.replaceAll(RegExp(r':[a-zA-Z0-9_]+:'), '');
    // Remove emojis (fpai-feature-004)
    result = result.replaceAll(
      RegExp(
        r'[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA6F}]',
        unicode: true,
      ),
      '',
    );
    result = result.replaceAll(RegExp(r'\s+'), ' ');

    return result.trim();
  }

  /// Split text into sentences for progress tracking.
  List<String> _splitSentences(String text) {
    final sentences = <String>[];
    final parts = text.split(RegExp(r'(?<=[.!?])\s+'));
    for (final part in parts) {
      if (part.trim().isEmpty) continue;
      if (sentences.isNotEmpty && sentences.last.length < 20) {
        sentences.last = '${sentences.last} ${part.trim()}';
      } else {
        sentences.add(part.trim());
      }
    }
    if (sentences.isEmpty && text.trim().isNotEmpty) {
      sentences.add(text.trim());
    }
    return sentences;
  }
}
