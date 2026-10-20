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

/// Reading size, the global chat colors and the chat font, moved here from
/// General. Colors left unpicked follow the app theme's own defaults.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SliderSetting(
          label: 'Reading Size',
          value: storageService.uiSettings.textScale,
          min: 0.7,
          max: 2.0,
          onChanged: (val) => storageService.uiSettings.setTextScale(val),
          divisions: 13,
        ),
        const SectionHeader('Chat Appearance'),
        const SizedBox(height: 8),
        ColorRow(
          label: 'User Bubble',
          color: storageService.uiSettings.globalUserBubbleColor,
          onPressed: () => showColorPicker(
            context,
            storageService.uiSettings.globalUserBubbleColor,
            (color) =>
                storageService.uiSettings.setGlobalUserBubbleColor(color),
          ),
        ),
        ColorRow(
          label: 'User Text',
          color: storageService.uiSettings.globalUserTextColor,
          onPressed: () => showColorPicker(
            context,
            storageService.uiSettings.globalUserTextColor,
            (color) => storageService.uiSettings.setGlobalUserTextColor(color),
          ),
        ),
        ColorRow(
          label: 'AI Bubble',
          color: storageService.uiSettings.globalAiBubbleColor,
          onPressed: () => showColorPicker(
            context,
            storageService.uiSettings.globalAiBubbleColor,
            (color) => storageService.uiSettings.setGlobalAiBubbleColor(color),
          ),
        ),
        ColorRow(
          label: 'AI Text',
          color: storageService.uiSettings.globalAiTextColor,
          onPressed: () => showColorPicker(
            context,
            storageService.uiSettings.globalAiTextColor,
            (color) => storageService.uiSettings.setGlobalAiTextColor(color),
          ),
        ),
        ColorRow(
          label: 'Dialogue (Quoted)',
          color: storageService.uiSettings.globalDialogueColor,
          onPressed: () => showColorPicker(
            context,
            storageService.uiSettings.globalDialogueColor,
            (color) => storageService.uiSettings.setGlobalDialogueColor(color),
          ),
        ),
        ColorRow(
          label: 'Actions (*text*)',
          color: storageService.uiSettings.globalActionColor,
          onPressed: () => showColorPicker(
            context,
            storageService.uiSettings.globalActionColor,
            (color) => storageService.uiSettings.setGlobalActionColor(color),
          ),
        ),
        const SizedBox(height: 12),
        // Global chat font — per-character overrides still win at render time
        // (UiSettings.getChatFontFamily). Restored after a refactor left only
        // a placeholder here; the setter had no other UI caller.
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
                  color: AppColors.textSecondary(context),
                  fontSize: 13,
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: DropdownButton<String>(
                  // Clamp to a known item — a stored family not in the list
                  // (older build / manual pref edit) would otherwise assert.
                  value:
                      _chatFonts.any(
                        (f) =>
                            f.$2 ==
                            storageService.uiSettings.globalChatFontFamily,
                      )
                      ? storageService.uiSettings.globalChatFontFamily
                      : '',
                  isExpanded: true,
                  // The button keeps focus after a pick; the theme's grey
                  // focus wash then sat over the chosen font for good.
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
                  onChanged: (value) => storageService.uiSettings
                      .setGlobalChatFontFamily(value ?? ''),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
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
