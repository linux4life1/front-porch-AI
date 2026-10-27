// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The full-width panel a world card opens beneath its row: the world's
// places as rows (depth-first, rooms indented under their building), with
// where chats start, the world's weather and "Add a place inside" on top.
// The model-made filter reuses it as a plain list with no world header.

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

class WorldPlacesPanel extends StatelessWidget {
  const WorldPlacesPanel({
    super.key,
    required this.title,
    required this.rows,
    this.startLine,
    this.startMissing = false,
    this.weatherLine,
    this.onAddInside,
    this.onClose,
  });

  final String title;
  final List<Widget> rows;

  /// "Chats start at X", or the ask for a star when [startMissing].
  final String? startLine;
  final bool startMissing;
  final String? weatherLine;
  final VoidCallback? onAddInside;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.formAccentOf(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 14,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  if (startLine != null) _startLine(context, accent),
                  if (weatherLine != null)
                    Text(
                      weatherLine!,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onAddInside != null)
                    TextButton.icon(
                      key: const Key('place-add-inside'),
                      style: TextButton.styleFrom(foregroundColor: accent),
                      icon: const Icon(
                        Icons.add_location_alt_outlined,
                        size: 16,
                      ),
                      label: const Text('Add a place inside'),
                      onPressed: onAddInside,
                    ),
                  if (onClose != null)
                    IconButton(
                      key: const Key('places-panel-close'),
                      tooltip: 'Hide places',
                      onPressed: onClose,
                      icon: Icon(
                        Icons.expand_less,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Divider(height: 14, color: AppColors.borderOf(context)),
          ...rows,
        ],
      ),
    );
  }

  Widget _startLine(BuildContext context, Color accent) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          startMissing ? Icons.star_border_rounded : Icons.star_rounded,
          size: 14,
          color: startMissing ? AppColors.logError : accent,
        ),
        const SizedBox(width: 4),
        Text(
          startLine!,
          style: TextStyle(
            fontSize: 12,
            color: startMissing
                ? AppColors.logError
                : AppColors.textSecondary(context),
          ),
        ),
      ],
    );
  }
}
