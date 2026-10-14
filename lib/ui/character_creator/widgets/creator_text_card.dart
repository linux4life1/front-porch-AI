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

import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The spec's card (docs/design/creator-ui-spec.md, "Card"): `card` fill,
/// 1px `line`, radius 16, padding 20, 12px gap; a header row with an h3
/// title, an optional muted subtitle and an optional [trailing] at the
/// right, then [children].
class CreatorCardShell extends StatelessWidget {
  const CreatorCardShell({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: StudioColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StudioColors.lineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(
              spacing: 10,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: StudioColors.inkOf(context),
                  ),
                ),
                Expanded(
                  child: subtitle == null
                      ? const SizedBox.shrink()
                      : Text(
                          subtitle!,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: StudioColors.mutedOf(context),
                          ),
                        ),
                ),
                ?trailing,
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// A [CreatorCardShell] around one macro-coloured text box (the Review
/// sections, and the profile step's cards later): `bg` fill, 1px `line`,
/// radius 12, padding 12×14, 15 / 1.55, min-height 96. The header's expand
/// button opens the box in the full-screen editor.
class CreatorTextCard extends StatelessWidget {
  const CreatorTextCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.controller,
    this.minLines = 3,
    this.maxLines = 8,
    this.onChanged,
    this.trailing,
    this.below = const [],
  });

  final String title;
  final String? subtitle;
  final TextEditingController controller;
  final int minLines;
  final int maxLines;

  /// Typing hook (a creator box calls `CreatorState.scheduleSave()`).
  final ValueChanged<String>? onChanged;

  /// Extra header actions, left of the expand button.
  final Widget? trailing;

  /// Widgets under the box, inside the card.
  final List<Widget> below;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder outline(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c),
    );
    final line = StudioColors.lineOf(context);
    return CreatorCardShell(
      title: title,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?trailing,
          IconButton(
            tooltip: 'Open $title in the full editor',
            onPressed: () => showExpandedEditorDialog(
              context: context,
              title: title,
              controller: controller,
            ),
            icon: const Icon(Icons.open_in_full, size: 18),
            color: StudioColors.proseOf(context),
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
      children: [
        Semantics(
          label: '$title text',
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 96),
            child: AppTextField(
              controller: controller,
              minLines: minLines,
              maxLines: maxLines,
              onChanged: onChanged,
              style: TextStyle(
                color: StudioColors.inkOf(context),
                fontSize: 15,
                height: 1.55,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: StudioColors.bgOf(context),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: outline(line),
                enabledBorder: outline(line),
                focusedBorder: outline(StudioColors.amberOf(context)),
              ),
            ),
          ),
        ),
        ...below,
      ],
    );
  }
}
