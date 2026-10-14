// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The Realism step's note after the first message was rewritten on the
/// Greetings step (#370): the outfit still follows the old one, and nothing
/// was changed. Offers a re-read or to keep it. Drawn from the approved
/// "Realism step: the hint after a new first message" sketch.
class OutfitHint extends StatelessWidget {
  const OutfitHint({
    super.key,
    required this.reading,
    required this.onReread,
    required this.onKeep,
    this.error,
  });

  /// The re-read is running.
  final bool reading;
  final VoidCallback onReread;
  final VoidCallback onKeep;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text(
          'The first message changed',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: StudioColors.inkOf(context),
          ),
        ),
        Text(
          'The outfit below was set from the old first message. Nothing '
          'was changed for you.',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: StudioColors.proseOf(context),
          ),
        ),
        if (error != null)
          Text(
            error!,
            key: const ValueKey('outfit-hint-error'),
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: StudioColors.badOf(context),
            ),
          ),
      ],
    );
    final buttons = [
      SizedBox(
        height: 40,
        child: OutlinedButton.icon(
          key: const ValueKey('outfit-reread'),
          onPressed: reading ? null : onReread,
          icon: reading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: amber,
                  ),
                )
              : const Icon(Icons.refresh, size: 18),
          label: Text(
            reading ? 'Reading the outfit…' : 'Re-read the outfit from it',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: amber,
            disabledForegroundColor: amber,
            side: BorderSide(color: amber, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
      SizedBox(
        height: 40,
        child: TextButton(
          key: const ValueKey('outfit-keep'),
          onPressed: reading ? null : onKeep,
          style: TextButton.styleFrom(
            foregroundColor: StudioColors.proseOf(context),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text(
            'Keep this outfit',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    ];
    return Container(
      key: const ValueKey('outfit-hint'),
      // The spec's hint box: `raise` fill, a 1px amber edge at 50%.
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: StudioColors.raiseOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amber.withValues(alpha: 0.5)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final icon = Icon(Icons.info_outline, size: 22, color: amber);
          // The sketch wraps: the buttons share the line only when the
          // words keep at least 360 of it.
          if (c.maxWidth >= 22 + 360 + 400) {
            return Row(
              spacing: 12,
              children: [
                icon,
                Expanded(child: text),
                ...buttons,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  icon,
                  Expanded(child: text),
                ],
              ),
              Wrap(spacing: 18, runSpacing: 8, children: buttons),
            ],
          );
        },
      ),
    );
  }
}
