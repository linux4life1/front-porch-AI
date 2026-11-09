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
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Settings → Appearance: Chat typography controls uniting reading scale
/// and chat typeface with live feedback.
class ChatTypographySection extends StatelessWidget {
  const ChatTypographySection({super.key});

  /// Curated chat-suitable Google Fonts. ('' == the UI font.)
  static const List<(String, String)> chatFonts = [
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
          // Reading scale header + value badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
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
                    'Scales message bubbles and transcript text',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                    color: AppColors.porchAmberOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Slider(
            key: const ValueKey('appearance-reading-size'),
            value: scale,
            min: 0.7,
            max: 2.0,
            divisions: 13,
            label: '$percent%',
            onChanged: (val) => ui.setTextScale(val),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          // Chat Font Dropdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                constraints: const BoxConstraints(maxWidth: 240),
                child: DropdownButton<String>(
                  key: const ValueKey('appearance-chat-font'),
                  value: chatFonts.any(
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
                  items: chatFonts.map((font) {
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
                  onChanged: (value) => ui.setGlobalChatFontFamily(value ?? ''),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
