// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Text on a solid porch fill reads whatever theme the widget sits under:
// dark ink on dark mode's bright amber, white on light mode's deep amber and
// on the destructive red.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final (name, fill) in [
    ('dark-mode amber', AppColors.porchAmber),
    ('light-mode amber', AppColors.porchAmberLight),
    ('red', AppColors.negativeAccentLight),
  ]) {
    test('ink on $name reads at 4.5:1 or better', () {
      expect(_contrast(AppColors.inkOn(fill), fill), greaterThanOrEqualTo(4.5));
    });
  }

  test('dark grounds are the studio browns', () {
    expect(AppColors.background, StudioColors.bg);
    expect(AppColors.card, StudioColors.card);
    expect(AppColors.surface, StudioColors.side);
    expect(AppColors.surfaceContainer, StudioColors.raise);
  });
}
