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

import 'package:front_porch_ai/ui/character_creator/widgets/creator_input_label.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/synced_text_field.dart';

/// The facts card's pieces (docs/design/creator-ui-spec.md, "Field"): the
/// spec label 6px above its control, a 40px field (`bg`, 1px `line`, radius
/// 10, 12px side padding, 14px ink) and its read-only twin.

/// [label] over [child].
Widget factLabelled(String label, Widget child) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  spacing: 6,
  children: [CreatorInputLabel(label), child],
);

/// An editable fact. Synced, so a rebuild per keystroke keeps the caret.
Widget factField(
  BuildContext context, {
  Key? key,
  required String value,
  required ValueChanged<String> onChanged,
  String? hint,
  bool readOnly = false,
}) => SyncedTextField(
  key: key,
  value: value,
  onChanged: onChanged,
  readOnly: readOnly,
  style: TextStyle(fontSize: 14, color: StudioColors.inkOf(context)),
  decoration: InputDecoration(
    isDense: true,
    hintText: hint,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
  ),
);

/// A fact shown as a field but edited elsewhere (the opening stance).
Widget factReadOnly(BuildContext context, String value) => Container(
  height: 40,
  alignment: Alignment.centerLeft,
  padding: const EdgeInsets.symmetric(horizontal: 12),
  decoration: BoxDecoration(
    color: StudioColors.bgOf(context),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: StudioColors.lineOf(context)),
  ),
  child: Text(
    value,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: 14, color: StudioColors.proseOf(context)),
  ),
);
