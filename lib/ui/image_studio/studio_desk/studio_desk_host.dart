// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';

/// What the desk's helpers need from the desk's State: its context, whether
/// it is still mounted, which mode it is in, whether settings may be written,
/// and a way to repaint after a change.
abstract interface class StudioDeskHost {
  BuildContext get context;
  bool get mounted;
  bool get editing;
  bool get configurationLocked;
  void rebuildState(VoidCallback fn);
}
