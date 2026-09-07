// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('recursive rm of *, ., home, and / is denied; project build is not', () {
    expect(waifuDeniedCommand('rm -rf *'), isNotNull);
    expect(waifuDeniedCommand('rm -rf .'), isNotNull);
    expect(waifuDeniedCommand('rm -rf ~'), isNotNull);
    expect(waifuDeniedCommand('rm -rf \$HOME'), isNotNull);
    expect(waifuDeniedCommand('rm -rf /*'), isNotNull);
    expect(waifuDeniedCommand('rm --recursive --force /'), isNotNull);
    expect(waifuDeniedCommand('sudo rm -rf /tmp/foo'), isNotNull);
    expect(waifuDeniedCommand('rm -rf build'), isNull);
    expect(waifuDeniedCommand('rm -rf .dart_tool'), isNull);
  });

  test('fork bomb, mkfs, and dd to a device are denied', () {
    expect(waifuDeniedCommand(':(){ :|:& };:'), isNotNull);
    expect(waifuDeniedCommand('mkfs.ext4 /dev/sda1'), isNotNull);
    expect(waifuDeniedCommand('dd if=/dev/zero of=/dev/sda'), isNotNull);
    expect(waifuDeniedCommand('diskutil eraseDisk JHFS+ x disk2'), isNotNull);
    expect(waifuDeniedCommand('ls -la'), isNull);
  });
}
