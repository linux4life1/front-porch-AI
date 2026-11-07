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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Whether Porch Life runs Needs at all. While it does not, every Needs
/// switch (a 1:1 chat's, a group chat's, a group's for new chats) greys out
/// at its own value with [NeedsOffInPorchLifeNote]: the choice is kept for
/// when Porch Life turns Needs back on. Listens, so a switch follows Porch
/// Life live. Allowed without a StorageService above (widget goldens).
bool porchLifeAllowsNeedsOf(BuildContext context) {
  try {
    return Provider.of<StorageService>(context).realismSettings.needsSimDefault;
  } on ProviderNotFoundException {
    return true;
  }
}

/// The line under a greyed Needs switch: where to look, and that [kept]
/// (whose choice) is not lost.
class NeedsOffInPorchLifeNote extends StatelessWidget {
  const NeedsOffInPorchLifeNote({
    super.key,
    this.kept = "This chat's choice is kept.",
  });

  final String kept;

  @override
  Widget build(BuildContext context) => Text(
    'Off in Porch Life, so no chat runs Needs. $kept',
    style: TextStyle(fontSize: 11, color: AppColors.textTertiary(context)),
  );
}
