// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('code-review is a slash command and matches /code', () {
    expect(
      kWaifuSlashCommands.map((c) => c.name),
      containsAll(['review', 'code-review', 'skills']),
    );
    expect(
      waifuSlashMatches('/code').map((c) => c.name),
      contains('code-review'),
    );
    expect(waifuSlashMatches('/code-review').map((c) => c.name), [
      'code-review',
    ]);
    expect(waifuSlashExact('/code-review src'), isNotNull);
    expect(waifuSlashExact('/code-review src')!.name, 'code-review');
  });

  test('review menu blurb is code review; both expand the same', () {
    final review = kWaifuSlashCommands.firstWhere((c) => c.name == 'review');
    final alias = kWaifuSlashCommands.firstWhere((c) => c.name == 'code-review');
    expect(review.blurb.toLowerCase(), contains('code review'));
    expect(alias.blurb.toLowerCase(), contains('code review'));
    expect(waifuSlashAgentTask('/code-review'), waifuSlashAgentTask('/review'));
    expect(waifuSlashAgentTask('/review'), contains('Review this folder'));
  });

  test('skills slash is local and help lists it', () {
    final skills = waifuSlashExact('/skills');
    expect(skills, isNotNull);
    expect(skills!.local, isTrue);
    expect(waifuSlashHelpText(), contains('/skills'));
    expect(waifuSlashHelpText(), contains('/code-review'));
  });
}
