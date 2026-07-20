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

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_theme_preset.dart';
import 'package:front_porch_ai/models/chat_theme_overrides.dart';
import 'settings_base.dart';

/// UI / theme / chat presentation settings (bubble colors/opacity, fonts,
/// dark mode, backgrounds, display buffer, sort/grid, effective color helpers).
///
/// Lifted from StorageService (Stage 7). Shims preserve getUserBubbleColor etc.
/// Note: effective *Color / getChatFontFamily take optional CharacterCard for
/// per-card overrides (frontPorchExtensions) and fall back to globals.
class UiSettings with SettingsBase {
  double _bubbleOpacity = 1.0;

  // Global chat color defaults
  Color _globalUserBubbleColor = const Color(0xFF3B82F6);
  Color _globalUserTextColor = Colors.white;
  Color _globalAiBubbleColor = const Color(0xFF374151);
  Color _globalAiTextColor = Colors.white;
  Color _globalDialogueColor = Colors.amberAccent;
  Color _globalActionColor = const Color(0xFF90CAF9);

  // Global chat font family
  String _globalChatFontFamily = '';

  // Theme mode (persisted; drives which set of the 5 chat colors is active)
  bool _isDark = true;

  // Light-mode chat color defaults (populated from AppColors on first load if no prefs)
  Color _lightUserBubbleColor = AppColors.userBubbleLight;
  Color _lightUserTextColor = AppColors.userTextLight;
  Color _lightAiBubbleColor = AppColors.aiBubbleLight;
  Color _lightAiTextColor = AppColors.aiTextLight;
  Color _lightDialogueColor = AppColors.dialogueLight;
  Color _lightActionColor = AppColors.actionLight;

  double _textScale = 1.0;
  String _chatBackground = 'none';
  List<Map<String, String>> _customBackgrounds = [];
  bool _displayBufferEnabled = false;
  double _targetDisplayTps = 6.0; // ~250 WPM average human reading speed
  double _bufferDurationSeconds = 3.0;
  String _sortMode = 'name'; // 'name', 'recent', 'importDate'
  double _gridScale = 300.0; // maxCrossAxisExtent in pixels (150-450)

  // Chat-sidebar accordion expansion (persisted per group id so the layout
  // survives restarts). Ids: author_note / character_state / journal_memory /
  // story_tools.
  final Map<String, bool> _sidebarGroupExpanded = {};
  static const List<String> _sidebarGroupIds = [
    'author_note',
    'character_state',
    'journal_memory',
    'story_tools',
  ];

  double get bubbleOpacity => _bubbleOpacity;
  Color get globalUserBubbleColor =>
      _isDark ? _globalUserBubbleColor : _lightUserBubbleColor;
  Color get globalUserTextColor =>
      _isDark ? _globalUserTextColor : _lightUserTextColor;
  Color get globalAiBubbleColor =>
      _isDark ? _globalAiBubbleColor : _lightAiBubbleColor;
  Color get globalAiTextColor =>
      _isDark ? _globalAiTextColor : _lightAiTextColor;
  Color get globalDialogueColor =>
      _isDark ? _globalDialogueColor : _lightDialogueColor;
  Color get globalActionColor =>
      _isDark ? _globalActionColor : _lightActionColor;
  bool get isDark => _isDark;
  String get globalChatFontFamily => _globalChatFontFamily;
  double get textScale => _textScale;
  String get chatBackground => _chatBackground;
  List<Map<String, String>> get customBackgrounds =>
      List.unmodifiable(_customBackgrounds);
  bool get displayBufferEnabled => _displayBufferEnabled;
  double get targetDisplayTps => _targetDisplayTps;
  double get bufferDurationSeconds => _bufferDurationSeconds;
  String get sortMode => _sortMode;
  double get gridScale => _gridScale;

