// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chips must name the command/path, never "bash bash".

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('bash chip shows the command, not the tool name twice', () {
    expect(
      waifuChipDetail('bash', {
        'command': 'flutter create . --project-name demo',
      }),
      contains('flutter create'),
    );
    expect(
      waifuChipCaption('bash', waifuChipDetail('bash', {'command': 'ls'})),
      'bash ls',
    );
    expect(waifuChipCaption('bash', 'bash'), 'bash');
  });

  test('glob chip shows the pattern', () {
    expect(waifuChipDetail('glob', {'pattern': '**/*.dart'}), '**/*.dart');
    expect(
      waifuChipCaption('glob', waifuChipDetail('glob', {'pattern': '**/*.dart'})),
      'glob **/*.dart',
    );
  });
}
