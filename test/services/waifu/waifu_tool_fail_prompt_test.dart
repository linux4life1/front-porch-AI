// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('failed write is FAILED in the next prompt, not a soft error tag', () {
    const fail = WaifuMessage.tool(
      name: 'write',
      output: 'denied: path is outside the folder jail',
      ok: false,
    );
    final line = waifuToolPromptLine(fail);
    expect(line, contains('[tool write FAILED]'));
    expect(line, contains('Disk was not changed'));
    expect(line, contains('folder jail'));
    expect(line, isNot(contains('[tool write error]')));
    expect(line, isNot(contains('[tool write ok]')));
  });
}
