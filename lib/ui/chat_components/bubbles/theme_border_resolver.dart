import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'border_painters.dart';

class ResolvedThemeData {
  final ChatThemeOverrides? overrides;
  final ChatThemePreset? preset;
  final Color? accent;
  final Color textColor;
  final Color borderColor;
  final String? borderStyle;
  final CustomPainter? borderPainter;
  final BorderRadius borderRadius;

  ResolvedThemeData({
    this.overrides,
    this.preset,
    this.accent,
    required this.textColor,
    required this.borderColor,
    this.borderStyle,
    this.borderPainter,
    required this.borderRadius,
  });
}

class ThemeBorderResolver {
  static ResolvedThemeData resolve({
    required ChatService? chatService,
    required StorageService storage,
    required CharacterCard? character,
    required bool isUser,
    required bool isDirectorNote,
    ChatThemeOverrides? themeOverrides,
    AppCorners corners = AppCorners.standard,
  }) {
    final overrides = themeOverrides ?? chatService?.sessionThemeOverrides;
    final preset = ChatThemePreset.byId(overrides?.themeId);
    final accent = preset != null
        ? storage.uiSettings.getUserTextColor(
            character,
            themePreset: preset,
            themeOverrides: overrides,
          )
        : null;
    final textColor = isUser
        ? storage.uiSettings.getUserTextColor(
            character,
            themePreset: preset,
            themeOverrides: overrides,
          )
        : storage.uiSettings.getAiTextColor(
            character,
            themePreset: preset,
            themeOverrides: overrides,
          );
    final borderColor = preset != null
        ? (overrides?.resolvedBorderColor(preset) ?? textColor)
        : textColor;
    final borderStyle = preset != null
        ? (overrides?.resolvedBorderStyle(preset) ?? preset.defaultBorderStyle)
        : null;
    final borderPainter =
        borderStyle != null && borderPainterFactories.containsKey(borderStyle)
        ? borderPainterFactories[borderStyle]!(borderColor)
        : null;
    final borderRadius = _bubbleRadius(isUser, isDirectorNote, corners);

    return ResolvedThemeData(
      overrides: overrides,
      preset: preset,
      accent: accent,
      textColor: textColor,
      borderColor: borderColor,
      borderStyle: borderStyle,
      borderPainter: borderPainter,
      borderRadius: borderRadius,
    );
  }

  /// Waifu Coder / tests with no [StorageService] in the tree.
  static ResolvedThemeData fallback({
    required Color textColor,
    required Color borderColor,
    required bool isUser,
    required bool isDirectorNote,
    AppCorners corners = AppCorners.standard,
  }) {
    return ResolvedThemeData(
      textColor: textColor,
      borderColor: borderColor,
      borderRadius: _bubbleRadius(isUser, isDirectorNote, corners),
    );
  }

  /// The 12 radius with the tail corner squared, scaled by [corners].
  static BorderRadius _bubbleRadius(
    bool isUser,
    bool isDirectorNote,
    AppCorners corners,
  ) {
    final round = Radius.circular(corners.scaled(12));
    final userTail = isUser && !isDirectorNote;
    return BorderRadius.only(
      topLeft: round,
      topRight: round,
      bottomLeft: userTail ? round : Radius.zero,
      bottomRight: userTail ? Radius.zero : round,
    );
  }
}
