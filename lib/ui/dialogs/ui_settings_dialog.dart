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
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/chat_theme_preset.dart';
import 'package:front_porch_ai/models/chat_theme_overrides.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'background_settings_dialog.dart';

class UiSettingsDialog extends StatefulWidget {
  final CharacterCard? character;

  const UiSettingsDialog({super.key, this.character});

  @override
  State<UiSettingsDialog> createState() => _UiSettingsDialogState();
}

class _UiSettingsDialogState extends State<UiSettingsDialog> {
  late ValueNotifier<CharacterCard?> _characterNotifier;
  final ScrollController _themeScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _characterNotifier = ValueNotifier<CharacterCard?>(widget.character);
  }

  @override
  void dispose() {
    _characterNotifier.dispose();
    _themeScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final chatService = Provider.of<ChatService>(context);
    final overrides = chatService.sessionThemeOverrides;
    final activePreset = ChatThemePreset.byId(overrides.themeId);
    final hasTheme = activePreset != null;

    return Dialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _characterNotifier.value != null
                        ? '${_characterNotifier.value!.name} - UI Settings'
                        : 'UI Settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: AppColors.iconSecondary(context),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Chat Theme ──────────────────────────────────────────────
              const Text(
                'Chat Theme',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.formMasterAccent,
                ),
              ),
              const SizedBox(height: 8),
              if (overrides.isCustomized)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${activePreset?.displayName ?? 'Theme'} (Customized)',
                    style: TextStyle(
                      color: AppColors.porchAmberOf(context),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              _buildPresetPicker(chatService),

              if (hasTheme) ...[
                const SizedBox(height: 16),
                _buildFontRow(overrides, activePreset, chatService),
                _buildBorderStyleRow(overrides, activePreset, chatService),
                _buildBorderColorRow(overrides, activePreset, chatService),
              ],

              const SizedBox(height: 20),

              // ── Appearance ──────────────────────────────────────────────
              const Text(
                'Appearance',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.formMasterAccent,
                ),
              ),
              const SizedBox(height: 12),
              _buildSlider(
                'Bubble Opacity',
                storageService.bubbleOpacity,
                0.1,
                1.0,
                (val) => storageService.setBubbleOpacity(val),
                divisions: 18,
              ),
              const SizedBox(height: 4),
              _buildSlider(
                'Chat Text Size',
                storageService.textScale,
                0.5,
                2.0,
                (val) => storageService.setTextScale(val),
                divisions: 30,
              ),
              if (_characterNotifier.value != null) ...[
                const SizedBox(height: 8),
                _buildAvatarLockedToggle(context),
              ],
              const SizedBox(height: 20),

              // ── Chat Colors ─────────────────────────────────────────────
              const Text(
                'Chat Colors',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.formMasterAccent,
                ),
              ),
              const SizedBox(height: 12),
              _buildColorRow(
                context,
                'User Bubble',
                _themeAwareColor(
                  storage: storageService,
                  chatService: chatService,
                  character: _characterNotifier.value,
                  themeColor: hasTheme
                      ? overrides.resolvedUserBubbleColor(activePreset)
                      : null,
                  globalColor: storageService.globalUserBubbleColor,
                  charColor:
                      _characterNotifier.value?.frontPorchExtensions
                          ?.userBubbleColor,
                ),
                (color) => _updateUserBubbleColor(context, color),
              ),
              _buildColorRow(
                context,
                'User Text',
                _themeAwareColor(
                  storage: storageService,
                  chatService: chatService,
                  character: _characterNotifier.value,
                  themeColor: hasTheme
                      ? overrides.resolvedUserTextColor(activePreset)
                      : null,
                  globalColor: storageService.globalUserTextColor,
                  charColor:
                      _characterNotifier.value?.frontPorchExtensions
                          ?.userTextColor,
                ),
                (color) => _updateUserTextColor(context, color),
              ),
              _buildColorRow(
                context,
                'AI Bubble',
                _themeAwareColor(
                  storage: storageService,
                  chatService: chatService,
                  character: _characterNotifier.value,
                  themeColor: hasTheme
                      ? overrides.resolvedAiBubbleColor(activePreset)
                      : null,
                  globalColor: storageService.globalAiBubbleColor,
                  charColor:
                      _characterNotifier.value?.frontPorchExtensions
                          ?.aiBubbleColor,
                ),
                (color) => _updateAiBubbleColor(context, color),
              ),
              _buildColorRow(
                context,
                'AI Text',
                _themeAwareColor(
                  storage: storageService,
                  chatService: chatService,
                  character: _characterNotifier.value,
                  themeColor: hasTheme
                      ? overrides.resolvedAiTextColor(activePreset)
                      : null,
                  globalColor: storageService.globalAiTextColor,
                  charColor:
                      _characterNotifier.value?.frontPorchExtensions
                          ?.aiTextColor,
                ),
                (color) => _updateAiTextColor(context, color),
              ),
              _buildColorRow(
                context,
                'Dialogue (Quoted)',
                _themeAwareColor(
                  storage: storageService,
                  chatService: chatService,
                  character: _characterNotifier.value,
                  themeColor: hasTheme
                      ? overrides.resolvedDialogueColor(activePreset)
                      : null,
                  globalColor: storageService.globalDialogueColor,
                  charColor:
                      _characterNotifier.value?.frontPorchExtensions
                          ?.dialogueColor,
                ),
                (color) => _updateDialogueColor(context, color),
              ),
              _buildColorRow(
                context,
                'Actions (*text*)',
                _themeAwareColor(
                  storage: storageService,
                  chatService: chatService,
                  character: _characterNotifier.value,
                  themeColor: hasTheme
                      ? overrides.resolvedActionColor(activePreset)
                      : null,
                  globalColor: storageService.globalActionColor,
                  charColor:
                      _characterNotifier.value?.frontPorchExtensions
                          ?.actionColor,
                ),
                (color) => _updateActionColor(context, color),
              ),
              const SizedBox(height: 20),

              // ── Chat Background ─────────────────────────────────────────
              const Text(
                'Chat Background',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.formMasterAccent,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (ctx) => const BackgroundSettingsDialog(),
                  ),
                  icon: const Icon(Icons.image, size: 18),
                  label: const Text('Manage Chat Backgrounds'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary(context),
                    side: BorderSide(color: AppColors.borderOf(context)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _themeAwareColor({
    required StorageService storage,
    required ChatService chatService,
    required CharacterCard? character,
    required Color? themeColor,
    required Color globalColor,
    required Color? charColor,
  }) {
    final overrides = chatService.sessionThemeOverrides;
    if (overrides.hasTheme && themeColor != null) return themeColor;
    return charColor ?? globalColor;
  }

  /// Ink that stays legible over an arbitrary user-picked swatch color (the
  /// color-picker swatches and the current-color chip can be any hue, so no
  /// fixed chrome color can guarantee contrast).
  static Color _swatchInk(Color bg) =>
      ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
      ? Colors.white
      : Colors.black87; // theme-keep: contrast over a user-chosen color

  // ── Theme preset picker ──────────────────────────────────────────────────

  Widget _buildPresetPicker(ChatService chatService) {
    final overrides = chatService.sessionThemeOverrides;

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
                      chatService.sessionThemeOverrides = ChatThemeOverrides();
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
                    chatService.sessionThemeOverrides =
                        ChatThemeOverrides(themeId: preset.id);
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

  static const _fontOptions = [
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

  static const _borderStyles = [
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
                    overrides.fontFamily =
                        val == preset.defaultFontFamily ? null : val;
                    chatService.sessionThemeOverrides = overrides;
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
                chatService.sessionThemeOverrides = overrides;
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
                    overrides.borderStyle =
                        val == preset.defaultBorderStyle ? null : val;
                    chatService.sessionThemeOverrides = overrides;
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
                chatService.sessionThemeOverrides = overrides;
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
    final currentColor = overrides.resolvedBorderColor(preset) ?? preset.defaultUserTextColor;
    return _buildColorRow(
      context,
      'Border',
      currentColor,
      (color) {
        final hex = color
            .toARGB32()
            .toRadixString(16)
            .padLeft(8, '0')
            .substring(2)
            .toUpperCase();
        overrides.borderColor = hex;
        chatService.sessionThemeOverrides = overrides;
      },
    );
  }

  // ── Appearance controls ──────────────────────────────────────────────────

  Widget _buildAvatarLockedToggle(BuildContext context) {
    final character = _characterNotifier.value!;
    final locked = character.frontPorchExtensions?.avatarLocked ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lock Avatar Size',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
              Text(
                'Avatar won\'t grow past default size when sidebar is wider',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: locked,
          onChanged: (val) async {
            _updateAvatarLocked(context, val);
          },
          activeTrackColor: AppColors.formMasterAccent,
        ),
      ],
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int? divisions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: AppColors.formMasterAccent,
          inactiveColor: AppColors.borderOf(context),
        ),
      ],
    );
  }

  Widget _buildColorRow(
    BuildContext context,
    String label,
    Color color,
    void Function(Color) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderOf(context), width: 1),
            ),
            child: IconButton(
              icon: Icon(
                Icons.color_lens,
                size: 20,
                color: _swatchInk(color),
              ),
              onPressed: () => _showColorPicker(context, color, onChanged),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showColorPicker(
    BuildContext context,
    Color initialColor,
    void Function(Color) onChanged,
  ) async {
    const presetColors = [
      Color(0xFF3B82F6),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFF14B8A6),
      Color(0xFFF97316),
      Color(0xFF6366F1),
      Color(0xFF06B6D4),
      Color(0xFF10B981),
      Color(0xFF84CC16),
    ];

    Color selectedColor = initialColor;
    void Function(void Function())? setStateCallback;

    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          setStateCallback = setState;
          return AlertDialog(
            title: const Text('Select Color'),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Quick Select',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: presetColors
                          .map(
                            (color) => GestureDetector(
                              onTap: () => Navigator.pop(context, color),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: color == selectedColor
                                        ? AppColors.formMasterAccent
                                        : AppColors.borderOf(context),
                                    width: 2,
                                  ),
                                ),
                                child: color == selectedColor
                                    ? Icon(
                                        Icons.check,
                                        size: 18,
                                        color: _swatchInk(color),
                                      )
                                    : null,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ColorPicker(
                        color: selectedColor,
                        onColorChanged: (color) {
                          selectedColor = color;
                          setStateCallback?.call(() {});
                        },
                        wheelDiameter: 160,
                        pickersEnabled: const <ColorPickerType, bool>{
                          ColorPickerType.wheel: true,
                        },
                        showColorCode: true,
                        colorCodeHasColor: true,
                        copyPasteBehavior: const ColorPickerCopyPasteBehavior(
                          copyButton: true,
                          pasteButton: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, selectedColor),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.formMasterAccent,
                  foregroundColor: AppColors.onChaosAccent,
                ),
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
    if (picked != null) {
      onChanged(picked);
    }
  }

  // ── Color update helpers with dual-routing ───────────────────────────────

  /// When a theme is active, writes go to session theme overrides.
  /// When no theme, writes go to per-character extensions or global prefs.
  bool _hasActiveTheme(ChatService chatService) =>
      chatService.sessionThemeOverrides.hasTheme;

  Future<void> _updateUserBubbleColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    if (_hasActiveTheme(chatService)) {
      final o = chatService.sessionThemeOverrides;
      o.userBubbleColor = _colorToHex(color);
      chatService.sessionThemeOverrides = o;
      return;
    }
    final character = _characterNotifier.value;
    if (character != null) {
      await _updateCharacterExtension(context, (e) => e.copyWith(userBubbleColor: color));
    } else {
      await storage.setGlobalUserBubbleColor(color);
    }
  }

  Future<void> _updateUserTextColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    if (_hasActiveTheme(chatService)) {
      final o = chatService.sessionThemeOverrides;
      o.userTextColor = _colorToHex(color);
      chatService.sessionThemeOverrides = o;
      return;
    }
    final character = _characterNotifier.value;
    if (character != null) {
      await _updateCharacterExtension(context, (e) => e.copyWith(userTextColor: color));
    } else {
      await storage.setGlobalUserTextColor(color);
    }
  }

  Future<void> _updateAiBubbleColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    if (_hasActiveTheme(chatService)) {
      final o = chatService.sessionThemeOverrides;
      o.aiBubbleColor = _colorToHex(color);
      chatService.sessionThemeOverrides = o;
      return;
    }
    final character = _characterNotifier.value;
    if (character != null) {
      await _updateCharacterExtension(context, (e) => e.copyWith(aiBubbleColor: color));
    } else {
      await storage.setGlobalAiBubbleColor(color);
    }
  }

  Future<void> _updateAiTextColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    if (_hasActiveTheme(chatService)) {
      final o = chatService.sessionThemeOverrides;
      o.aiTextColor = _colorToHex(color);
      chatService.sessionThemeOverrides = o;
      return;
    }
    final character = _characterNotifier.value;
    if (character != null) {
      await _updateCharacterExtension(context, (e) => e.copyWith(aiTextColor: color));
    } else {
      await storage.setGlobalAiTextColor(color);
    }
  }

  Future<void> _updateDialogueColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    if (_hasActiveTheme(chatService)) {
      final o = chatService.sessionThemeOverrides;
      o.dialogueColor = _colorToHex(color);
      chatService.sessionThemeOverrides = o;
      return;
    }
    final character = _characterNotifier.value;
    if (character != null) {
      await _updateCharacterExtension(context, (e) => e.copyWith(dialogueColor: color));
    } else {
      await storage.setGlobalDialogueColor(color);
    }
  }

  Future<void> _updateActionColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    if (_hasActiveTheme(chatService)) {
      final o = chatService.sessionThemeOverrides;
      o.actionColor = _colorToHex(color);
      chatService.sessionThemeOverrides = o;
      return;
    }
    final character = _characterNotifier.value;
    if (character != null) {
      await _updateCharacterExtension(context, (e) => e.copyWith(actionColor: color));
    } else {
      await storage.setGlobalActionColor(color);
    }
  }

  Future<void> _updateAvatarLocked(BuildContext context, bool locked) async {
    final character = _characterNotifier.value;
    if (character == null) return;

    final currentExtensions =
        character.frontPorchExtensions ?? FrontPorchExtensions();
    final updatedExtensions = currentExtensions.copyWith(avatarLocked: locked);
    updatedExtensions.ensureStableId();
    final updatedCharacter = _cloneCharacter(character, updatedExtensions);
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    await charRepo.updateCharacter(updatedCharacter);
    setState(() {
      _characterNotifier.value = updatedCharacter;
    });
  }

  Future<void> _updateCharacterExtension(
    BuildContext context,
    FrontPorchExtensions Function(FrontPorchExtensions) mutate,
  ) async {
    final character = _characterNotifier.value;
    if (character == null) return;
    final currentExtensions =
        character.frontPorchExtensions ?? FrontPorchExtensions();
    final updatedExtensions = mutate(currentExtensions);
    updatedExtensions.ensureStableId();
    final updatedCharacter = _cloneCharacter(character, updatedExtensions);
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    await charRepo.updateCharacter(updatedCharacter);
    setState(() {
      _characterNotifier.value = updatedCharacter;
    });
  }

  CharacterCard _cloneCharacter(
    CharacterCard character,
    FrontPorchExtensions extensions,
  ) {
    final updated = CharacterCard(
      name: character.name,
      description: character.description,
      personality: character.personality,
      scenario: character.scenario,
      firstMessage: character.firstMessage,
      mesExample: character.mesExample,
      systemPrompt: character.systemPrompt,
      postHistoryInstructions: character.postHistoryInstructions,
      alternateGreetings: List.from(character.alternateGreetings),
      tags: List.from(character.tags),
      imagePath: character.imagePath,
      folderId: character.folderId,
      lorebook: character.lorebook != null
          ? Lorebook(entries: List.from(character.lorebook!.entries))
          : null,
      worldNames: List.from(character.worldNames),
      ttsVoice: character.ttsVoice,
      frontPorchExtensions: extensions,
      rawExtensions: character.rawExtensions != null
          ? Map<String, dynamic>.from(character.rawExtensions!)
          : null,
      avatarImages: character.avatarImages != null
          ? List.from(character.avatarImages!)
          : null,
    )..dbId = character.dbId;
    return updated;
  }

  String _colorToHex(Color c) =>
      c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
}
