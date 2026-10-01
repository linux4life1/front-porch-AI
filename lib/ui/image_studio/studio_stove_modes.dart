// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Create / Edit on the stove: the one in use is the one that cannot be
/// pressed.
class StudioStoveModes extends StatelessWidget {
  const StudioStoveModes({super.key, required this.editing, this.onMode});

  final bool editing;
  final ValueChanged<bool>? onMode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: editing ? () => onMode?.call(false) : null,
            child: const Text('Create'),
          ),
          TextButton(
            onPressed: editing ? null : () => onMode?.call(true),
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }
}
