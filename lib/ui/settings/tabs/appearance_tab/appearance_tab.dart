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
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'accent_picker_row.dart';
import 'appearance_choice.dart';
import 'background_weather_section.dart';
import 'chat_appearance_section.dart';
import 'theme_card_grid.dart';

/// Settings → Appearance: the app theme, light/dark/system mode, accent, UI
/// font and corners, then the chat's own colors, font, and reading size.
class AppearanceTab extends StatelessWidget {
  const AppearanceTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<StorageService>().appearance;
    final corners = AppCorners.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 540;
        return SingleChildScrollView(
          padding: EdgeInsets.all(constraints.maxWidth < 360 ? 12 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Section 1: Theme & Chrome ─────────────────────────────
              const SectionHeader('Theme & Chrome'),
              const SizedBox(height: 12),
              const ThemeCardGrid(),
              const SizedBox(height: 14),

              // Shell Controls Container Card (Mode, Font, Corners)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerOf(context),
                  borderRadius: corners.circular(12),
                  border: Border.all(
                    color: AppColors.borderOf(context),
                    width: 1,
                  ),
                ),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 14,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    AppearanceChoice<AppThemeMode>(
                      key: const ValueKey('appearance-mode'),
                      label: 'Brightness Mode',
                      values: AppThemeMode.values,
                      selected: appearance.mode,
                      labelOf: (m) => m.label,
                      onChanged: appearance.setMode,
                    ),
                    AppearanceChoice<UiFont>(
                      key: const ValueKey('appearance-font'),
                      label: 'UI Typeface',
                      values: UiFont.values,
                      selected: appearance.font,
                      labelOf: (f) => f.label,
                      onChanged: appearance.setFont,
                    ),
                    AppearanceChoice<UiCorners>(
                      key: const ValueKey('appearance-corners'),
                      label: 'Corner Roundness',
                      values: UiCorners.values,
                      selected: appearance.corners,
                      labelOf: (c) => c.label,
                      onChanged: appearance.setCorners,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Accent Bar with Theme Default Pill & Swatches
              const AccentPickerRow(),

              const SizedBox(height: 12),

              // Reset Shell Customisations
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('appearance-reset'),
                  onPressed: appearance.resetCustomisations,
                  icon: constraints.maxWidth < 360
                      ? null
                      : const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Reset accent, font and corners'),
                ),
              ),

              const SizedBox(height: 28),

              // ── Section 2: Chat Typography & Scale + Section 3: Palette ─
              const ChatAppearanceSection(),

              const SizedBox(height: 28),

              // ── Section 4: Atmosphere & Immersion ─────────────────────────
              const SectionHeader('Atmosphere & Immersion'),
              const SizedBox(height: 12),
              if (isNarrow) ...[
                const BackgroundWeatherSection(),
                const SizedBox(height: 12),
                const MoodOnCharacterControls(),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: const BackgroundWeatherSection()),
                    const SizedBox(width: 14),
                    Expanded(child: const MoodOnCharacterControls()),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
