// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Re-reads a Change sheet's list from the connected app. Labelled and
/// styled like the Refresh Models button on the LLM backends. Shows a small
/// spinner while it reads and ignores taps until it is done.
class StudioRefreshButton extends StatelessWidget {
  const StudioRefreshButton({
    super.key,
    required this.label,
    required this.refreshing,
    required this.onPressed,
  });

  final String label;
  final bool refreshing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: refreshing ? null : onPressed,
      icon: refreshing
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh, size: 16),
      label: Text(refreshing ? 'Loading...' : label),
      style: TextButton.styleFrom(padding: EdgeInsets.zero),
    );
  }
}
