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

import 'package:front_porch_ai/services/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The preset store and the model follower of one [StorageService].
typedef GenPresetHandles = ({
  GenPresetSettings presets,
  GenPresetFollower follower,
});

/// [storage]'s presets, or null on a test double that has none; every
/// preset control hides then, so older screens render as they did.
GenPresetHandles? genPresetsOf(StorageService storage) {
  try {
    return (presets: storage.genPresets, follower: storage.genPresetFollower);
  } on NoSuchMethodError {
    return null;
  }
}

/// What a per-value reset puts back for one field, and where it comes from.
typedef ResetTarget = ({double value, String source});

/// The ↺ target for the field [pick] reads: the model's recommended value
/// when it has one, else the app default.
ResetTarget? resetTargetFor(
  RecommendedSamplers? rec,
  num? Function(SamplerValues v) pick,
) {
  if (rec == null) return null;
  final value = pick(rec.resetValues);
  if (value == null) return null;
  final fromModel = pick(rec.values) != null;
  return (
    value: value.toDouble(),
    source: fromModel ? rec.sourceWords : 'app default',
  );
}

/// Builds [builder] with the current model's recommended samplers, rebuilt
/// when they change; null when [storage] has no presets.
class RecommendedSamplersBuilder extends StatelessWidget {
  const RecommendedSamplersBuilder({
    super.key,
    required this.storage,
    required this.builder,
  });

  final StorageService storage;
  final Widget Function(BuildContext context, RecommendedSamplers? rec) builder;

  @override
  Widget build(BuildContext context) {
    final handles = genPresetsOf(storage);
    if (handles == null) return builder(context, null);
    return ValueListenableBuilder<RecommendedSamplers>(
      valueListenable: handles.follower.recommended,
      builder: (context, rec, _) => builder(context, rec),
    );
  }
}

/// The small ↺ beside a value.
class ValueResetButton extends StatelessWidget {
  const ValueResetButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: const Icon(Icons.restart_alt, size: 18),
      color: AppColors.textTertiary(context),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}
