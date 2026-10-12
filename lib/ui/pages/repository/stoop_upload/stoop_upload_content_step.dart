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

import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_adult_lock_banner.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_comments_switch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_completeness_panel.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_standards.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Upload wizard step 2 — NSFW flag + the character-agency acknowledgement +
/// completeness.
class StoopUploadContentStep extends StatelessWidget {
  final StoopCompleteness? completeness;
  final bool forcedAdult;
  final bool adultValue;
  final bool castPending;
  final bool commentsEnabled;
  final bool standardsAck;
  final ValueChanged<bool> onAdultChanged;
  final ValueChanged<bool> onCommentsChanged;
  final ValueChanged<bool?> onStandardsAckChanged;

  const StoopUploadContentStep({
    super.key,
    required this.completeness,
    required this.forcedAdult,
    required this.adultValue,
    required this.castPending,
    required this.commentsEnabled,
    required this.standardsAck,
    required this.onAdultChanged,
    required this.onCommentsChanged,
    required this.onStandardsAckChanged,
  });

  @override
  Widget build(BuildContext context) {
    final completeness = this.completeness;
    return ListView(
      key: const ValueKey('content'),
      padding: const EdgeInsets.all(24),
      children: [
        if (completeness != null) ...[
          StoopCompletenessPanel(completeness: completeness),
          const SizedBox(height: 16),
        ],
        if (forcedAdult) ...[
          const StoopAdultLockBanner(),
          const SizedBox(height: 16),
        ],
        StoopAdultSwitch(
          key: const Key('stoop-adult-switch'),
          value: adultValue,
          locked: forcedAdult,
          pending: castPending,
          onChanged: onAdultChanged,
        ),
        const SizedBox(height: 12),
        StoopCommentsSwitch(
          key: const Key('stoop-comments-opt-in'),
          value: commentsEnabled,
          onChanged: onCommentsChanged,
        ),
        const SizedBox(height: 20),
        StoopStandardsCard(
          footer: CheckboxListTile(
            value: standardsAck,
            onChanged: onStandardsAckChanged,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            activeColor: AppColors.stoopAmber,
            checkColor: AppColors.stoopAmberInk,
            title: Text(
              'This card meets the Stoop content standards',
              style: TextStyle(
                color: stoopCream(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'I confirm this card meets every standard above — and complies '
              'with The Stoop Acceptable Use Policy.',
              style: TextStyle(color: stoopCream2(context)),
            ),
          ),
        ),
      ],
    );
  }
}
