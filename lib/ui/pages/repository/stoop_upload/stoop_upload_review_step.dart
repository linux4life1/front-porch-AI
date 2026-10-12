// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_adult_lock_banner.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_completeness_panel.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_pick_step.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_world_share.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Upload wizard step 3 — review + publish. Exactly one of [selectedCard],
/// [selectedGroup], [selectedWorld] is set. Text fields arrive trimmed.
class StoopUploadReviewStep extends StatelessWidget {
  final CharacterCard? selectedCard;
  final GroupChat? selectedGroup;
  final World? selectedWorld;
  final StoopCompleteness? completeness;
  final String name;
  final String summary;
  final String originalCreator;
  final bool adultValue;
  final bool forcedAdult;
  final List<String> tags;
  final String? error;

  const StoopUploadReviewStep({
    super.key,
    required this.selectedCard,
    required this.selectedGroup,
    required this.selectedWorld,
    required this.completeness,
    required this.name,
    required this.summary,
    required this.originalCreator,
    required this.adultValue,
    required this.forcedAdult,
    required this.tags,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final world = selectedWorld;
    final group = selectedGroup;
    final isGroup = group != null;
    final preview = world != null
        ? stoopWorldCoverPreview(
            context,
            coverBytes: decodeWorldCoverBytes(world.coverImage),
          )
        : isGroup
        ? Container(
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: stoopTealSoft(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: StoopGroupMontage(group: group),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(selectedCard!.imagePath!),
              width: 96,
              height: 96,
              fit: BoxFit.cover,
            ),
          );
    return ListView(
      key: const ValueKey('review'),
      padding: const EdgeInsets.all(24),
      children: [
        if (completeness != null) ...[
          StoopCompletenessPanel(completeness: completeness!),
          const SizedBox(height: 16),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            preview,
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: stoopDisplay(context, size: 21)),
                  const SizedBox(height: 4),
                  Text(summary, style: TextStyle(color: stoopCream2(context))),
                  if (originalCreator.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'created by $originalCreator',
                      style: TextStyle(
                        color: stoopFaint(context),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  if (adultValue) ...[
                    const SizedBox(height: 8),
                    const StoopBadge(StoopBadgeKind.nsfw),
                  ],
                ],
              ),
            ),
          ],
        ),
        // Last surface before Submit — say why that badge is there.
        if (forcedAdult) ...[
          const SizedBox(height: 18),
          const StoopAdultLockBanner(),
        ],
        const SizedBox(height: 18),
        if (tags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in tags)
                Text('#$t', style: TextStyle(color: stoopTealText(context))),
            ],
          ),
        const SizedBox(height: 20),
        Text(
          'Your submission will be reviewed by a moderator before it appears '
          'on The Stoop. You’ll get a message in the app when it’s approved or '
          'if changes are needed.',
          style: TextStyle(color: stoopMute(context), height: 1.5),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(error!, style: TextStyle(color: stoopEmberText(context))),
        ],
      ],
    );
  }
}
