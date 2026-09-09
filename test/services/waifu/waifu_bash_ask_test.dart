// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proven red: Build treated every bash call as a mutate, so `ls -la`
// asked every time. Always this session also died on nested workers.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('Build does not ask for read-only bash like ls -la', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    expect(p.needsAsk(name: 'bash', args: {'command': 'ls -la'}), isFalse);
    expect(
      p.needsAsk(name: 'bash', args: {'command': 'ls -la .waifu'}),
      isFalse,
    );
    expect(p.needsAsk(name: 'bash', args: {'command': 'pwd'}), isFalse);
    expect(
      p.needsAsk(name: 'bash', args: {'command': 'cat README.md'}),
      isFalse,
    );
    expect(p.needsAsk(name: 'bash', args: {'command': 'git status'}), isFalse);
  });

  test('Build still asks for mutating bash; porch writes do not', () {
    final p = WaifuPermissions(
      mode: WaifuMode.build,
      workingDirectory: '/tmp/porch-app',
    );
    expect(p.needsAsk(name: 'bash', args: {'command': 'rm -rf build'}), isTrue);
    expect(
      p.needsAsk(name: 'bash', args: {'command': 'ls -la && rm foo'}),
      isTrue,
    );
    expect(p.needsAsk(name: 'bash', args: {'command': 'ls > out.txt'}), isTrue);
    expect(
      p.needsAsk(name: 'write', args: {'path': 'a.txt', 'contents': 'x'}),
      isFalse,
    );
    expect(
      p.needsAsk(name: 'write', args: {'path': '/etc/hosts', 'contents': 'x'}),
      isTrue,
    );
  });

  test('Always this session is shared with nested workers', () {
    final parent = WaifuPermissions(mode: WaifuMode.build);
    final child = parent.fork(mode: WaifuMode.build);
    expect(
      child.needsAsk(name: 'write', args: {'path': 'a.txt', 'contents': 'x'}),
      isTrue,
    );
    child.allowAlways();
    expect(
      parent.needsAsk(name: 'write', args: {'path': 'b.txt', 'contents': 'y'}),
      isFalse,
    );
    expect(
      child.needsAsk(name: 'bash', args: {'command': 'mkdir src'}),
      isFalse,
    );
  });
}
