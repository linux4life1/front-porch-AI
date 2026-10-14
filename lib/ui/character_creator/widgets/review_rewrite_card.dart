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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/greeting_card_parts.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// A rewrite row (the profile, the example dialogue, the lorebook): a steer
/// field and the outlined action, or Stop while it writes; an optional
/// caption under it and the last error. The button drops under a steer box
/// that would be narrower than 280, as the greeting cards do.
class ReviewRewriteRow extends StatelessWidget {
  const ReviewRewriteRow({
    super.key,
    required this.id,
    required this.steer,
    required this.hint,
    required this.action,
    required this.writing,
    required this.onRun,
    required this.onStop,
    this.locked = false,
    this.grows = false,
    this.caption,
    this.error,
  });

  /// Key prefix: `<id>-steer`, `<id>-run`, `<id>-stop`, `<id>-error`.
  final String id;
  final TextEditingController steer;
  final String hint;
  final String action;
  final bool writing;
  final VoidCallback onRun;
  final VoidCallback onStop;

  /// Something else holds the model; the action waits.
  final bool locked;
  final bool grows;
  final String? caption;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final field = GreetingSteerField(
      key: ValueKey('$id-steer'),
      controller: steer,
      enabled: !writing,
      hint: hint,
      grows: grows,
    );
    final button = writing
        ? GreetingStopButton(key: ValueKey('$id-stop'), onPressed: onStop)
        : GreetingRegenerateButton(
            key: ValueKey('$id-run'),
            label: action,
            onPressed: locked ? null : onRun,
          );
    final muted = StudioColors.mutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 280 + 10 + 200) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [field, button],
              );
            }
            return Row(
              crossAxisAlignment: grows
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              spacing: 10,
              children: [
                Expanded(child: field),
                button,
              ],
            );
          },
        ),
        if (caption != null)
          Text(
            caption!,
            style: TextStyle(fontSize: 12, height: 1.5, color: muted),
          ),
        if (error != null)
          GreetingErrorLine(key: ValueKey('$id-error'), text: error!),
      ],
    );
  }
}

/// One lorebook entry on the Review card (docs/design/creator-ui-spec.md,
/// "Lorebook entry row"): `bg` fill, 1px `line`, radius 12, padding 10×14;
/// the name at 180px, a one-line preview, and "Edited by hand" when the
/// entry is no longer the generator's text. [onToggle] adds the keep
/// checkbox (the editor view); [onEdit] opens the entry.
class ReviewLoreRow extends StatelessWidget {
  const ReviewLoreRow({
    super.key,
    required this.entry,
    required this.editedByHand,
    required this.onEdit,
    this.kept,
    this.onToggle,
  });

  final LorebookEntry entry;
  final bool editedByHand;
  final VoidCallback onEdit;
  final bool? kept;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final line = StudioColors.lineOf(context);
    final muted = StudioColors.mutedOf(context);
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: StudioColors.bgOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: kept == false ? line.withValues(alpha: 0.4) : line,
          ),
        ),
        child: Row(
          spacing: 12,
          children: [
            if (onToggle != null)
              SizedBox.square(
                dimension: 20,
                child: Checkbox(
                  value: kept ?? true,
                  onChanged: (v) => onToggle!(v ?? true),
                ),
              ),
            SizedBox(
              width: 180,
              child: Text(
                entry.name.isEmpty ? 'Untitled entry' : entry.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: StudioColors.inkOf(context),
                ),
              ),
            ),
            Expanded(
              child: Text(
                entry.content.replaceAll('\n', ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: muted),
              ),
            ),
            if (editedByHand)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: line),
                ),
                child: Text(
                  'Edited by hand',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