  void load() {
    _bubbleOpacity = prefs?.getDouble(k('bubble_opacity')) ?? _bubbleOpacity;
    _globalUserBubbleColor = Color(
      prefs?.getInt(k('global_user_bubble_color')) ??
          _globalUserBubbleColor.toARGB32(),
    );
    _globalUserTextColor = Color(
      prefs?.getInt(k('global_user_text_color')) ??
          _globalUserTextColor.toARGB32(),
    );
    _globalAiBubbleColor = Color(
      prefs?.getInt(k('global_ai_bubble_color')) ??
          _globalAiBubbleColor.toARGB32(),
    );
    _globalAiTextColor = Color(
      prefs?.getInt(k('global_ai_text_color')) ?? _globalAiTextColor.toARGB32(),
    );
    _globalDialogueColor = Color(
      prefs?.getInt(k('global_dialogue_color')) ??
          _globalDialogueColor.toARGB32(),
    );
    _globalActionColor = Color(
      prefs?.getInt(k('global_action_color')) ?? _globalActionColor.toARGB32(),
    );
    _globalChatFontFamily =
        prefs?.getString(k('global_chat_font_family')) ?? _globalChatFontFamily;

    // Theme + light-mode color set (fall back to AppColors light defaults if never saved)
    _isDark = prefs?.getBool(k('dark_mode')) ?? true;
    _lightUserBubbleColor = Color(
      prefs?.getInt(k('light_user_bubble_color')) ??
          AppColors.userBubbleLight.toARGB32(),
    );
    _lightUserTextColor = Color(
      prefs?.getInt(k('light_user_text_color')) ??
          AppColors.userTextLight.toARGB32(),
    );
    _lightAiBubbleColor = Color(
      prefs?.getInt(k('light_ai_bubble_color')) ??
          AppColors.aiBubbleLight.toARGB32(),
    );
    _lightAiTextColor = Color(
      prefs?.getInt(k('light_ai_text_color')) ??
          AppColors.aiTextLight.toARGB32(),
    );
    _lightDialogueColor = Color(
      prefs?.getInt(k('light_dialogue_color')) ??
          AppColors.dialogueLight.toARGB32(),
    );
    _lightActionColor = Color(
      prefs?.getInt(k('light_action_color')) ??
          AppColors.actionLight.toARGB32(),
    );

    _textScale = prefs?.getDouble(k('text_scale')) ?? 1.0;
    _chatBackground = prefs?.getString(k('chat_background')) ?? 'none';
    final customBgJson = prefs?.getString(k('custom_backgrounds'));
    if (customBgJson != null) {
      try {
        _customBackgrounds = (jsonDecode(customBgJson) as List)
            .map((e) => Map<String, String>.from(e as Map))
            .toList();
      } catch (_) {
        _customBackgrounds = [];
      }
    }
    // Force token throttle OFF for all users (existing preference deleted)
    prefs?.remove(k('display_buffer_enabled'));
    _displayBufferEnabled = false;
    _targetDisplayTps = prefs?.getDouble(k('target_display_tps')) ?? 30.0;
    _bufferDurationSeconds =
        prefs?.getDouble(k('buffer_duration_seconds')) ?? 3.0;

    _sortMode = prefs?.getString(k('sort_mode')) ?? 'name';
    _gridScale = prefs?.getDouble(k('grid_scale')) ?? 300.0;

    for (final id in _sidebarGroupIds) {
      final v = prefs?.getBool(k('sidebar_group_expanded_$id'));
      if (v != null) _sidebarGroupExpanded[id] = v;
    }
  }

  /// Whether a sidebar accordion group is expanded (falls back to the
  /// caller-provided default when the user never toggled it).
  bool sidebarGroupExpanded(String id, {required bool fallback}) =>
      _sidebarGroupExpanded[id] ?? fallback;

  Future<void> setSidebarGroupExpanded(String id, bool value) async {
    _sidebarGroupExpanded[id] = value;
    await prefs?.setBool(k('sidebar_group_expanded_$id'), value);
    notify();
  }

