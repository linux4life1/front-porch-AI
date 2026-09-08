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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'background_settings_dialog.dart';

part 'ui_settings_dialog.theme.dart';
part 'ui_settings_dialog.controls.dart';
part 'ui_settings_dialog.updates.dart';

class UiSettingsDialog extends StatefulWidget {
  final CharacterCard? character;

  /// When set with [onThemeOverrides], theme reads/writes stay on this
  /// object (Waifu Coder). Chat keeps using [ChatService.sessionThemeOverrides].
  final ChatThemeOverrides? themeOverrides;
  final ValueChanged<ChatThemeOverrides>? onThemeOverrides;

  const UiSettingsDialog({
    super.key,
    this.character,
    this.themeOverrides,
    this.onThemeOverrides,
  });

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

  /// Re-exposes the protected [setState] for the `part of` extensions
  /// (`ui_settings_dialog.*.dart`), which hold the theme preset picker,
  /// appearance/color controls, and persistence helpers but can't call a
  /// State's protected members directly.
  void rebuildState(VoidCallback fn) => setState(fn);

  ChatThemeOverrides? _boundTheme;

  ChatThemeOverrides _themeOf(ChatService chat) {
    if (widget.onThemeOverrides != null) {
      return _boundTheme ?? widget.themeOverrides ?? ChatThemeOverrides();
    }
    return chat.sessionThemeOverrides;
  }

  void _commitTheme(ChatService chat, ChatThemeOverrides next) {
    if (widget.onThemeOverrides != null) {
      _boundTheme = next;
      widget.onThemeOverrides!(next);
      rebuildState(() {});
      return;
    }
    chat.sessionThemeOverrides = next;
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
    final overrides = _themeOf(chatService);
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
                  chatService: chatService,
                  themeColor: hasTheme
                      ? overrides.resolvedUserBubbleColor(activePreset)
                      : null,
                  globalColor: storageService.globalUserBubbleColor,
                  charColor: _characterNotifier
                      .value
                      ?.frontPorchExtensions
                      ?.userBubbleColor,
                ),
                (color) => _updateUserBubbleColor(context, color),
              ),
              _buildColorRow(
                context,
                'User Text',
                _themeAwareColor(
                  chatService: chatService,
                  themeColor: hasTheme
                      ? overrides.resolvedUserTextColor(activePreset)
                      : null,
                  globalColor: storageService.globalUserTextColor,
                  charColor: _characterNotifier
                      .value
                      ?.frontPorchExtensions
                      ?.userTextColor,
                ),
                (color) => _updateUserTextColor(context, color),
              ),
              _buildColorRow(
                context,
                'AI Bubble',
                _themeAwareColor(
                  chatService: chatService,
                  themeColor: hasTheme
                      ? overrides.resolvedAiBubbleColor(activePreset)
                      : null,
                  globalColor: storageService.globalAiBubbleColor,
                  charColor: _characterNotifier
                      .value
                      ?.frontPorchExtensions
                      ?.aiBubbleColor,
                ),
                (color) => _updateAiBubbleColor(context, color),
              ),
              _buildColorRow(
                context,
                'AI Text',
                _themeAwareColor(
                  chatService: chatService,
                  themeColor: hasTheme
                      ? overrides.resolvedAiTextColor(activePreset)
                      : null,
                  globalColor: storageService.globalAiTextColor,
                  charColor: _characterNotifier
                      .value
                      ?.frontPorchExtensions
                      ?.aiTextColor,
                ),
                (color) => _updateAiTextColor(context, color),
              ),
              _buildColorRow(
                context,
                'Dialogue (Quoted)',
                _themeAwareColor(
                  chatService: chatService,
                  themeColor: hasTheme
                      ? overrides.resolvedDialogueColor(activePreset)
                      : null,
                  globalColor: storageService.globalDialogueColor,
                  charColor: _characterNotifier
                      .value
                      ?.frontPorchExtensions
                      ?.dialogueColor,
                ),
                (color) => _updateDialogueColor(context, color),
              ),
              _buildColorRow(
                context,
                'Actions (*text*)',
                _themeAwareColor(
                  chatService: chatService,
                  themeColor: hasTheme
                      ? overrides.resolvedActionColor(activePreset)
                      : null,
                  globalColor: storageService.globalActionColor,
                  charColor: _characterNotifier
                      .value
                      ?.frontPorchExtensions
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

  /// Resolves which color a Chat Colors row shows: an active session theme
  /// override wins, otherwise falls back to the per-character extension
  /// color (if any) and finally the global preference.
  Color _themeAwareColor({
    required ChatService chatService,
    required Color? themeColor,
    required Color globalColor,
    required Color? charColor,
  }) {
    final overrides = _themeOf(chatService);
    if (overrides.hasTheme && themeColor != null) return themeColor;
    return charColor ?? globalColor;
  }
}
