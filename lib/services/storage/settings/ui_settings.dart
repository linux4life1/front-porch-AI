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
import 'package:front_porch_ai/ui/theme/appearance_options.dart';
import 'package:front_porch_ai/ui/theme/chat_default_colors.dart';
import 'package:front_porch_ai/models/models.dart';
import 'appearance_settings.dart';
import 'library_view_prefs.dart';
import 'settings_base.dart';

/// UI / theme / chat presentation settings (bubble colors/opacity, fonts,
/// dark mode, backgrounds, display buffer, effective color helpers). The home
/// library's sort, card size and search scope live in [LibraryViewPrefs].
///
/// Lifted from StorageService (Stage 7). Shims preserve getUserBubbleColor etc.
/// Note: effective *Color / getChatFontFamily take optional CharacterCard for
/// per-card overrides (frontPorchExtensions) and fall back to globals.
class UiSettings with SettingsBase, LibraryViewPrefs {
  UiSettings([AppearanceSettings? appearance])
    : _appearance = appearance ?? AppearanceSettings();

  /// Owns the light/dark mode and the theme whose chat defaults apply.
  final AppearanceSettings _appearance;

  bool get _isDark => _appearance.isDark;
  ChatDefaultColors get _chat => _appearance.chatDefaults;

  double _bubbleOpacity = 1.0;

  // Chat colors the user picked, per mode; null falls back to the app
  // theme's default (AppPalette.chat).
  Color? _globalUserBubbleColor;
  Color? _globalUserTextColor;
  Color? _globalAiBubbleColor;
  Color? _globalAiTextColor;
  Color? _globalDialogueColor;
  Color? _globalActionColor;
  Color? _lightUserBubbleColor;
  Color? _lightUserTextColor;
  Color? _lightAiBubbleColor;
  Color? _lightAiTextColor;
  Color? _lightDialogueColor;
  Color? _lightActionColor;

  // Global chat font family
  String _globalChatFontFamily = '';

  // Stick-to-bottom while a reply is streaming. Default ON — the old
  // follow-while-generating feel. Off is the Mac-pass no-chase lock.
  bool _followStreamingReplies = true;
  bool _evaluationMinimized = false;

  double _textScale = 1.0;
  String _chatBackground = 'none';
  List<Map<String, String>> _customBackgrounds = [];
  bool _displayBufferEnabled = false;
  double _targetDisplayTps = 6.0; // ~250 WPM average human reading speed
  double _bufferDurationSeconds = 3.0;

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
      (_isDark ? _globalUserBubbleColor : _lightUserBubbleColor) ??
      _chat.userBubble;
  Color get globalUserTextColor =>
      (_isDark ? _globalUserTextColor : _lightUserTextColor) ?? _chat.userText;
  Color get globalAiBubbleColor =>
      (_isDark ? _globalAiBubbleColor : _lightAiBubbleColor) ?? _chat.aiBubble;
  Color get globalAiTextColor =>
      (_isDark ? _globalAiTextColor : _lightAiTextColor) ?? _chat.aiText;
  Color get globalDialogueColor =>
      (_isDark ? _globalDialogueColor : _lightDialogueColor) ?? _chat.dialogue;

  /// True once the user picked their own dialogue colour for this mode in
  /// Chat Appearance (the user bubble keeps a picked colour as is).
  bool get globalDialogueColorChosen =>
      (_isDark ? _globalDialogueColor : _lightDialogueColor) != null;
  bool get globalActionColorChosen =>
      (_isDark ? _globalActionColor : _lightActionColor) != null;
  Color get globalActionColor =>
      (_isDark ? _globalActionColor : _lightActionColor) ?? _chat.action;
  bool get isDark => _isDark;
  bool get followStreamingReplies => _followStreamingReplies;
  bool get evaluationMinimized => _evaluationMinimized;
  String get globalChatFontFamily => _globalChatFontFamily;
  double get textScale => _textScale;
  String get chatBackground => _chatBackground;
  List<Map<String, String>> get customBackgrounds =>
      List.unmodifiable(_customBackgrounds);
  bool get displayBufferEnabled => _displayBufferEnabled;
  double get targetDisplayTps => _targetDisplayTps;
  double get bufferDurationSeconds => _bufferDurationSeconds;

