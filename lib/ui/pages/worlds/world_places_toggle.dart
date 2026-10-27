// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "N places · starts at X" on a world card: opens and closes the panel of
// that world's places beneath its row of cards.

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

class WorldPlacesToggle extends StatelessWidget {
  const WorldPlacesToggle({
    super.key,
    required this.count,
    required this.startingPlace,
    required this.open,
    required this.onTap,
  });

  /// Every place in the world, rooms inside buildings included.
  final int count;

  /// The starred place, or null when the world has places but no valid
  /// star — then the toggle says so in the error ink.
  final World? startingPlace;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.formAccentOf(context);
    final start = startingPlace;
    return Material(
      color: open ? accent.withValues(alpha: 0.12) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: open
              ? accent.withValues(alpha: 0.5)
              : AppColors.borderOf(context),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.place_outlined, size: 15, color: accent),
              const SizedBox(width: 6),
              Text(
                '$count place${count == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  start == null
                      ? '· no starting place'
                      : '· starts at ${start.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: start == null
                        ? AppColors.logError
                        : AppColors.textTertiary(context),
                  ),
                ),
              ),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  Icons.expand_more,
                  size: 18,
                  color: AppColors.textSecondary(context),
                  semanticLabel: open ? 'Hide places' : 'Show places',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
