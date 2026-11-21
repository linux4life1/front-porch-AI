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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The line under a group's greyed Memory switch: the global Memory setting
/// (the 1:1 one) is off, so no chat uses memory, and the group's own choice is
/// kept for when it is on. The wording is shared with the PWA.
class MemoryOffEverywhereNote extends StatelessWidget {
  const MemoryOffEverywhereNote({super.key});

  static const text =
      "Memory is off for every chat. Turn it on in a one-on-one chat's "
      "sidebar. This group's choice is kept.";

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: AppColors.textTertiary(context)),
    ),
  );
}