  void load() {
    _evaluationMinimized = prefs?.getBool(k('evaluation_minimized')) ?? false;
    _bubbleOpacity = prefs?.getDouble(k('bubble_opacity')) ?? _bubbleOpacity;
    _globalUserBubbleColor = _pickedColor('global_user_bubble_color');
    _globalUserTextColor = _pickedColor('global_user_text_color');
    _globalAiBubbleColor = _pickedColor('global_ai_bubble_color');
    _globalAiTextColor = _pickedColor('global_ai_text_color');
    _globalDialogueColor = _pickedColor('global_dialogue_color');
    _globalActionColor = _pickedColor('global_action_color');
    _globalChatFontFamily =
        prefs?.getString(k('global_chat_font_family')) ?? _globalChatFontFamily;

    _followStreamingReplies =
        prefs?.getBool(k('follow_streaming_replies')) ?? true;
    _lightUserBubbleColor = _pickedColor('light_user_bubble_color');
    _lightUserTextColor = _pickedColor('light_user_text_color');
    _lightAiBubbleColor = _pickedColor('light_ai_bubble_color');
    _lightAiTextColor = _pickedColor('light_ai_text_color');
    _lightDialogueColor = _pickedColor('light_dialogue_color');
    _lightActionColor = _pickedColor('light_action_color');

    _textScale = (prefs?.getDouble(k('text_scale')) ?? 1.0).clamp(0.7, 2.0);
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
    // One-time (df57bb0d): force the throttle off for users who had it on.
    // Must stay guarded — the old unconditional remove ran on EVERY launch,
    // so the Settings switch ("Smooth Output Buffer") could never survive a
    // restart, which is not what that change intended ("users can re-enable
    // via UI if desired").
    if (prefs?.getBool(k('display_buffer_reset_done')) != true) {
      prefs?.remove(k('display_buffer_enabled'));
      prefs?.setBool(k('display_buffer_reset_done'), true);
    }
    _displayBufferEnabled =
        prefs?.getBool(k('display_buffer_enabled')) ?? false;
    _targetDisplayTps = prefs?.getDouble(k('target_display_tps')) ?? 30.0;
    _bufferDurationSeconds =
        prefs?.getDouble(k('buffer_duration_seconds')) ?? 3.0;

    loadLibraryViewPrefs();

    for (final id in _sidebarGroupIds) {
      final v = prefs?.getBool(k('sidebar_group_expanded_$id'));
      if (v != null) _sidebarGroupExpanded[id] = v;
    }
  }

