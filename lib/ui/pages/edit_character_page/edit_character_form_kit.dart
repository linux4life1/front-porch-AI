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
import 'package:front_porch_ai/ui/widgets/widgets.dart';

// Theme-aware surfaces (dark values identical to the old hardcoded navy
// tokens, so dark mode is unchanged; light mode finally gets light).
const _borderFocus = AppColors.formMasterAccent;

/// The character editor's shared section card, field and label builders,
/// resolved against the [context] of the tab that builds them.
class EditCharacterFormKit {
  final BuildContext context;

  const EditCharacterFormKit(this.context);

  /// Glassmorphic section card with icon header.
  Widget sectionCard({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> children,
    Widget? trailing,
    bool collapsed = false,
  }) {
    final header = Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    );

    if (collapsed) {
      // Material, not a decorated Container: ExpansionTile's header is a
      // ListTile, which paints its background and ink splash onto the nearest
      // Material ancestor — a coloured DecoratedBox in between swallows the
      // ripple. Flutter 3.44 asserts on this ("ListTile background color or
      // ink splashes may be invisible"). Same colour, radius and border; the
      // header ripple now actually renders.
      return Material(
        color: AppColors.cardOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.45),
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            title: Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconColor: AppColors.iconSecondary(context),
            collapsedIconColor: AppColors.iconSecondary(context),
            children: children,
          ),
        ),
      );
    }

    // Same Material surface as the collapsed ExpansionTile path — Alternate
    // Greetings (and any other section) can host ListTiles/SwitchListTiles,
    // and a coloured DecoratedBox between them and the scaffold Material
    // trips Flutter's "ink may be invisible" assert.
    return Material(
      color: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: AppColors.borderOf(context).withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [header, const SizedBox(height: 16), ...children],
        ),
      ),
    );
  }

  /// Styled text field matching the manual creator design.
  Widget styledField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    bool expandable = false,
    bool enabled = true,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            fieldLabel(label),
            if (expandable) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () => showExpandedEditorDialog(
                  context: context,
                  title: label,
                  controller: controller,
                  hintText: 'Enter $label...',
                ),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Tooltip(
                    message: 'Open fullscreen editor',
                    child: Icon(
                      Icons.open_in_full,
                      size: 14,
                      color: AppColors.resolve(
                        context,
                        Colors.white.withValues(alpha: 0.25),
                        Colors.black.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        AppTextField(
          controller: controller,
          maxLines: maxLines,
          enabled: enabled,
          style: TextStyle(
            color: enabled
                ? AppColors.textPrimary(context)
                : AppColors.textTertiary(context),
            fontSize: 14,
          ),
          decoration: inputDecoration(hint ?? 'Enter $label...'),
        ),
      ],
    );
  }

  Widget fieldLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  InputDecoration inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: AppColors.textTertiary(context),
        fontSize: 13,
      ),
      filled: true,
      fillColor: AppColors.backgroundOf(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppColors.borderOf(context).withValues(alpha: 0.45),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppColors.borderOf(context).withValues(alpha: 0.45),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _borderFocus),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppColors.resolve(
            context,
            Colors.white.withValues(alpha: 0.04),
            Colors.black.withValues(alpha: 0.04),
          ),
        ),
      ),
      contentPadding: const EdgeInsets.all(14),
    );
  }
}
