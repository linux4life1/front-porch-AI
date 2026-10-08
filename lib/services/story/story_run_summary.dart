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

import 'story_studio_store.dart';

/// Where a story's model time went, per job (planning, prose, review).
class StoryJobTime {
  StoryJobTime(this.role);

  final String role;
  int calls = 0;
  int millis = 0;
  final Set<String> models = {};

  double get averageSeconds => calls == 0 ? 0 : millis / calls / 1000;

  /// "Review · 28 calls · 34 min · 74s each · grok-4.7"
  String get line => [
    role.isEmpty ? 'Other' : role[0].toUpperCase() + role.substring(1),
    '$calls call${calls == 1 ? '' : 's'}',
    storyDuration(millis),
    '${averageSeconds.round()}s each',
    if (models.isNotEmpty) models.join(', '),
  ].join(' · ');
}

/// "48s" under a minute and a half, else whole minutes.
String storyDuration(int millis) {
  final seconds = millis / 1000;
  return seconds < 90 ? '${seconds.round()}s' : '${(seconds / 60).round()} min';
}

/// Time per job, in the order planning, prose, review, then anything else.
List<StoryJobTime> storyJobTimes(Iterable<StoryRunEntry> entries) {
  const order = ['planning', 'prose', 'review'];
  final byRole = <String, StoryJobTime>{};
  for (final e in entries) {
    final job = byRole.putIfAbsent(e.role, () => StoryJobTime(e.role));
    job.calls++;
    job.millis += e.millis;
    if (e.model.isNotEmpty) job.models.add(e.model);
  }
  int rank(String role) {
    final i = order.indexOf(role);
    return i < 0 ? order.length : i;
  }

  return byRole.values.toList()
    ..sort((a, b) => rank(a.role).compareTo(rank(b.role)));
}

/// Plain words when checking takes far longer than writing: the Review job
/// runs after every beat, so a slow model there dominates the whole story.
/// Null until there are enough calls to judge, or when checks are not slow.
String? slowChecksNote(Iterable<StoryRunEntry> entries) {
  final jobs = {for (final j in storyJobTimes(entries)) j.role: j};
  final review = jobs['review'];
  final prose = jobs['prose'];
  if (review == null || prose == null) return null;
  if (review.calls < 3 || prose.calls < 3) return null;
  if (review.averageSeconds < 20 ||
      review.averageSeconds < prose.averageSeconds * 3) {
    return null;
  }
  return 'Checks average ${review.averageSeconds.round()}s each; writing '
      'averages ${prose.averageSeconds.round()}s. A check runs after every '
      'beat, so a faster Review model (Setup, Engine step) would speed this '
      'story up.';
}
