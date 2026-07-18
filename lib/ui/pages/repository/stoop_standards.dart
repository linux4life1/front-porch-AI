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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// One Stoop content standard — the single source of truth for the rules shown
/// in the upload flow (and echoed in the AUP). Cards that clearly fail these
/// are removed in moderation; the same rules drive the AI/human review rubric.
class StoopStandard {
  final IconData icon;
  final String title;
  final String body;
  const StoopStandard(this.icon, this.title, this.body);
}

const List<StoopStandard> kStoopStandards = [
  StoopStandard(
    Icons.layers_rounded,
    'Substantial',
    'More than a bare prompt — a real scenario, example dialogue, or supporting '
        'detail that justifies a standalone card.',
  ),
  StoopStandard(
    Icons.extension_rounded,
    'Coherent',
    'Persona, scenario, and content agree — no contradictions, one clear '
        'concept the card actually represents.',
  ),
  StoopStandard(
    Icons.menu_book_rounded,
    'Readable',
    'Understandable writing and formatting (unless the card is intentionally a '
        'structured JSON/code format).',
  ),
  StoopStandard(
    Icons.hide_image_rounded,
    'No explicit imagery',
    'Adult text is fine when you mark it NSFW — but avatars must stay '
        'non-pornographic. No nudity or lust-inducing images.',
  ),
  StoopStandard(
    Icons.psychology_rounded,
    'Has agency',
    'Written as a character with its own will — not a forced harem, forced '
        'wedding, or a “must obey” puppet. The Stoop rejects cards that strip '
        'characters of agency.',
  ),
  StoopStandard(
    Icons.verified_user_rounded,
    'Within the AUP',
    'This card complies with The Stoop Acceptable Use Policy.',
  ),
];

/// The standards laid out as a card. Shown in the upload flow; the [footer]
/// (the agency + standards acknowledgements) lives inside the same box so the
/// step reads as one cohesive card rather than several stacked blocks.
class StoopStandardsCard extends StatelessWidget {
  final Widget? footer;
  const StoopStandardsCard({super.key, this.footer});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stoop content standards',
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Keep the porch worth visiting. Cards that clearly miss these — or '
            'use nude/pornographic avatars — are removed.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          for (final s in kStoopStandards)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(s.icon, size: 18, color: AppColors.iconSecondary(context)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          s.body,
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (footer != null) ...[
            Divider(height: 22, color: AppColors.borderOf(context)),
            footer!,
          ],
        ],
      ),
    );
  }
}
