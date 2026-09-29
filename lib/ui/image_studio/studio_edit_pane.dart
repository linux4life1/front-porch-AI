// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'studio_desk.dart';

/// Edit stove. Readiness comes from the same desk the Create tab uses.
class StudioEditPane extends StatelessWidget {
  const StudioEditPane({
    super.key,
    this.busy = false,
    this.onReadyChanged,
    this.onGenerate,
    this.errorText = '',
  });

  final bool busy;
  final ValueChanged<bool>? onReadyChanged;
  final VoidCallback? onGenerate;
  final String errorText;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: busy,
      child: StudioDesk(
        editMode: true,
        showGenerate: true,
        generating: busy,
        onGenerate: onGenerate,
        errorText: errorText,
        onReadyChanged: onReadyChanged,
      ),
    );
  }
}
