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

import 'dart:io';

import 'package:front_porch_ai/models/story_project.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/utils/wav_utils.dart';

/// One chunk of read-along text tagged with the voice that should speak it.
/// Narration carries a null [voiceKey] (the default narrator voice); dialogue
/// carries the matched cast member's TTS voice + name.
class StoryVoiceSegment {
  final String text;
  final String? voiceKey;
  final String? characterName;

  const StoryVoiceSegment({
    required this.text,
    this.voiceKey,
    this.characterName,
  });
}

/// Shared "read to me" narration engine for Porch Stories. Splits prose into
/// narration vs. per-character dialogue and synthesizes a single stitched WAV.
///
/// This is the single source of truth used by BOTH the desktop reader's
/// auto-advancing read-along AND the web `/api/stories/<id>/narrate` endpoint, so
/// the spoken output is identical across platforms. All WAV stitching goes
/// through [WavUtils] — there is no second concatenation copy.
class StoryNarrationService {
  const StoryNarrationService._();

  /// Parse [text] into ordered narration/dialogue segments, identifying the
  /// speaker for each quoted line by scanning ~100 chars before / ~60 chars
  /// after the quote for a voiced cast member's first name.
  static List<StoryVoiceSegment> parseVoiceSegments(
    String text,
    List<StoryCastMember> cast,
  ) {
    final segments = <StoryVoiceSegment>[];
    // Match quoted dialogue using straight or curly double quotes.
    final dialoguePattern = RegExp(r'["“”]([^"“”]+)["“”]');
    int lastEnd = 0;

    for (final match in dialoguePattern.allMatches(text)) {
      // Narration before this dialogue.
      if (match.start > lastEnd) {
        final narration = text.substring(lastEnd, match.start).trim();
        if (narration.isNotEmpty) {
          segments.add(StoryVoiceSegment(text: narration));
        }
      }

      // Find the speaker by name in the surrounding context.
      final searchStart = (match.start - 100).clamp(0, text.length);
      final searchEnd = (match.end + 60).clamp(0, text.length);
      final context = text.substring(searchStart, searchEnd).toLowerCase();

      String? matchedVoice;
      String? matchedName;
      for (final c in cast) {
        final voice = c.voiceModel;
        if (voice != null && voice.isNotEmpty) {
          final firstName = c.name.split(' ').first.toLowerCase();
          if (firstName.isNotEmpty && context.contains(firstName)) {
            matchedVoice = voice;
            matchedName = c.name;
            break;
          }
        }
      }

      segments.add(
        StoryVoiceSegment(
          text: match.group(1) ?? '',
          voiceKey: matchedVoice,
          characterName: matchedName,
        ),
      );
      lastEnd = match.end;
    }

    // Trailing narration.
    if (lastEnd < text.length) {
      final remaining = text.substring(lastEnd).trim();
      if (remaining.isNotEmpty) {
        segments.add(StoryVoiceSegment(text: remaining));
      }
    }

    // No dialogue found: speak the whole thing as one narration segment.
    if (segments.isEmpty) {
      segments.add(StoryVoiceSegment(text: text));
    }

    return segments;
  }

  /// Synthesize [text] to a single WAV, voicing each character's dialogue with
  /// their assigned TTS voice. Returns null when nothing could be synthesized.
  ///
  /// Fast path: when no cast member has a voice assigned, the whole text is read
  /// in the default narrator voice (one TTS call). Otherwise each segment is
  /// synthesized in turn and the parts are stitched via [WavUtils]. Pass
  /// [isCancelled] to abort a long read-along mid-page.
  static Future<File?> synthesizeStitchedWav(
    String text,
    List<StoryCastMember> cast,
    TtsService tts, {
    bool Function()? isCancelled,
  }) async {
    if (text.trim().isEmpty) return null;

    final hasVoiced = cast.any((c) => (c.voiceModel ?? '').isNotEmpty);
    if (!hasVoiced) {
      return tts.generateAudioFile(text);
    }

    final segments = parseVoiceSegments(text, cast);
    final files = <File>[];
    for (final seg in segments) {
      if (isCancelled?.call() ?? false) break;
      if (seg.text.trim().isEmpty) continue;
      final file = await tts.generateAudioFile(
        seg.text,
        voiceKey: seg.voiceKey,
      );
      if (file != null) files.add(file);
    }

    if (files.isEmpty) return null;
    if (files.length == 1) return files.first;
    // WavUtils returns null only on a genuinely unstitchable set — fall back to
    // the first part so the reader still speaks something.
    return await WavUtils.concatenateWavFiles(files) ?? files.first;
  }
}
