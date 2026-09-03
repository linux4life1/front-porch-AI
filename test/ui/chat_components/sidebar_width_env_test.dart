// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/sidebar_tokens.dart';

void main() {
  test('SIDEBAR_WIDTH omit/default stays product 300', () {
    expect(SidebarTokens.widthFromEnvironment(defined: 300), 300);
  });

  test('SIDEBAR_WIDTH 0 stays closed', () {
    expect(SidebarTokens.widthFromEnvironment(defined: 0), 0);
    expect(SidebarTokens.widthFromEnvironment(defined: -1), 0);
  });

  test('SIDEBAR_WIDTH clamps to minWidth..maxWidth', () {
    expect(
      SidebarTokens.widthFromEnvironment(defined: 230),
      SidebarTokens.minWidth,
    );
    expect(
      SidebarTokens.widthFromEnvironment(defined: 214),
      SidebarTokens.minWidth,
    );
    expect(
      SidebarTokens.widthFromEnvironment(defined: 100),
      SidebarTokens.minWidth,
    );
    expect(
      SidebarTokens.widthFromEnvironment(defined: 999),
      SidebarTokens.maxWidth,
    );
  });
}
