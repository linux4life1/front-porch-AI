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

part of 'ui_settings_dialog.dart';

const _fontOptions = [
  'serif',
  'sans-serif',
  'monospace',
  'Georgia',
  'Times New Roman',
  'Arial',
  'Helvetica',
  'Courier New',
  'Verdana',
  'Roboto',
  'Open Sans',
  'Lato',
  'Merriweather',
  'Playfair Display',
  'Source Code Pro',
];

const _borderStyles = [
  'scalloped',
  'dualLine',
  'grid',
  'wavy',
  'shadow',
  'vine',
  'wave',
  'glitch',
  'floral',
  'gear',
  'greekKey',
];

/// Chat Theme section of [UiSettingsDialog]: the horizontal preset picker
/// (None + every [ChatThemePreset]) and, once a theme is active, the
/// font/border-style/border-color override rows. Extracted verbatim from
/// UiSettingsDialog; direct state access preserves behavior.
extension _UiSettingsThemeSection on _UiSettingsDialogState {
  // ── Theme preset picker ──────────────────────────────────────────────────

  Widget _buildPresetPicker(ChatService chatService) {
    final overrides = _themeOf(chatService);

    return Row(
      children: [
        IconButton(
          icon: Icon(
            Icons.chevron_left,
            color: AppColors.textTertiary(context),
          ),
          constraints: const BoxConstraints(minWidth: 28, minHeight: 72),
          padding: EdgeInsets.zero,
          onPressed: () {
            final offset = _themeScrollController.offset;
            _themeScrollController.animateTo(
              (offset - 144).clamp(
                0,
                _themeScrollController.position.maxScrollExtent,
              ),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
          },
        ),
        Expanded(
          child: SizedBox(
            height: 72,
            child: ListView.separated(
              controller: _themeScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: ChatThemePreset.presets.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isSelected = !overrides.hasTheme;
                  return GestureDetector(
                    onTap: () {
                      _commitTheme(chatService, ChatThemeOverrides());
                    },
                    child: Container(
                      width: 64,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.porchAmberOf(
                                context,
                              ).withValues(alpha: 0.15)
                            : AppColors.surfaceContainerOf(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.formMasterAccent
                              : AppColors.borderOf(context),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'None',
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                }
                final preset = ChatThemePreset.presets[index - 1];
                final isSelected = overrides.themeId == preset.id;
                return GestureDetector(
                  onTap: () {
                    _commitTheme(
                      chatService,
                      ChatThemeOverrides(themeId: preset.id),
                    );
                  },
                  child: Container(
                    width: 64,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerOf(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.formMasterAccent
                            : AppColors.borderOf(context),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: preset.defaultUserBubbleColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: preset.defaultAiBubbleColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          preset.displayName,
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          preset.defaultBorderStyle,
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.chevron_right,
            color: AppColors.textTertiary(context),
          ),
          constraints: const BoxConstraints(minWidth: 28, minHeight: 72),
          padding: EdgeInsets.zero,
          onPressed: () {
            final offset = _themeScrollController.offset;
            _themeScrollController.animateTo(
              (offset + 144).clamp(
                0,
                _themeScrollController.position.maxScrollExtent,
              ),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
          },
        ),
      ],
    );
  }

  // ── Theme font / border controls ─────────────────────────────────────────

  Widget _buildFontRow(
    ChatThemeOverrides overrides,
    ChatThemePreset preset,
    ChatService chatService,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Text(
            'Font',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(6),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: overrides.fontFamily ?? preset.defaultFontFamily,
                dropdownColor: AppColors.surfaceContainerOf(context),
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 12,
                ),
                items: _fontOptions
                    .map(
                      (f) => DropdownMenuItem(
                        value: f,
                        child: Text(f, style: TextStyle(fontFamily: f)),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    overrides.fontFamily = val == preset.defaultFontFamily
                        ? null
                        : val;
                    _commitTheme(chatService, overrides);
                  }
                },
              ),
            ),
          ),
          if (overrides.fontFamily != null)
            IconButton(
              icon: Icon(
                Icons.restart_alt,
                size: 14,
                color: AppColors.porchAmberOf(context),
              ),
              onPressed: () {
                overrides.fontFamily = null;
                _commitTheme(chatService, overrides);
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _buildBorderStyleRow(
    ChatThemeOverrides overrides,
    ChatThemePreset preset,
    ChatService chatService,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Text(
            'Border',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(6),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: overrides.borderStyle ?? preset.defaultBorderStyle,
                dropdownColor: AppColors.surfaceContainerOf(context),
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 12,
                ),
                items: _borderStyles
                    .map(
                      (b) => DropdownMenuItem(
                        value: b,
                        child: Text(b, style: const TextStyle(fontSize: 12)),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    overrides.borderStyle = val == preset.defaultBorderStyle
                        ? null
                        : val;
                    _commitTheme(chatService, overrides);
                  }
                },
              ),
            ),
          ),
          if (overrides.borderStyle != null)
            IconButton(
              icon: Icon(
                Icons.restart_alt,
                size: 14,
                color: AppColors.porchAmberOf(context),
              ),
              onPressed: () {
                overrides.borderStyle = null;
                _commitTheme(chatService, overrides);
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _buildBorderColorRow(
    ChatThemeOverrides overrides,
    ChatThemePreset preset,
    ChatService chatService,
  ) {
    final currentColor =
        overrides.resolvedBorderColor(preset) ?? preset.defaultUserTextColor;
    return _buildColorRow(context, 'Border', currentColor, (color) {
      overrides.borderColor = _colorToHex(color);
      _commitTheme(chatService, overrides);
    });
  }
}
