// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chips must name the command/path, never "bash bash".

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/desk/desk.dart';

void main() {
  test('bash chip shows the command, not the tool name twice', () {
    expect(
      deskChipDetail('bash', {
        'command': 'flutter create . --project-name demo',
      }),
      contains('flutter create'),
    );
    expect(
      deskChipCaption('bash', deskChipDetail('bash', {'command': 'ls'})),
      'bash ls',
    );
    expect(deskChipCaption('bash', 'bash'), 'bash');
  });

  test('glob chip shows the pattern', () {
    expect(deskChipDetail('glob', {'pattern': '**/*.dart'}), '**/*.dart');
    expect(
      deskChipCaption('glob', deskChipDetail('glob', {'pattern': '**/*.dart'})),
      'glob **/*.dart',
    );
  });
}
