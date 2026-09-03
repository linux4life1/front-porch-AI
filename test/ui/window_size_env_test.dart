// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/window_size_env.dart';

void main() {
  test('WINDOW_WIDTH/HEIGHT omit/0 is unset', () {
    expect(WindowSizeEnv.sizeFromEnvironment(width: 0, height: 0), isNull);
    expect(WindowSizeEnv.sizeFromEnvironment(width: -1, height: 0), isNull);
    expect(WindowSizeEnv.sizeFromEnvironment(), isNull);
    expect(WindowSizeEnv.active, isFalse);
  });

  test('either axis >0 skips unset; missing axis is 1280 or 720', () {
    expect(
      WindowSizeEnv.sizeFromEnvironment(width: 1024, height: 0),
      const Size(1024, 720),
    );
    expect(
      WindowSizeEnv.sizeFromEnvironment(width: 0, height: 600),
      const Size(1280, 600),
    );
    expect(
      WindowSizeEnv.sizeFromEnvironment(width: 800, height: 600),
      const Size(800, 600),
    );
  });

  test('UIC boot sizes fit the 1280x800 box desktop', () {
    const boots = [Size(1280, 720), Size(1024, 700), Size(800, 600)];
    for (final want in boots) {
      expect(
        WindowSizeEnv.sizeFromEnvironment(
          width: want.width.toInt(),
          height: want.height.toInt(),
        ),
        want,
      );
      expect(want.width, lessThanOrEqualTo(1280));
      expect(want.height, lessThanOrEqualTo(800));
    }
  });
}
