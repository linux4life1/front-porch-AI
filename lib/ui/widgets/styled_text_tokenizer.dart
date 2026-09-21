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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

enum StyledTokenType { macro, dialogue, action }

class StyledTextPreset {
  final RegExp pattern;
  final TextStyle Function(BuildContext context, String match, TextStyle? base)
  styler;
  final bool usePriorityTokenization;

  const StyledTextPreset(
    this.pattern,
    this.styler, {
    this.usePriorityTokenization = false,
  });

  static final prose = StyledTextPreset(
    RegExp(r'("[^"]*")|(\*[^*]*\*)|({{[^}]*}})'),
    (ctx, match, base) {
      if (match.startsWith('"')) {
        return (base ?? const TextStyle()).copyWith(
          color: AppColors.resolve(
            ctx,
            Colors.amberAccent,
            const Color(0xFFB45309),
          ),
          fontWeight: FontWeight.w500,
        );
      }
      if (match.startsWith('*')) {
        return (base ?? const TextStyle()).copyWith(
          color: AppColors.resolve(
            ctx,
            const Color(0xFF90CAF9),
            const Color(0xFF1565C0),
          ),
        );
      }
      return (base ?? const TextStyle()).copyWith(
        color: AppColors.resolve(
          ctx,
          Colors.tealAccent,
          const Color(0xFF0D9488),
        ),
      );
    },
    usePriorityTokenization: true,
  );

  static final chat = StyledTextPreset(RegExp(r'("[^"]*")|(\*[^*]*\*)'), (
    ctx,
    match,
    base,
  ) {
    if (match.startsWith('"')) {
      return (base ?? const TextStyle()).copyWith(
        color: AppColors.resolve(
          ctx,
          Colors.amberAccent,
          const Color(0xFFB45309),
        ),
        fontWeight: FontWeight.w500,
      );
    }
    return (base ?? const TextStyle()).copyWith(
      color: AppColors.resolve(
        ctx,
        const Color(0xFF90CAF9),
        const Color(0xFF1565C0),
      ),
    );
  }, usePriorityTokenization: true);

  static final macros = StyledTextPreset(RegExp(r'({{[^}]*}})'), (
    ctx,
    match,
    base,
  ) {
    return (base ?? const TextStyle()).copyWith(
      color: AppColors.resolve(ctx, Colors.tealAccent, const Color(0xFF0D9488)),
    );
  });
}

/// Tokenizes [text] with priority: "dialogue" > *action*.
/// Dialogue is found first (no skips), then action scans skipping dialogue.
/// Action ranges are split around dialogue ranges inside them.
/// Used by [StyledTextController] (chat preset) and [StyledChatMessage].
List<({int start, int end, String matchText, StyledTokenType type})>
tokenizeChat(String text) {
  final dialogueRanges = scanDialogue(text, []);
  final actionRanges = scanDelimited(text, '*', '*', dialogueRanges);

  // Split action ranges around dialogue ranges inside them
  final actionSplits = <({int start, int end})>[];
  for (final ar in actionRanges) {
    int segStart = ar.start;
    for (final dr in dialogueRanges) {
      if (dr.start >= ar.start && dr.end <= ar.end) {
        if (segStart < dr.start) {
          actionSplits.add((start: segStart, end: dr.start));
        }
        segStart = dr.end;
      }
    }
    if (segStart < ar.end) {
      actionSplits.add((start: segStart, end: ar.end));
    }
  }

  return <({int start, int end, String matchText, StyledTokenType type})>[
    for (final d in dialogueRanges)
      (
        start: d.start,
        end: d.end,
        matchText: text.substring(d.start, d.end),
        type: StyledTokenType.dialogue,
      ),
    for (final a in actionSplits)
      (
        start: a.start,
        end: a.end,
        matchText: text.substring(a.start, a.end),
        type: StyledTokenType.action,
      ),
  ]..sort((a, b) => a.start.compareTo(b.start));
}

/// Opening quote → the set of closing quotes that can terminate it, covering
/// the common localized/typographic dialogue styles: straight ("…"), English
/// curly (“…”), German/Polish/Czech („…“ / „…”), Nordic (”…”), French & German
/// guillemets («…» / »…«) and CJK brackets (「…」). Scanned left-to-right, so a
/// char that is both an opener and a closer (e.g. « in French vs German-alt)
/// resolves by consumption order. Kept in sync with the web UI dialogue matcher
/// (web_ui/src/components/rpText.tsx) so highlighting is identical on both.
const Map<String, Set<String>> kDialogueQuotePairs = {
  '"': {'"'},
  '“': {'”'}, // “ … ”
  '„': {'“', '”'}, // „ … “  /  „ … ”
  '”': {'”'}, // ” … ”
  '«': {'»'}, // « … »
  '»': {'«'}, // » … «
  '「': {'」'}, // 「 … 」
};

/// Scans [text] for dialogue quoted with any style in [kDialogueQuotePairs],
/// skipping any delimiter inside [skipRanges]. The dialogue analogue of
/// [scanDelimited]: quotes need multiple, asymmetric open/close pairs whereas
/// asterisks only need one symmetric delimiter (so that path keeps using
/// [scanDelimited] unchanged).
List<({int start, int end})> scanDialogue(
  String text,
  List<({int start, int end})> skipRanges,
) {
  final ranges = <({int start, int end})>[];
  int i = 0;
  while (i < text.length) {
    final closers = kDialogueQuotePairs[text[i]];
    if (closers != null && !inRanges(i, skipRanges)) {
      final start = i;
      i++;
      while (i < text.length) {
        if (closers.contains(text[i]) && !inRanges(i, skipRanges)) {
          ranges.add((start: start, end: i + 1));
          i++;
          break;
        }
        i++;
      }
    } else {
      i++;
    }
  }
  return ranges;
}

/// Scans [text] left-to-right for [openChar]…[closeChar] pairs,
/// skipping any delimiter that falls inside [skipRanges].
List<({int start, int end})> scanDelimited(
  String text,
  String openChar,
  String closeChar,
  List<({int start, int end})> skipRanges,
) {
  final ranges = <({int start, int end})>[];
  int i = 0;
  while (i < text.length) {
    if (text[i] == openChar && !inRanges(i, skipRanges)) {
      final start = i;
      i++;
      while (i < text.length) {
        if (text[i] == closeChar && !inRanges(i, skipRanges)) {
          ranges.add((start: start, end: i + 1));
          i++;
          break;
        }
        i++;
      }
    } else {
      i++;
    }
  }
  return ranges;
}

/// Returns true when [pos] falls inside any range in [ranges].
bool inRanges(int pos, List<({int start, int end})> ranges) {
  for (final r in ranges) {
    if (pos >= r.start && pos < r.end) return true;
    if (r.start > pos) break;
  }
  return false;
}
