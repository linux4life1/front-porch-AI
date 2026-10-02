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

import 'package:front_porch_ai/services/story/story_xml.dart';

/// What a reviewer model decided about a planning or prose step.
class ReviewVerdict {
  final bool pass;

  /// False when no verdict could be read. An unreadable review counts as a
  /// pass: a reviewer that cannot follow its own format must not burn the
  /// generator's retries.
  final bool parsed;
  final String critique;

  /// What to fix, fed back to the generator on a retry.
  final List<String> reasons;

  /// The problems alone, in plain words — what the writer screen shows.
  final List<String> problems;

  const ReviewVerdict({
    required this.pass,
    this.parsed = true,
    this.critique = '',
    this.reasons = const [],
    this.problems = const [],
  });

  static const skipped = ReviewVerdict(pass: true, parsed: false);

  /// The reasons as one block for a retry prompt.
  String get feedback =>
      reasons.isNotEmpty ? reasons.map((r) => '- $r').join('\n') : critique;
}

abstract final class StoryReview {
  static final _labelled = RegExp(
    r'\b(?:status|verdict|result|decision)\b[^A-Za-z]{0,12}(PASS|FAIL)',
    caseSensitive: false,
  );

  /// Read a verdict from tags first, then from looser shapes models fall
  /// back to (a JSON field, a "Status: FAIL" line, a bare leading word).
  static ReviewVerdict parse(String raw) {
    final text = StoryXml.clean(raw);
    if (text.isEmpty) return ReviewVerdict.skipped;

    bool? pass;
    final status = StoryXml.tag(text, 'status').toUpperCase();
    if (status.contains('FAIL')) {
      pass = false;
    } else if (status.contains('PASS')) {
      pass = true;
    }
    pass ??= switch (_labelled.firstMatch(text)?.group(1)?.toUpperCase()) {
      'PASS' => true,
      'FAIL' => false,
      _ => null,
    };
    if (pass == null) {
      if (RegExp(r'"valid"\s*:\s*false').hasMatch(text)) pass = false;
      if (RegExp(r'"valid"\s*:\s*true').hasMatch(text)) pass = true;
    }
    if (pass == null) {
      final head = text.trimLeft().toUpperCase();
      if (head.startsWith('FAIL')) pass = false;
      if (head.startsWith('PASS')) pass = true;
    }
    if (pass == null) return ReviewVerdict.skipped;

    final critique = StoryXml.firstTag(text, const [
      'critique_analysis',
      'critique',
      'reason',
    ]);
    final reasons = <String>[
      ...StoryXml.list(text, 'deviation_reasons', 'reason'),
    ];
    final problems = <String>[...reasons];
    for (final issue in StoryXml.all(text, 'issue')) {
      final severity = StoryXml.tag(issue, 'severity').toUpperCase();
      if (severity == 'MINOR') continue;
      final what = StoryXml.tag(issue, 'description');
      if (what.isEmpty) continue;
      final where = StoryXml.tag(issue, 'location');
      final fix = StoryXml.tag(issue, 'fix_suggestion');
      final line = [
        what,
        if (where.isNotEmpty) '(at: $where)',
        if (fix.isNotEmpty) 'Fix: $fix',
      ].join(' ');
      if (!reasons.any((r) => r.contains(what))) {
        reasons.add(line);
        problems.add(what);
      }
    }
    return ReviewVerdict(
      pass: pass,
      critique: critique,
      reasons: reasons,
      problems: problems,
    );
  }
}
