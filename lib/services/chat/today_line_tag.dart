// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Optional hidden tag the model may append when a planner forms today's
// sentence. Stripped from the visible reply. Not a second eval.

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
}
