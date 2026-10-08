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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';

import 'launch_choice_row.dart';

/// "Free graphics memory when idle", in Advanced Launch Options: off, or how
/// long KoboldCpp may sit with nothing to do before its model is unloaded.
/// Chips like the Prefill Batch Size row above it. Takes effect at once.
class KoboldIdleUnloadRow extends StatelessWidget {
  const KoboldIdleUnloadRow({
    super.key,
    required this.settings,
    required this.accent,
  });

  final BackendSettings settings;
  final Color accent;

  @override
  Widget build(BuildContext context) => LaunchChoiceRow(
    title: 'Free graphics memory when idle',
    blurb:
        'Unloads the model when KoboldCpp has had nothing to do for this '
        'long, so other programs can use the graphics memory. The first '
        'reply after that takes longer to start.',
    choices: kKoboldIdleUnloadChoices,
    chosen: settings.idleUnloadMinutes,
    label: koboldIdleUnloadLabel,
    onChoose: settings.setIdleUnloadMinutes,
    accent: accent,
  );
}
