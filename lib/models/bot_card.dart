// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/models/character_card.dart';

const botCardExtension = 'front_porch_card_mode';
const botPresentation = 'bot_prose';
const botInstructionsLimit = 2000;

Map<String, dynamic>? botOpeningMetadata(BotCardSnapshot? snapshot) =>
    snapshot == null ? null : {'presentation': botPresentation};

extension BotCardFields on CharacterCard {
  String get cardTypeLabel => isBotCard
      ? 'bot'
      : hasUnsupportedCardMode
      ? 'unsupported'
      : 'character';

  bool get isBotCard {
    final mode = rawExtensions?[botCardExtension];
    return mode is Map &&
        mode['version'] == 1 &&
        mode['kind'] == 'bot' &&
        (!mode.containsKey('behavior_instructions') ||
            mode['behavior_instructions'] is String);
  }

  bool get hasUnsupportedCardMode =>
      rawExtensions?.containsKey(botCardExtension) == true && !isBotCard;

  String get behaviorInstructions {
    if (!isBotCard) return '';
    final mode = rawExtensions![botCardExtension] as Map;
    return mode['behavior_instructions'] as String? ?? '';
  }

  /// Replace only our recognized selection. Ordinary edits must preserve even
  /// opaque values written by another client or a later card version.
  void setBotCard(bool enabled, String instructions) {
    if (hasUnsupportedCardMode || (!enabled && !isBotCard)) return;
    final extensions = Map<String, dynamic>.of(rawExtensions ?? {});
    if (enabled) {
      final previous = isBotCard
          ? Map<String, dynamic>.from(extensions[botCardExtension] as Map)
          : const <String, dynamic>{};
      final trimmed = instructions.trim();
      extensions[botCardExtension] = {
        ...previous,
        'version': 1,
        'kind': 'bot',
        if (trimmed.isNotEmpty) 'behavior_instructions': trimmed,
      };
      if (trimmed.isEmpty) {
        (extensions[botCardExtension] as Map).remove('behavior_instructions');
      }
    } else if (isBotCard) {
      extensions.remove(botCardExtension);
    }
    // Group row saves distinguish an empty map (clear) from null (omit).
    rawExtensions = extensions;
  }
}

String limitBotInstructions(String instructions) =>
    String.fromCharCodes(instructions.trim().runes.take(botInstructionsLimit));

/// The Bot’s role and examples stay with a conversation when its
/// library card or group template is edited.
class BotCardSnapshot {
  final String scope;
  final String instructions;
  final String description;
  final String personality;
  final String examples;

  const BotCardSnapshot({
    required this.scope,
    required this.instructions,
    required this.description,
    required this.personality,
    required this.examples,
  });

  static BotCardSnapshot? fromCard(CharacterCard? card) =>
      card == null || !card.isBotCard
      ? null
      : BotCardSnapshot(
          scope: card.scenario,
          instructions: limitBotInstructions(card.behaviorInstructions),
          description: card.description,
          personality: card.personality,
          examples: card.mesExample,
        );

  static BotCardSnapshot? fromJson(Object? json) {
    if (json is! Map || json['version'] != 1) return null;
    String string(String key) => json[key] is String ? json[key] as String : '';
    return BotCardSnapshot(
      scope: string('scope'),
      instructions: limitBotInstructions(string('instructions')),
      description: string('description'),
      personality: string('personality'),
      examples: string('examples'),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'scope': scope,
    'instructions': instructions,
    'description': description,
    'personality': personality,
    'examples': examples,
  };

  String promptRole(String name) => [
    'Bot speaker: $name',
    if (description.trim().isNotEmpty) 'Role: ${description.trim()}',
    if (personality.trim().isNotEmpty) 'Personality: ${personality.trim()}',
    if (scope.trim().isNotEmpty) 'Scope: ${scope.trim()}',
    if (instructions.isNotEmpty) 'Behavior instructions: $instructions',
  ].join('\n');
}

Map<String, BotCardSnapshot> readGroupBots(Object? json) {
  if (json is! Map) return {};
  final result = <String, BotCardSnapshot>{};
  for (final entry in json.entries) {
    final snapshot = BotCardSnapshot.fromJson(entry.value);
    if (entry.key is String && snapshot != null) {
      result[entry.key as String] = snapshot;
    }
  }
  return result;
}
