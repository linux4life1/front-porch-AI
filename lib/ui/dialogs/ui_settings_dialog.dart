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
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/dialogs/ui_settings/ui_settings.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'background_settings_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    _characterNotifier = ValueNotifier<CharacterCard?>(widget.character);
  }

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
      setState(() {});
      return;
    }
    chat.sessionThemeOverrides = next;
  }

  @override
  void dispose() {
    _characterNotifier.dispose();
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
              ChatThemePresetPicker(
                overrides: overrides,
                onSelected: (next) => _commitTheme(chatService, next),
              ),

              if (hasTheme) ...[
                const SizedBox(height: 16),
                ChatThemeDropdownRow(
                  label: 'Font',
                  value: overrides.fontFamily ?? activePreset.defaultFontFamily,
                  options: kChatThemeFontOptions,
                  optionStyle: (f) => TextStyle(fontFamily: f),
                  overridden: overrides.fontFamily != null,
                  onChanged: (val) {
                    overrides.fontFamily = val == activePreset.defaultFontFamily
                        ? null
                        : val;
                    _commitTheme(chatService, overrides);
                  },
                  onReset: () {
                    overrides.fontFamily = null;
                    _commitTheme(chatService, overrides);
                  },
                ),
                ChatThemeDropdownRow(
                  label: 'Border',
                  value:
                      overrides.borderStyle ?? activePreset.defaultBorderStyle,
                  options: kChatThemeBorderStyles,
                  optionStyle: (_) => const TextStyle(fontSize: 12),
                  overridden: overrides.borderStyle != null,
                  onChanged: (val) {
                    overrides.borderStyle =
                        val == activePreset.defaultBorderStyle ? null : val;
                    _commitTheme(chatService, overrides);
                  },
                  onReset: () {
                    overrides.borderStyle = null;
                    _commitTheme(chatService, overrides);
                  },
                ),
                ChatColorRow(
                  label: 'Border',
                  color:
                      overrides.resolvedBorderColor(activePreset) ??
                      activePreset.defaultUserTextColor,
                  onChanged: (color) {
                    overrides.borderColor = chatColorToHex(color);
                    _commitTheme(chatService, overrides);
                  },
                ),
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
              UiSettingsSlider(
                label: 'Bubble Opacity',
                value: storageService.uiSettings.bubbleOpacity,
                min: 0.1,
                max: 1.0,
                onChanged: (val) =>
                    storageService.uiSettings.setBubbleOpacity(val),
                divisions: 18,
              ),
              const SizedBox(height: 4),
              UiSettingsSlider(
                label: 'Reading Size',
                value: storageService.uiSettings.textScale.clamp(
                  kReadingScaleMin,
                  kReadingScaleMax,
                ),
                min: kReadingScaleMin,
                max: kReadingScaleMax,
                onChanged: (val) => storageService.uiSettings.setTextScale(val),
                divisions: 13,
              ),
              if (_characterNotifier.value != null) ...[
                const SizedBox(height: 8),
                AvatarLockToggle(
                  locked:
                      _characterNotifier
                          .value!
                          .frontPorchExtensions
                          ?.avatarLocked ??
                      false,
                  onChanged: (val) async {
                    _updateAvatarLocked(context, val);
                  },
                ),
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
              for (final slot in ChatColorSlot.values)
                ChatColorRow(
                  label: slot.label,
                  color: _themeAwareColor(
                    chatService: chatService,
                    themeColor: hasTheme
                        ? slot.themeColor(overrides, activePreset)
                        : null,
                    globalColor: slot.globalColor(storageService),
                    charColor: slot.characterColor(
                      _characterNotifier.value?.frontPorchExtensions,
                    ),
                  ),
                  onChanged: (color) => _updateChatColor(context, slot, color),
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
                  onPressed: () => showWarmDialogOf<void>(
                    context,
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

  /// When a theme is active, writes go to session theme overrides (or the
  /// bound Waifu overrides when [UiSettingsDialog.onThemeOverrides] is set).
  /// When no theme, writes go to per-character extensions or global prefs.
  bool _hasActiveTheme(ChatService chatService) =>
      _themeOf(chatService).hasTheme;

  Future<void> _updateChatColor(
    BuildContext context,
    ChatColorSlot slot,
    Color color,
  ) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    if (_hasActiveTheme(chatService)) {
      final o = _themeOf(chatService);
      slot.writeTheme(o, chatColorToHex(color));
      _commitTheme(chatService, o);
      return;
    }
    final character = _characterNotifier.value;
    if (character != null) {
      await _updateCharacterExtension(
        context,
        (e) => slot.writeCharacter(e, color),
      );
    } else {
      await slot.writeGlobal(storage, color);
    }
  }

  Future<void> _updateAvatarLocked(BuildContext context, bool locked) =>
      _updateCharacterExtension(
        context,
        (e) => e.copyWith(avatarLocked: locked),
      );

  Future<void> _updateCharacterExtension(
    BuildContext context,
    FrontPorchExtensions Function(FrontPorchExtensions) mutate,
  ) async {
    final character = _characterNotifier.value;
    if (character == null) return;
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    final updatedCharacter = await saveCharacterExtension(
      charRepo,
      character,
      mutate,
    );
    setState(() {
      _characterNotifier.value = updatedCharacter;
    });
  }
}