  Future<void> setBubbleOpacity(double value) async {
    _bubbleOpacity = value;
    await prefs?.setDouble(k('bubble_opacity'), value);
    notify();
  }

  Future<void> setGlobalUserBubbleColor(Color value) async {
    if (_isDark) {
      _globalUserBubbleColor = value;
      await prefs?.setInt(k('global_user_bubble_color'), value.toARGB32());
    } else {
      _lightUserBubbleColor = value;
      await prefs?.setInt(k('light_user_bubble_color'), value.toARGB32());
    }
    notify();
  }

  Future<void> setGlobalUserTextColor(Color value) async {
    if (_isDark) {
      _globalUserTextColor = value;
      await prefs?.setInt(k('global_user_text_color'), value.toARGB32());
    } else {
      _lightUserTextColor = value;
      await prefs?.setInt(k('light_user_text_color'), value.toARGB32());
    }
    notify();
  }

  Future<void> setGlobalAiBubbleColor(Color value) async {
    if (_isDark) {
      _globalAiBubbleColor = value;
      await prefs?.setInt(k('global_ai_bubble_color'), value.toARGB32());
    } else {
      _lightAiBubbleColor = value;
      await prefs?.setInt(k('light_ai_bubble_color'), value.toARGB32());
    }
    notify();
  }

  Future<void> setGlobalAiTextColor(Color value) async {
    if (_isDark) {
      _globalAiTextColor = value;
      await prefs?.setInt(k('global_ai_text_color'), value.toARGB32());
    } else {
      _lightAiTextColor = value;
      await prefs?.setInt(k('light_ai_text_color'), value.toARGB32());
    }
    notify();
  }

  Future<void> setGlobalDialogueColor(Color value) async {
    if (_isDark) {
      _globalDialogueColor = value;
      await prefs?.setInt(k('global_dialogue_color'), value.toARGB32());
    } else {
      _lightDialogueColor = value;
      await prefs?.setInt(k('light_dialogue_color'), value.toARGB32());
    }
    notify();
  }

  Future<void> setGlobalActionColor(Color value) async {
    if (_isDark) {
      _globalActionColor = value;
      await prefs?.setInt(k('global_action_color'), value.toARGB32());
    } else {
      _lightActionColor = value;
      await prefs?.setInt(k('light_action_color'), value.toARGB32());
    }
    notify();
  }

  Future<void> setGlobalChatFontFamily(String value) async {
    _globalChatFontFamily = value;
    await prefs?.setString(k('global_chat_font_family'), value);
    notify();
  }

  Future<void> setIsDark(bool value) async {
    if (_isDark == value) return;
    _isDark = value;
    await prefs?.setBool(k('dark_mode'), value);
    notify();
  }

  Future<void> setTextScale(double value) async {
    _textScale = value;
    await prefs?.setDouble(k('text_scale'), value);
    notify();
  }

  Future<void> setChatBackground(String value) async {
    _chatBackground = value;
    await prefs?.setString(k('chat_background'), value);
    notify();
  }

  Future<void> addCustomBackground(
    String id,
    String name,
    String filePath,
  ) async {
    _customBackgrounds.add({'id': id, 'name': name, 'filePath': filePath});
    await _persistCustomBackgrounds();
    notify();
  }

  Future<void> removeCustomBackground(String id) async {
    _customBackgrounds.removeWhere((bg) => bg['id'] == id);
    await _persistCustomBackgrounds();
    notify();
  }

  bool hasCustomBackgroundWithName(String name) {
    return _customBackgrounds.any((bg) => bg['name'] == name);
  }

  Future<void> _persistCustomBackgrounds() async {
    await prefs?.setString(
      k('custom_backgrounds'),
      jsonEncode(_customBackgrounds),
    );
  }

  Future<void> setDisplayBufferEnabled(bool value) async {
    _displayBufferEnabled = value;
    await prefs?.setBool(k('display_buffer_enabled'), value);
    notify();
  }

