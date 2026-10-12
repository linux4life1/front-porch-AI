// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/pages/repository/stoop_collapsible.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';

/// First-message section with a carousel over the alternate greetings.
/// [index] is clamped into range; [onIndexChanged] gets the new index.
class StoopDetailFirstMessage extends StatelessWidget {
  final List<String> greetings;
  final int index;
  final ValueChanged<int> onIndexChanged;

  const StoopDetailFirstMessage({
    super.key,
    required this.greetings,
    required this.index,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (greetings.isEmpty) return const SizedBox.shrink();
    final idx = index.clamp(0, greetings.length - 1);
    final multi = greetings.length > 1;
    return StoopCollapsible(
      title: multi ? 'First message (${greetings.length})' : 'First message',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Greeting carousel lives inside the expanded body so a collapsed card
          // stays a single line; expand to browse the alternates.
          if (multi)
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left, size: 20),
                  color: stoopCream2(context),
                  onPressed: idx > 0 ? () => onIndexChanged(idx - 1) : null,
                ),
                Text(
                  '${idx + 1}/${greetings.length}',
                  style: TextStyle(color: stoopMute(context)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right, size: 20),
                  color: stoopCream2(context),
                  onPressed: idx < greetings.length - 1
                      ? () => onIndexChanged(idx + 1)
                      : null,
                ),
              ],
            ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: stoopBg1(context),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: stoopBorder(context)),
            ),
            child: Text(
              greetings[idx],
              style: TextStyle(color: stoopCream2(context), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
