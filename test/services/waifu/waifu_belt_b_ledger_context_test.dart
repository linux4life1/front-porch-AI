// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  WaifuMessage bash(String command) => WaifuMessage.tool(
    name: kWaifuToolBash,
    output: 'ok',
    ok: true,
    args: {'command': command},
  );

  test('B2: named check is as-run only with the turn context', () {
    const named = 'tox -e py';
    final folded = [bash(named), bash('ls')];
    final bare = waifuMachineLedger(
      folded: folded,
      context: const WaifuVerifyContext(),
    );
    expect(bare, isNot(contains(named)));
    expect(bare.split('verify as-run:').last, isNot(contains('ls')));

    final ledger = waifuMachineLedger(
      folded: folded,
      context: const WaifuVerifyContext(named: [named]),
    );
    final verifyBlock = ledger
        .split('verify as-run:')
        .last
        .split('plan:')
        .first;
    expect(verifyBlock, contains(named));
    expect(verifyBlock, isNot(contains('ls')));
  });
}
