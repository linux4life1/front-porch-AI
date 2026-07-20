import 'package:flutter/material.dart';

class ChatThemePreset {
  final String id;
  final String displayName;
  final String description;
  final Color defaultUserBubbleColor;
  final Color defaultUserTextColor;
  final Color defaultAiBubbleColor;
  final Color defaultAiTextColor;
  final Color? defaultBorderColor;
  final String defaultFontFamily;
  final String defaultBackgroundKey;
  final String defaultBorderStyle;

  const ChatThemePreset({
    required this.id,
    required this.displayName,
    required this.description,
    required this.defaultUserBubbleColor,
    required this.defaultUserTextColor,
    required this.defaultAiBubbleColor,
    required this.defaultAiTextColor,
    this.defaultBorderColor,
    required this.defaultFontFamily,
    required this.defaultBackgroundKey,
    required this.defaultBorderStyle,
  });

  static const List<ChatThemePreset> presets = [
    fantasy,
    galactic,
    neonGrid,
    sakura,
    noir,
    enchantedForest,
    oceanDepths,
    cyberpunk,
    romanEmpire,
    steampunk,
  ];

  static const ChatThemePreset fantasy = ChatThemePreset(
    id: 'fantasy',
    displayName: 'Fantasy',
    description: 'Rich purples and soft gold',
    defaultUserBubbleColor: Color(0xFFFFE57F),
    defaultUserTextColor: Color(0xFF6D4C41),
    defaultAiBubbleColor: Color(0xFFFFE57F),
    defaultAiTextColor: Color(0xFF3E2723),
    defaultBorderColor: Color(0xFF007E1B),
    defaultFontFamily: 'serif',
    defaultBackgroundKey: 'fantasy',
    defaultBorderStyle: 'vine',
  );

  static const ChatThemePreset galactic = ChatThemePreset(
    id: 'galactic',
    displayName: 'Galactic',
    description: 'Deep space blues and cyan',
    defaultUserBubbleColor: Color(0xFF0D1B2A),
    defaultUserTextColor: Color(0xFF00D4FF),
    defaultAiBubbleColor: Color(0xFF0D1B2A),
    defaultAiTextColor: Color(0xFFE0E0FF),
    defaultBorderColor: Color(0xFF00D4FF),
    defaultFontFamily: 'sans-serif',
    defaultBackgroundKey: 'space_station',
    defaultBorderStyle: 'dualLine',
  );

  static const ChatThemePreset neonGrid = ChatThemePreset(
    id: 'neon_grid',
    displayName: 'Neon Grid',
    description: 'Black backdrop with neon glow',
    defaultUserBubbleColor: Color(0xFF0A0A0A),
    defaultUserTextColor: Color(0xFFFF00FF),
    defaultAiBubbleColor: Color(0xFF0A0A0A),
    defaultAiTextColor: Color(0xFF00FFFF),
    defaultBorderColor: Color(0xFFFF00FF),
    defaultFontFamily: 'monospace',
    defaultBackgroundKey: 'grid',
    defaultBorderStyle: 'glitch',
  );

  static const ChatThemePreset sakura = ChatThemePreset(
    id: 'sakura',
    displayName: 'Sakura',
    description: 'Soft pinks and pale tones',
    defaultUserBubbleColor: Color(0xFFFFE4E9),
    defaultUserTextColor: Color(0xFF2D5A27),
    defaultAiBubbleColor: Color(0xFFFFE4E9),
    defaultAiTextColor: Color(0xFF2D5A27),
    defaultBorderColor: Color(0xFF2D5A27),
    defaultFontFamily: 'serif',
    defaultBackgroundKey: 'cherry_blossom',
    defaultBorderStyle: 'wavy',
  );

  static const ChatThemePreset noir = ChatThemePreset(
    id: 'noir',
    displayName: 'Noir',
    description: 'Monochrome shadows',
    defaultUserBubbleColor: Color(0xFF2D2D2D),
    defaultUserTextColor: Color(0xFFF5F5F5),
    defaultAiBubbleColor: Color(0xFF1A1A1A),
    defaultAiTextColor: Color(0xFFCCCCCC),
    defaultBorderColor: Color(0xFF888888),
    defaultFontFamily: 'sans-serif',
    defaultBackgroundKey: 'noir',
    defaultBorderStyle: 'shadow',
  );

  static const ChatThemePreset enchantedForest = ChatThemePreset(
    id: 'enchanted_forest',
    displayName: 'Enchanted Forest',
    description: 'Deep greens and warm earth',
    defaultUserBubbleColor: Color(0xFF2D5A27),
    defaultUserTextColor: Color(0xFFF0E6D3),
    defaultAiBubbleColor: Color(0xFF4A7C3F),
    defaultAiTextColor: Color(0xFFFFF8E7),
    defaultBorderColor: Color(0xFF5E3D04),
    defaultFontFamily: 'serif',
    defaultBackgroundKey: 'enchanted_wood',
    defaultBorderStyle: 'vine',
  );

  static const ChatThemePreset oceanDepths = ChatThemePreset(
    id: 'ocean_depths',
    displayName: 'Ocean Depths',
    description: 'Deep blues and teal',
    defaultUserBubbleColor: Color(0xFF003049),
    defaultUserTextColor: Color(0xFFE0F7FA),
    defaultAiBubbleColor: Color(0xFF006D77),
    defaultAiTextColor: Color(0xFFE0F7FA),
    defaultBorderColor: Color(0xFF00BCD4),
    defaultFontFamily: 'sans-serif',
    defaultBackgroundKey: 'ocean_depth',
    defaultBorderStyle: 'dualLine',
  );

  static const ChatThemePreset cyberpunk = ChatThemePreset(
    id: 'cyberpunk',
    displayName: 'Cyberpunk',
    description: 'Neon on dark',
    defaultUserBubbleColor: Color(0xFF0A0A23),
    defaultUserTextColor: Color(0xFF00FF41),
    defaultAiBubbleColor: Color(0xFF1A0A2E),
    defaultAiTextColor: Color(0xFFFF00FF),
    defaultBorderColor: Color(0xFF00FF41),
    defaultFontFamily: 'monospace',
    defaultBackgroundKey: 'futuristic_city',
    defaultBorderStyle: 'glitch',
  );

  static const ChatThemePreset romanEmpire = ChatThemePreset(
    id: 'roman_empire',
    displayName: 'Roman Empire',
    description: 'Rich browns and warm cream',
    defaultUserBubbleColor: Color(0xFFFDE68A),
    defaultUserTextColor: Color(0xFF5D4037),
    defaultAiBubbleColor: Color(0xFFFDE68A),
    defaultAiTextColor: Color(0xFF451A03),
    defaultBorderColor: Color(0xFF451A03),
    defaultFontFamily: 'serif',
    defaultBackgroundKey: 'roman_market',
    defaultBorderStyle: 'greekKey',
  );

  static const ChatThemePreset steampunk = ChatThemePreset(
    id: 'steampunk',
    displayName: 'Steampunk',
    description: 'Brass and copper tones',
    defaultUserBubbleColor: Color(0xFF3E2723),
    defaultUserTextColor: Color(0xFFFFD54F),
    defaultAiBubbleColor: Color(0xFF5D4037),
    defaultAiTextColor: Color(0xFFE0C9A6),
    defaultBorderColor: Color(0xFFFFD54F),
    defaultFontFamily: 'serif',
    defaultBackgroundKey: 'steampunk_bg',
    defaultBorderStyle: 'gear',
  );

  static ChatThemePreset? byId(String? id) {
    if (id == null) return null;
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
