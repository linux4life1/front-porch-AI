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

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Work days as a person says them, the twin of the phone's `workDaysText`:
/// runs of days collapse ("Mon–Fri", "Mon–Thu, Sat"), one day is its name,
/// all seven are "Every day", and none is the Mon–Fri default.
String workDaysText(List<int>? days) {
  final set = {...?days}.where((d) => d >= 1 && d <= 7).toList()..sort();
  if (set.isEmpty) return 'Mon–Fri';
  if (set.length == 7) return 'Every day';
  final runs = <String>[];
  var start = set.first;
  var prev = start;
  void close() => runs.add(
    start == prev
        ? _weekdays[start - 1]
        : '${_weekdays[start - 1]}–${_weekdays[prev - 1]}',
  );
  for (final d in set.skip(1)) {
    if (d == prev + 1) {
      prev = d;
      continue;
    }
    close();
    start = prev = d;
  }
  close();
  return runs.join(', ');
}

/// [field] with a muted [suffix] beside it, or under it when the two do
/// not fit side by side with the field at least 120px wide.
Widget factFieldWithSuffix(
  BuildContext context, {
  required Widget field,
  required String suffix,
}) {
  final style = TextStyle(fontSize: 13, color: StudioColors.mutedOf(context));
  final text = Text(suffix, style: style);
  return LayoutBuilder(
    builder: (context, c) {
      final painter = TextPainter(
        text: TextSpan(text: suffix, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final fits = painter.width + 8 + 120 <= c.maxWidth;
      painter.dispose();
      if (fits) {
        return Row(
          spacing: 8,
          children: [
            Expanded(child: field),
            text,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [field, text],
      );
    },
  );
}