  Future<void> setTargetDisplayTps(double value) async {
    _targetDisplayTps = value;
    await prefs?.setDouble(k('target_display_tps'), value);
    notify();
  }

  Future<void> setBufferDurationSeconds(double value) async {
    _bufferDurationSeconds = value;
    await prefs?.setDouble(k('buffer_duration_seconds'), value);
    notify();
  }

  Future<void> setSortMode(String value) async {
    _sortMode = value;
    await prefs?.setString(k('sort_mode'), value);
    notify();
  }

  Future<void> setGridScale(double value) async {
    _gridScale = value.clamp(150.0, 450.0);
    await prefs?.setDouble(k('grid_scale'), _gridScale);
    notify();
  }

  /// Get effective user bubble color.
  /// Resolution: per-character override → theme override → theme preset → global.
  Color getUserBubbleColor(
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    final charColor = character?.frontPorchExtensions?.userBubbleColor;
    if (charColor != null) return charColor;
    if (themeOverrides?.userBubbleColor != null && themePreset != null) {
      return themeOverrides!.resolvedUserBubbleColor(themePreset);
    }
    if (themePreset != null) return themePreset.defaultUserBubbleColor;
    return _isDark ? _globalUserBubbleColor : _lightUserBubbleColor;
  }

  /// Get effective user text color.
  /// Resolution: per-character override → theme override → theme preset → global.
  Color getUserTextColor(
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    final charColor = character?.frontPorchExtensions?.userTextColor;
    if (charColor != null) return charColor;
    if (themeOverrides?.userTextColor != null && themePreset != null) {
      return themeOverrides!.resolvedUserTextColor(themePreset);
    }
    if (themePreset != null) return themePreset.defaultUserTextColor;
    return _isDark ? _globalUserTextColor : _lightUserTextColor;
  }

  /// Get effective AI bubble color.
  /// Resolution: per-character override → theme override → theme preset → global.
  Color getAiBubbleColor(
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    final charColor = character?.frontPorchExtensions?.aiBubbleColor;
    if (charColor != null) return charColor;
    if (themeOverrides?.aiBubbleColor != null && themePreset != null) {
      return themeOverrides!.resolvedAiBubbleColor(themePreset);
    }
    if (themePreset != null) return themePreset.defaultAiBubbleColor;
    return _isDark ? _globalAiBubbleColor : _lightAiBubbleColor;
  }

  /// Get effective AI text color.
  /// Resolution: per-character override → theme override → theme preset → global.
  Color getAiTextColor(
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    final charColor = character?.frontPorchExtensions?.aiTextColor;
    if (charColor != null) return charColor;
    if (themeOverrides?.aiTextColor != null && themePreset != null) {
      return themeOverrides!.resolvedAiTextColor(themePreset);
    }
    if (themePreset != null) return themePreset.defaultAiTextColor;
    return _isDark ? _globalAiTextColor : _lightAiTextColor;
  }

  /// Get effective dialogue color (per-character overrides global)
  Color getDialogueColor(CharacterCard? character) {
    final fallback = _isDark ? _globalDialogueColor : _lightDialogueColor;
    return character?.frontPorchExtensions?.dialogueColor ?? fallback;
  }

  /// Get effective action color (per-character overrides global)
  Color getActionColor(CharacterCard? character) {
    final fallback = _isDark ? _globalActionColor : _lightActionColor;
    return character?.frontPorchExtensions?.actionColor ?? fallback;
  }

  /// Get effective chat font family.
  /// Resolution: per-character override → theme override → theme preset → global.
  String getChatFontFamily(
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    final charFont = character?.frontPorchExtensions?.chatFontFamily;
    if (charFont != null) return charFont;
    if (themeOverrides?.fontFamily != null && themePreset != null) {
      return themeOverrides!.resolvedFontFamily(themePreset);
    }
    if (themePreset != null) return themePreset.defaultFontFamily;
    return _globalChatFontFamily;
  }
}
