// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Restoring a generation from history never leaves the style dropdown on a
// value it cannot show.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/image_studio/studio_helpers.dart';

void main() {
  test('a saved style the desk lists is restored', () {
    expect(restorableStyle('anime', 'photorealistic'), 'anime');
  });

  test('a saved style the desk does not list keeps the current one', () {
    expect(restorableStyle('cel_shaded_v0', 'watercolor'), 'watercolor');
    expect(restorableStyle('', 'anime'), 'anime');
  });
}
