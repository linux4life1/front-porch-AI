// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'studio_desk.dart';

/// Edit stove. Readiness comes from the same desk the Create tab uses.
class StudioEditPane extends StatelessWidget {
  const StudioEditPane({super.key, this.busy = false, this.onReadyChanged});

  final bool busy;
  final ValueChanged<bool>? onReadyChanged;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: busy,
      child: StudioDesk(onReadyChanged: onReadyChanged),
    );
  }
}
