// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/ui/image_studio/studio_model_sheet.dart';

/// The files one Change sheet lists. A name is a guess, so nothing is hidden:
/// files that look wrong for [primary] (for a [role] of 'VAE' or
/// 'Text encoder') come last, named in `unfit`. The model itself has no role.
StudioModelListing studioModelListing({
  required String primary,
  required String role,
  required List<String> pool,
}) {
  final unfit = role.isEmpty
      ? const <String>{}
      : {
          for (final file in pool)
            if (!supportFileFits(primary: primary, file: file, role: role))
              file,
        };
  return (
    items: [
      for (final file in pool)
        if (!unfit.contains(file)) file,
      for (final file in pool)
        if (unfit.contains(file)) file,
    ],
    unfit: unfit,
  );
}
