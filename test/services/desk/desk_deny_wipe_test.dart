// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/desk/desk.dart';

void main() {
  test('recursive rm of *, ., home, and / is denied; project build is not', () {
    expect(deskDeniedCommand('rm -rf *'), isNotNull);
    expect(deskDeniedCommand('rm -rf .'), isNotNull);
    expect(deskDeniedCommand('rm -rf ~'), isNotNull);
    expect(deskDeniedCommand('rm -rf \$HOME'), isNotNull);
    expect(deskDeniedCommand('rm -rf /*'), isNotNull);
    expect(deskDeniedCommand('rm --recursive --force /'), isNotNull);
    expect(deskDeniedCommand('sudo rm -rf /tmp/foo'), isNotNull);
    expect(deskDeniedCommand('rm -rf build'), isNull);
    expect(deskDeniedCommand('rm -rf .dart_tool'), isNull);
  });

  test('fork bomb, mkfs, and dd to a device are denied', () {
    expect(deskDeniedCommand(':(){ :|:& };:'), isNotNull);
    expect(deskDeniedCommand('mkfs.ext4 /dev/sda1'), isNotNull);
    expect(deskDeniedCommand('dd if=/dev/zero of=/dev/sda'), isNotNull);
    expect(deskDeniedCommand('diskutil eraseDisk JHFS+ x disk2'), isNotNull);
    expect(deskDeniedCommand('ls -la'), isNull);
  });
}
