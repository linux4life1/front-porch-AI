import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
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
  }) {
    final overrides = chatService?.sessionThemeOverrides;
    final preset = ChatThemePreset.byId(overrides?.themeId);
    final accent = preset != null
        ? storage.getUserTextColor(character, preset, overrides)
        : null;
    final textColor = isUser
        ? storage.getUserTextColor(character, preset, overrides)
        : storage.getAiTextColor(character, preset, overrides);
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
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: isUser && !isDirectorNote
          ? const Radius.circular(12)
          : Radius.zero,
      bottomRight: isUser && !isDirectorNote
          ? Radius.zero
          : const Radius.circular(12),
    );

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
  }) {
    return ResolvedThemeData(
      textColor: textColor,
      borderColor: borderColor,
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(12),
        topRight: const Radius.circular(12),
        bottomLeft: isUser && !isDirectorNote
            ? const Radius.circular(12)
            : Radius.zero,
        bottomRight: isUser && !isDirectorNote
            ? Radius.zero
            : const Radius.circular(12),
      ),
    );
  }
}
