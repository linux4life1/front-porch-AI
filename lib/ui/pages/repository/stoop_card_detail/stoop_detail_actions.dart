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

import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Hub votebox (joined ▼ score ▲, amber-lit when upvoted, ember when
/// downvoted) + the lamplight download CTA.
class StoopDetailActions extends StatelessWidget {
  final int score;
  final int myVote;
  final bool downloading;
  final ValueChanged<int> onVote;
  final VoidCallback onDownload;

  const StoopDetailActions({
    super.key,
    required this.score,
    required this.myVote,
    required this.downloading,
    required this.onVote,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: stoopBg1(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: stoopBorderHi(context)),
          ),
          child: Row(
            children: [
              _voteCell(
                context,
                icon: Icons.arrow_downward_rounded,
                on: myVote == -1,
                gradient: stoopEmberGradient,
                onTap: () => onVote(-1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '$score',
                  style: TextStyle(
                    color: stoopAmberText(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _voteCell(
                context,
                icon: Icons.arrow_upward_rounded,
                on: myVote == 1,
                gradient: stoopAmberGradient,
                onTap: () => onVote(1),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StoopAmberButton(
            label: downloading ? 'Adding…' : 'Download to library',
            icon: downloading ? null : Icons.download_rounded,
            busy: downloading,
            onPressed: downloading ? null : onDownload,
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      ],
    );
  }

  Widget _voteCell(
    BuildContext context, {
    required IconData icon,
    required bool on,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(gradient: on ? gradient : null),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Icon(
          icon,
          size: 19,
          color: on ? AppColors.stoopAmberInk : stoopCream2(context),
        ),
      ),
    );
  }
}
