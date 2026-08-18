// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Leftover [today: …] strip (never shown in the bubble) plus the scene-time
// eval field parser. Today's sentence is a realism-engine eval, not a tag.

/// Parses and strips `[today: …]` from a model reply.
class TodayLineTag {
  TodayLineTag._();

  static final RegExp pattern = RegExp(
    r'\[today:\s*(.*?)\]',
    caseSensitive: false,
    dotAll: true,
  );

  /// [line] is null when no tag was present (keep whatever is held).
  /// Empty string means the tag was present but blank (abandon / clear).
  static ({String visible, String? line}) parse(String raw) {
    final matches = pattern.allMatches(raw).toList();
    if (matches.isEmpty) return (visible: raw, line: null);

    String line = (matches.last.group(1) ?? '').trim();
    line = line.replaceAll(RegExp(r'\s+'), ' ');
    if (line.length > 140) line = line.substring(0, 140).trim();

    var visible = raw.replaceAll(pattern, '');
    visible = visible.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return (visible: visible, line: line);
  }

  /// Scene-time / one-shot `today_sentence` field.
  ///
  /// Returns null when the field is omitted (keep the current hold).
  /// Returns '' for empty or "none" (abandon). Otherwise the trimmed
  /// sentence, collapsed whitespace, capped at 140.
  static String? parseEvalSentence(String raw) {
    final hasKey = RegExp(r'"today_sentence"\s*:').hasMatch(raw);
    final String value;
    if (hasKey) {
      value =
          RegExp(
            r'"today_sentence"\s*:\s*"([^"]*)"',
          ).firstMatch(raw)?.group(1) ??
          '';
    } else if (raw.trim().startsWith('{')) {
      return null;
    } else {
      value = raw;
      if (value.trim().isEmpty) return null;
    }
    var line = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (line.isEmpty || line.toLowerCase() == 'none') return '';
    if (line.length > 140) line = line.substring(0, 140).trim();
    return line;
  }
}
