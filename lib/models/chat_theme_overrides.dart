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
  String? dialogueColor;
  String? actionColor;
  String? backgroundKey;
  String? borderStyle;
  String? borderColor;

  ChatThemeOverrides({
    this.themeId,
    this.fontFamily,
    this.userBubbleColor,
    this.userTextColor,
    this.aiBubbleColor,
    this.aiTextColor,
    this.dialogueColor,
    this.actionColor,
    this.backgroundKey,
    this.borderStyle,
    this.borderColor,
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
        dialogueColor != null ||
        actionColor != null ||
        backgroundKey != null ||
        borderStyle != null ||
        borderColor != null;
  }

  String resolvedFontFamily(ChatThemePreset preset) =>
      fontFamily ?? preset.defaultFontFamily;

  Color resolvedUserBubbleColor(ChatThemePreset preset) =>
      userBubbleColor != null
          ? _parseColor(userBubbleColor!, preset.defaultUserBubbleColor)
          : preset.defaultUserBubbleColor;

  Color resolvedUserTextColor(ChatThemePreset preset) =>
      userTextColor != null
          ? _parseColor(userTextColor!, preset.defaultUserTextColor)
          : preset.defaultUserTextColor;

  Color resolvedAiBubbleColor(ChatThemePreset preset) =>
      aiBubbleColor != null
          ? _parseColor(aiBubbleColor!, preset.defaultAiBubbleColor)
          : preset.defaultAiBubbleColor;

  Color resolvedAiTextColor(ChatThemePreset preset) =>
      aiTextColor != null
          ? _parseColor(aiTextColor!, preset.defaultAiTextColor)
          : preset.defaultAiTextColor;

  String resolvedBackgroundKey(ChatThemePreset preset) =>
      backgroundKey ?? preset.defaultBackgroundKey;

  String resolvedBorderStyle(ChatThemePreset preset) =>
      borderStyle ?? preset.defaultBorderStyle;

  Color? resolvedBorderColor(ChatThemePreset preset) =>
      borderColor != null
          ? _parseColor(
              borderColor!,
              preset.defaultBorderColor ?? const Color(0x00000000),
            )
          : preset.defaultBorderColor;

  Color resolvedDialogueColor(ChatThemePreset preset) =>
      dialogueColor != null
          ? _parseColor(dialogueColor!, preset.defaultDialogueColor)
          : preset.defaultDialogueColor;

  Color resolvedActionColor(ChatThemePreset preset) =>
      actionColor != null
          ? _parseColor(actionColor!, preset.defaultActionColor)
          : preset.defaultActionColor;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (themeId != null) map['themeId'] = themeId;
    if (fontFamily != null) map['fontFamily'] = fontFamily;
    if (userBubbleColor != null) map['userBubbleColor'] = userBubbleColor;
    if (userTextColor != null) map['userTextColor'] = userTextColor;
    if (aiBubbleColor != null) map['aiBubbleColor'] = aiBubbleColor;
    if (aiTextColor != null) map['aiTextColor'] = aiTextColor;
    if (dialogueColor != null) map['dialogueColor'] = dialogueColor;
    if (actionColor != null) map['actionColor'] = actionColor;
    if (backgroundKey != null) map['backgroundKey'] = backgroundKey;
    if (borderStyle != null) map['borderStyle'] = borderStyle;
    if (borderColor != null) map['borderColor'] = borderColor;
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
      dialogueColor: json['dialogueColor'] as String?,
      actionColor: json['actionColor'] as String?,
      backgroundKey: json['backgroundKey'] as String?,
      borderStyle: json['borderStyle'] as String?,
      borderColor: json['borderColor'] as String?,
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

  // A stored/foreign/corrupt override string can be a non-hex value (old
  // export, hand-edited JSON, a future web payload). int.parse throws on those,
  // and these resolvers run during message-bubble build — an unguarded parse
  // would take down the whole chat paint. Fall back to the preset's channel
  // color instead of crashing.
  static Color _parseColor(String hex, Color fallback) {
    try {
      final h = hex.replaceFirst('#', '');
      if (h.length == 6) {
        return Color(int.parse('FF$h', radix: 16));
      }
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return fallback;
    }
  }
}
