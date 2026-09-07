// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/desk/desk.dart';

void main() {
  test('code-review is a slash command and matches /code', () {
    expect(
      kDeskSlashCommands.map((c) => c.name),
      containsAll(['review', 'code-review', 'skills']),
    );
    expect(
      deskSlashMatches('/code').map((c) => c.name),
      contains('code-review'),
    );
    expect(deskSlashMatches('/code-review').map((c) => c.name), [
      'code-review',
    ]);
    expect(deskSlashExact('/code-review src'), isNotNull);
    expect(deskSlashExact('/code-review src')!.name, 'code-review');
  });

  test('review menu blurb is code review; both expand the same', () {
    final review = kDeskSlashCommands.firstWhere((c) => c.name == 'review');
    final alias = kDeskSlashCommands.firstWhere((c) => c.name == 'code-review');
    expect(review.blurb.toLowerCase(), contains('code review'));
    expect(alias.blurb.toLowerCase(), contains('code review'));
    expect(deskSlashAgentTask('/code-review'), deskSlashAgentTask('/review'));
    expect(deskSlashAgentTask('/review'), contains('Review this folder'));
  });

  test('skills slash is local and help lists it', () {
    final skills = deskSlashExact('/skills');
    expect(skills, isNotNull);
    expect(skills!.local, isTrue);
    expect(deskSlashHelpText(), contains('/skills'));
    expect(deskSlashHelpText(), contains('/code-review'));
  });
}
