import 'dart:convert';
import 'package:flutter/material.dart';
import 'chat_theme_preset.dart';

class ChatThemeOverrides {
  String? themeId;
  String? fontFamily;
  String? userBubbleColor;
  String? userTextColor;
  String? aiBubbleColor;
  String? aiTextColor;
  String? backgroundKey;
  String? borderStyle;

  ChatThemeOverrides({
    this.themeId,
    this.fontFamily,
    this.userBubbleColor,
    this.userTextColor,
    this.aiBubbleColor,
    this.aiTextColor,
    this.backgroundKey,
    this.borderStyle,
  });

  bool get hasTheme => themeId != null;

  bool get isCustomized {
    if (themeId == null) return false;
    final preset = ChatThemePreset.byId(themeId);
    if (preset == null) return false;
    return fontFamily != null ||
        userBubbleColor != null ||
        userTextColor != null ||
        aiBubbleColor != null ||
        aiTextColor != null ||
        backgroundKey != null ||
        borderStyle != null;
  }

  String resolvedFontFamily(ChatThemePreset preset) =>
      fontFamily ?? preset.defaultFontFamily;

  Color resolvedUserBubbleColor(ChatThemePreset preset) =>
      userBubbleColor != null
          ? _parseColor(userBubbleColor!)
          : preset.defaultUserBubbleColor;

  Color resolvedUserTextColor(ChatThemePreset preset) =>
      userTextColor != null
          ? _parseColor(userTextColor!)
          : preset.defaultUserTextColor;

  Color resolvedAiBubbleColor(ChatThemePreset preset) =>
      aiBubbleColor != null
          ? _parseColor(aiBubbleColor!)
          : preset.defaultAiBubbleColor;

  Color resolvedAiTextColor(ChatThemePreset preset) =>
      aiTextColor != null
          ? _parseColor(aiTextColor!)
          : preset.defaultAiTextColor;

  String resolvedBackgroundKey(ChatThemePreset preset) =>
      backgroundKey ?? preset.defaultBackgroundKey;

  String resolvedBorderStyle(ChatThemePreset preset) =>
      borderStyle ?? preset.defaultBorderStyle;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (themeId != null) map['themeId'] = themeId;
    if (fontFamily != null) map['fontFamily'] = fontFamily;
    if (userBubbleColor != null) map['userBubbleColor'] = userBubbleColor;
    if (userTextColor != null) map['userTextColor'] = userTextColor;
    if (aiBubbleColor != null) map['aiBubbleColor'] = aiBubbleColor;
    if (aiTextColor != null) map['aiTextColor'] = aiTextColor;
    if (backgroundKey != null) map['backgroundKey'] = backgroundKey;
    if (borderStyle != null) map['borderStyle'] = borderStyle;
    return map;
  }

  factory ChatThemeOverrides.fromJson(Map<String, dynamic> json) {
    return ChatThemeOverrides(
      themeId: json['themeId'] as String?,
      fontFamily: json['fontFamily'] as String?,
      userBubbleColor: json['userBubbleColor'] as String?,
      userTextColor: json['userTextColor'] as String?,
      aiBubbleColor: json['aiBubbleColor'] as String?,
      aiTextColor: json['aiTextColor'] as String?,
      backgroundKey: json['backgroundKey'] as String?,
      borderStyle: json['borderStyle'] as String?,
    );
  }

  String? toJsonString() {
    if (!hasTheme && !isCustomized) return null;
    return jsonEncode(toJson());
  }

  factory ChatThemeOverrides.fromJsonString(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) {
      return ChatThemeOverrides();
    }
    try {
      return ChatThemeOverrides.fromJson(
        jsonDecode(jsonString) as Map<String, dynamic>,
      );
    } catch (_) {
      return ChatThemeOverrides();
    }
  }

  ChatThemeOverrides copy() =>
      ChatThemeOverrides.fromJson(Map<String, dynamic>.from(toJson()));

  static Color _parseColor(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length == 6) {
      return Color(int.parse('FF$h', radix: 16));
    }
    return Color(int.parse(h, radix: 16));
  }
}
