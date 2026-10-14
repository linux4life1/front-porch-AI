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
/// title, an optional subtitle 10px after it and an optional [trailing] at
/// the right, then [children]. A [writing] card takes the 1.5px amber edge
/// at 60% ("Writing card").
class CreatorCardShell extends StatelessWidget {
  const CreatorCardShell({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleAmber = false,
    this.writing = false,
    this.trailing,
    required this.children,
  });

  final String title;
  final String? subtitle;

  /// The subtitle in amber 12 / 600 ("Writing…", "Re-read after the
  /// rewrite") instead of muted.
  final bool subtitleAmber;
  final bool writing;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: StudioColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: writing
            ? Border.all(color: amber.withValues(alpha: 0.6), width: 1.5)
            : Border.all(color: StudioColors.lineOf(context)),
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
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: subtitleAmber ? FontWeight.w600 : null,
                            color: subtitleAmber
                                ? amber
                                : StudioColors.mutedOf(context),
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
/// sections and the profile cards): `bg` fill, 1px `line`, radius 12,
/// padding 12×14, 15 / 1.55, min-height 96. The header's expand button
/// opens the box in the full-screen editor.
///
/// With [writingText] the card is a writing card: the box shows that text
/// read-only (with the 2×16 amber caret when [caret]), the box's own text
/// is left alone (Stop has nothing to undo), and the expand button waits
/// at 35%.
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
    this.writingText,
    this.caret = false,
    this.status,
    this.statusAmber = false,
    this.boxKey,
    this.locked = false,
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

  final String? writingText;
  final bool caret;

  /// Shown in place of [subtitle] ("Writing…", "Kept as it is").
  final String? status;
  final bool statusAmber;
  final Key? boxKey;

  /// The box is read-only and dimmed like a waiting button (the Automated
  /// description while a rewrite runs: it is kept verbatim, so typing then
  /// would be thrown away).
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final writing = writingText != null;
    return CreatorCardShell(
      title: title,
      subtitle: status ?? subtitle,
      subtitleAmber: status != null && statusAmber,
      writing: writing,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?trailing,
          Opacity(
            opacity: writing || locked ? 0.35 : 1,
            child: IconButton(
              tooltip: 'Open $title in the full editor',
              onPressed: writing || locked
                  ? null
                  : () => showExpandedEditorDialog(
                      context: context,
                      title: title,
                      controller: controller,
                    ),
              icon: const Icon(Icons.open_in_full, size: 18),
              color: StudioColors.proseOf(context),
              disabledColor: StudioColors.proseOf(context),
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
      children: [
        Semantics(
          label: '$title text',
          child: writing
              ? _writingBox(context)
              : locked
              ? Opacity(opacity: 0.35, child: _box(context))
              : _box(context),
        ),
        ...below,
      ],
    );
  }

  TextStyle _style(BuildContext context) =>
      TextStyle(color: StudioColors.inkOf(context), fontSize: 15, height: 1.55);

  Widget _box(BuildContext context) {
    OutlineInputBorder outline(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c),
    );
    final line = StudioColors.lineOf(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 96),
      child: AppTextField(
        key: boxKey,
        controller: controller,
        readOnly: locked,
        minLines: minLines,
        maxLines: maxLines,
        onChanged: onChanged,
        style: _style(context),
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
    );
  }

  Widget _writingBox(BuildContext context) => Container(
    key: boxKey,
    constraints: const BoxConstraints(minHeight: 96),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: StudioColors.bgOf(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: StudioColors.lineOf(context)),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(text: writingText),
          if (caret)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                width: 2,
                height: 16,
                margin: const EdgeInsets.only(left: 2),
                color: StudioColors.amberOf(context),
              ),
            ),
        ],
      ),
      style: _style(context),
    ),
  );
}
