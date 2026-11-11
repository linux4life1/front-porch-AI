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
import 'package:front_porch_ai/ui/settings/dialogs/color_picker_dialog.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'chat_capsule_preview.dart';
import 'chat_color_matrix.dart';
import 'mood_on_character_controls.dart';

/// Settings → Appearance → Chat Appearance: Reading Size, Chat Font,
/// live micro-chat preview, and paired message color controls.
class ChatAppearanceSection extends StatelessWidget {
  const ChatAppearanceSection({super.key});

  /// Curated chat-suitable Google Fonts. ('' == the UI font.)
  static const List<(String, String)> _chatFonts = [
    ('Same as the UI font', ''),
    ('Roboto', 'Roboto'),
    ('Open Sans', 'Open Sans'),
    ('Lato', 'Lato'),
    ('Source Sans 3', 'Source Sans 3'),
    ('Nunito', 'Nunito'),
    ('Poppins', 'Poppins'),
    ('Montserrat', 'Montserrat'),
    ('Raleway', 'Raleway'),
    ('Work Sans', 'Work Sans'),
    ('DM Sans', 'DM Sans'),
    ('Quicksand', 'Quicksand'),
    ('Rubik', 'Rubik'),
    ('Karla', 'Karla'),
    ('Merriweather', 'Merriweather'),
    ('Playfair Display', 'Playfair Display'),
    ('Roboto Mono', 'Roboto Mono'),
    ('Fira Code', 'Fira Code'),
  ];

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final ui = storageService.uiSettings;
    final scale = ui.textScale;
    final percent = (scale * 100).round();
    final corners = AppCorners.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Chat Appearance'),
        const SizedBox(height: 12),

        // ── Typography & Scale Card ──────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: corners.circular(12),
            border: Border.all(
              color: AppColors.borderOf(context),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reading Size',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Scales chat bubbles and transcript text',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerOf(context),
                      borderRadius: corners.circular(6),
                      border: Border.all(
                        color: AppColors.borderOf(context),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      '$percent%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.formAccentOf(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Slider(
                key: const ValueKey('appearance-reading-size'),
                value: scale,
                min: 0.7,
                max: 2.0,
                divisions: 13,
                label: '$percent%',
                onChanged: (val) => ui.setTextScale(val),
              ),
              const SizedBox(height: 8),
              Divider(
                height: 1,
                color: AppColors.borderOf(context).withValues(alpha: 0.5),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Chat Font',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: DropdownButton<String>(
                        key: const ValueKey('appearance-chat-font'),
                        value: _chatFonts.any(
                          (f) => f.$2 == ui.globalChatFontFamily,
                        )
                            ? ui.globalChatFontFamily
                            : '',
                        isExpanded: true,
                        focusColor: Colors.transparent,
                        dropdownColor: AppColors.cardOf(context),
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 13,
                        ),
                        underline: const SizedBox.shrink(),
                        items: _chatFonts.map((font) {
                          return DropdownMenuItem<String>(
                            value: font.$2,
                            child: Text(
                              font.$1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: font.$2.isEmpty ? null : font.$2,
                                color: AppColors.textPrimary(context),
                                fontSize: 13,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) =>
                            ui.setGlobalChatFontFamily(value ?? ''),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Live WYSIWYG Capsule Preview ─────────────────────────────────
        ChatCapsulePreview(
          onTapAiBubble: () => showColorPicker(
            context,
            ui.globalAiBubbleColor,
            ui.setGlobalAiBubbleColor,
          ),
          onTapUserBubble: () => showColorPicker(
            context,
            ui.globalUserBubbleColor,
            ui.setGlobalUserBubbleColor,
          ),
        ),

        const SizedBox(height: 12),

        // ── Paired Color Matrix ──────────────────────────────────────────
        const ChatColorMatrix(),

        const SizedBox(height: 8),

        // ── Reset to Theme Defaults Button ───────────────────────────────
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('chat-colors-use-theme'),
            onPressed: storageService.uiSettings.resetChatColors,
            icon: const Icon(Icons.format_color_reset_outlined, size: 18),
            label: const Text('Use the theme\'s chat colors'),
          ),
        ),
      ],
    );
  }
}
