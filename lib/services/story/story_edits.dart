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

import 'dart:math';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/story_xml.dart';

/// Outcome of applying a set of find → replace edits to a passage.
class EditReport {
  final String text;

  /// Edits that landed, with [ProseEdit.find] rewritten to the exact text
  /// that was matched (so the diff shown to the user is true to the page).
  final List<ProseEdit> applied;

  /// Edits whose target could not be found, paired with why.
  final List<({ProseEdit edit, String reason})> failed;

  const EditReport({
    required this.text,
    this.applied = const [],
    this.failed = const [],
  });

  bool get changed => applied.isNotEmpty;
}

/// Surgical editing: a model proposes small find → replace blocks and this
/// applies them, instead of asking the model to retype (and quietly rewrite)
/// the whole passage. Matching tolerates the ways a model misquotes prose —
/// straightened quotes, collapsed whitespace, a clipped middle.
abstract final class StoryEdits {
  /// A fix that rewrites more than this share of the passage is a rewrite,
  /// not a patch, and is refused.
  static const maxChangeRatio = 0.6;

  /// Read `<edit><find>…</find><replace>…</replace></edit>` blocks. The
  /// synonyms cover what models write when they drift from the format.
  static List<ProseEdit> parse(String raw) {
    final text = StoryXml.clean(raw);
    var blocks = StoryXml.all(text, 'edit');
    if (blocks.isEmpty) blocks = StoryXml.all(text, 'search_replace');
    if (blocks.isEmpty && StoryXml.has(text, 'find')) blocks = [text];
    final edits = <ProseEdit>[];
    for (final block in blocks) {
      final find = _field(block, const ['find', 'search', 'original']);
      if (find == null || find.trim().isEmpty) continue;
      final replace =
          _field(block, const ['replace', 'rewritten', 'replacement']) ?? '';
      edits.add(ProseEdit(find: find, replace: replace));
    }
    return edits;
  }

  /// Untrimmed on purpose: leading/trailing spaces inside a replacement are
  /// part of the edit.
  static String? _field(String block, List<String> names) {
    for (final n in names) {
      final inner = StoryXml.all(block, n, limit: 1);
      if (inner.isNotEmpty) return StoryXml.decode(inner.first);
    }
    return null;
  }

  /// Apply [edits] in order, each against the text as left by the previous.
  static EditReport apply(String original, List<ProseEdit> edits) {
    var text = original;
    final applied = <ProseEdit>[];
    final failed = <({ProseEdit edit, String reason})>[];
    for (final edit in edits) {
      final at = locate(text, edit.find);
      if (at == null) {
        failed.add((edit: edit, reason: 'passage not found'));
        continue;
      }
      final before = text.substring(at.start, at.end);
      // A needle matched only after trimming drops its padding from the
      // replacement too, or the patch would double the surrounding spaces.
      final after = text.contains(edit.find)
          ? edit.replace
          : edit.replace.trim();
      if (before == after) {
        failed.add((edit: edit, reason: 'edit makes no change'));
        continue;
      }
      text = text.substring(0, at.start) + after + text.substring(at.end);
      applied.add(ProseEdit(find: before, replace: after));
    }
    return EditReport(text: text, applied: applied, failed: failed);
  }

  /// Where [needle] sits in [haystack]: exact, then trimmed, then with
  /// typographic quotes/dashes flattened, then with flexible whitespace, and
  /// for long passages by a unique head and tail.
  static ({int start, int end})? locate(String haystack, String needle) {
    if (needle.trim().isEmpty) return null;
    var start = haystack.indexOf(needle);
    if (start != -1) return (start: start, end: start + needle.length);
    final trimmed = needle.trim();
    start = haystack.indexOf(trimmed);
    if (start != -1) return (start: start, end: start + trimmed.length);

    // Every mapping is one code unit to one code unit, so offsets found in
    // the flattened text address the original.
    final flatHay = _flatten(haystack);
    final flatNeedle = _flatten(trimmed);
    start = flatHay.indexOf(flatNeedle);
    if (start != -1) return (start: start, end: start + flatNeedle.length);

    final flexible = RegExp(
      flatNeedle.split(RegExp(r'\s+')).map(RegExp.escape).join(r'\s+'),
    ).firstMatch(flatHay);
    if (flexible != null) return (start: flexible.start, end: flexible.end);

    if (flatNeedle.length >= 80) {
      final head = flatNeedle.substring(0, 40);
      final tail = flatNeedle.substring(flatNeedle.length - 40);
      final headAt = flatHay.indexOf(head);
      if (headAt != -1 && flatHay.indexOf(head, headAt + 1) == -1) {
        final tailAt = flatHay.indexOf(tail, headAt + head.length);
        if (tailAt != -1 &&
            flatHay.indexOf(tail, tailAt + 1) == -1 &&
            tailAt + tail.length - headAt <= 3 * flatNeedle.length) {
          return (start: headAt, end: tailAt + tail.length);
        }
      }
    }
    return null;
  }

  static String _flatten(String text) => text
      .replaceAll(RegExp('[‘’‚‛]'), "'")
      .replaceAll(RegExp('[“”„‟]'), '"')
      .replaceAll(RegExp('[–—]'), '-')
      .replaceAll('…', '.')
      .replaceAll(RegExp('[   ]'), ' ');

  /// Share of [after] (by characters) that is not carried over from
  /// [before], by word-level longest common subsequence. Word-level because
  /// a paragraph-level diff reads one small edit per paragraph as a rewrite.
  static double changeRatio(String before, String after) {
    final oldWords = before.split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    final newWords = after.split(RegExp(r'\s+'))..removeWhere((w) => w.isEmpty);
    final afterChars = newWords.fold<int>(0, (n, w) => n + w.length);
    if (afterChars == 0) return 0;
    var prev = List<int>.filled(newWords.length + 1, 0);
    var curr = List<int>.filled(newWords.length + 1, 0);
    for (var i = 1; i <= oldWords.length; i++) {
      for (var j = 1; j <= newWords.length; j++) {
        curr[j] = oldWords[i - 1] == newWords[j - 1]
            ? prev[j - 1] + newWords[j - 1].length
            : max(prev[j], curr[j - 1]);
      }
      final swap = prev;
      prev = curr;
      curr = swap;
    }
    return (afterChars - prev[newWords.length]) / afterChars;
  }
}
