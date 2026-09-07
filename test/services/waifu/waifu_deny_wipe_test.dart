// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('recursive rm cannot target roots, homes, systems, or parents', () {
    for (final command in [
      'rm -r /',
      'rm -rf /',
      'rm -rf /*',
      'rm -rf "."',
      "rm -rf '/'",
      'rm -rf ~',
      r'rm -rf $HOME',
      r'rm -rf ${HOME}',
      r'''rm -rf "${HOME}"''',
      'rm -rf ..',
      'rm -rf ../',
      'rm -rf ../sibling',
      'rm -rf /usr',
      'rm -rf /usr/local',
      'rm -rf /home',
      'rm -rf /Users',
      'bash -c "rm -rf /"',
      "bash -c 'rm -rf ..'",
      'rm --recursive --force /',
      'sudo rm -rf /tmp/foo',
    ]) {
      expect(
        waifuDeniedCommand(command, workingDirectory: '/tmp/project'),
        isNotNull,
        reason: command,
      );
    }
    expect(waifuDeniedCommand('rm -rf build'), isNull);
    expect(waifuDeniedCommand('rm -rf .dart_tool'), isNull);
    expect(
      waifuDeniedCommand(
        'rm -r /home/me/project/build',
        workingDirectory: '/home/me/project',
      ),
      isNull,
    );
  });

  test('destructive git, disk, find, Python, and permission bombs stop', () {
    for (final command in [
      'git clean -fdx',
      'git clean -ffdx',
      'git reset --hard',
      'git checkout -- .',
      'git restore .',
      ':(){ :|:& };:',
      'mkfs.ext4 /dev/sda1',
      'wipefs -a /dev/sda',
      'dd if=/dev/zero of=/dev/sda',
      'dd if=/dev/zero of="/dev/sda"',
      'diskutil eraseDisk JHFS+ x disk2',
      'format c:',
      'chmod -R 777 /',
      'chown -R root /usr',
      'find / -delete',
      'find ~ -delete',
      'find .. -delete',
      '''python -c "import shutil; shutil.rmtree('/')"''',
    ]) {
      expect(
        waifuDeniedCommand(command, workingDirectory: '/tmp/project'),
        isNotNull,
        reason: command,
      );
    }
    expect(waifuDeniedCommand('git clean -ndx'), isNull);
    expect(waifuDeniedCommand('find build -delete'), isNull);
    expect(waifuDeniedCommand('chmod -R u+rwX build'), isNull);
    expect(waifuDeniedCommand('ls -la'), isNull);
  });

  test('process-environment dump commands are denied', () {
    for (final command in [
      'env',
      '/usr/bin/env',
      'printenv',
      'bash -c "printenv"',
      'export -p',
    ]) {
      expect(waifuDeniedCommand(command), isNotNull, reason: command);
    }
    expect(waifuDeniedCommand('export BUILD_MODE=debug'), isNull);
  });
}