  Color? _pickedColor(String key) {
    final value = prefs?.getInt(k(key));
    return value == null ? null : Color(value);
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

  /// Forgets this mode's picked chat colors so the app theme's own apply.
  Future<void> resetChatColors() async {
    final prefix = _isDark ? 'global' : 'light';
    for (final role in _chatColorRoles) {
      await prefs?.remove(k('${prefix}_${role}_color'));
    }
    if (_isDark) {
      _globalUserBubbleColor = _globalUserTextColor = _globalAiBubbleColor =
          _globalAiTextColor = _globalDialogueColor = _globalActionColor = null;
    } else {
      _lightUserBubbleColor = _lightUserTextColor = _lightAiBubbleColor =
          _lightAiTextColor = _lightDialogueColor = _lightActionColor = null;
    }
    notify();
  }

  static const _chatColorRoles = [
    'user_bubble',
    'user_text',
    'ai_bubble',
    'ai_text',
    'dialogue',
    'action',
  ];

  Future<void> setGlobalChatFontFamily(String value) async {
    _globalChatFontFamily = value;
    await prefs?.setString(k('global_chat_font_family'), value);
    notify();
  }

  /// Picks dark or light outright (Match system is set on [AppearanceSettings]).
  Future<void> setIsDark(bool value) =>
      _appearance.setMode(value ? AppThemeMode.dark : AppThemeMode.light);

  Future<void> setEvaluationMinimized(bool value) async {
    if (_evaluationMinimized == value) return;
    await prefs?.setBool(k('evaluation_minimized'), value);
    _evaluationMinimized = value;
    notify();
  }

  Future<void> setFollowStreamingReplies(bool value) async {
    if (_followStreamingReplies == value) return;
    _followStreamingReplies = value;
    await prefs?.setBool(k('follow_streaming_replies'), value);
    notify();
  }

  Future<void> setTextScale(double value) async {
    _textScale = value.clamp(0.7, 2.0);
    await prefs?.setDouble(k('text_scale'), _textScale);
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

  /// Get effective user bubble color.
  /// Resolution when a theme is active: theme override → theme preset (a chosen
  /// theme wins over per-character colors). No theme: per-character → global.
  Color getUserBubbleColor(
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    if (themeOverrides?.userBubbleColor != null && themePreset != null) {
      return themeOverrides!.resolvedUserBubbleColor(themePreset);
    }
    if (themePreset != null) return themePreset.defaultUserBubbleColor;
    final charColor = character?.frontPorchExtensions?.userBubbleColor;
    if (charColor != null) return charColor;
    return globalUserBubbleColor;
  }

  /// Get effective user text color.
  /// Resolution when a theme is active: theme override → theme preset (a chosen
  /// theme wins over per-character colors). No theme: per-character → global.
  Color getUserTextColor(
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    if (themeOverrides?.userTextColor != null && themePreset != null) {
      return themeOverrides!.resolvedUserTextColor(themePreset);
    }
    if (themePreset != null) return themePreset.defaultUserTextColor;
    final charColor = character?.frontPorchExtensions?.userTextColor;
    if (charColor != null) return charColor;
    return globalUserTextColor;
  }

  /// Get effective AI bubble color.
  /// Resolution when a theme is active: theme override → theme preset (a chosen
  /// theme wins over per-character colors). No theme: per-character → global.
  Color getAiBubbleColor(
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    if (themeOverrides?.aiBubbleColor != null && themePreset != null) {
      return themeOverrides!.resolvedAiBubbleColor(themePreset);
    }
    if (themePreset != null) return themePreset.defaultAiBubbleColor;
    final charColor = character?.frontPorchExtensions?.aiBubbleColor;
    if (charColor != null) return charColor;
    return globalAiBubbleColor;
  }

  /// Get effective AI text color.
  /// Resolution when a theme is active: theme override → theme preset (a chosen
  /// theme wins over per-character colors). No theme: per-character → global.
  Color getAiTextColor(
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    if (themeOverrides?.aiTextColor != null && themePreset != null) {
      return themeOverrides!.resolvedAiTextColor(themePreset);
    }
    if (themePreset != null) return themePreset.defaultAiTextColor;
    final charColor = character?.frontPorchExtensions?.aiTextColor;
    if (charColor != null) return charColor;
    return globalAiTextColor;
  }

  /// Get effective dialogue color.
  /// Resolution when a theme is active: theme override → theme preset (a chosen
  /// theme wins over per-character colors). No theme: per-character → global.
  Color getDialogueColor(
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    if (themeOverrides?.dialogueColor != null && themePreset != null) {
      return themeOverrides!.resolvedDialogueColor(themePreset);
    }
    if (themePreset != null) return themePreset.defaultDialogueColor;
    final charColor = character?.frontPorchExtensions?.dialogueColor;
    if (charColor != null) return charColor;
    return globalDialogueColor;
  }

  /// Get effective action color.
  /// Resolution when a theme is active: theme override → theme preset (a chosen
  /// theme wins over per-character colors). No theme: per-character → global.
  Color getActionColor(
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    if (themeOverrides?.actionColor != null && themePreset != null) {
      return themeOverrides!.resolvedActionColor(themePreset);
    }
    if (themePreset != null) return themePreset.defaultActionColor;
    final charColor = character?.frontPorchExtensions?.actionColor;
    if (charColor != null) return charColor;
    return globalActionColor;
  }

  /// Get effective chat font family.
  /// Resolution when a theme is active: theme override → theme preset (a chosen
  /// theme wins over per-character colors). No theme: per-character → global.
  String getChatFontFamily(
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    if (themeOverrides?.fontFamily != null && themePreset != null) {
      return themeOverrides!.resolvedFontFamily(themePreset);
    }
    if (themePreset != null) return themePreset.defaultFontFamily;
    final charFont = character?.frontPorchExtensions?.chatFontFamily;
    if (charFont != null) return charFont;
    return _globalChatFontFamily;
  }
}
