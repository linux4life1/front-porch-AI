// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/models/character_card.dart';

const scenarioCardExtension = 'front_porch_card_mode';
const scenarioPresentation = 'scenario_prose';
const scenarioRulesLimit = 2000;

Map<String, dynamic>? scenarioOpeningMetadata(ScenarioCardSnapshot? snapshot) =>
    snapshot == null ? null : {'presentation': scenarioPresentation};

extension ScenarioCardFields on CharacterCard {
  String get cardTypeLabel => isScenarioCard
      ? 'scenario'
      : hasUnsupportedCardMode
      ? 'unsupported'
      : 'character';

  bool get isScenarioCard {
    final mode = rawExtensions?[scenarioCardExtension];
    return mode is Map &&
        mode['version'] == 1 &&
        mode['kind'] == 'scenario' &&
        (!mode.containsKey('facilitation_rules') ||
            mode['facilitation_rules'] is String);
  }

  bool get hasUnsupportedCardMode =>
      rawExtensions?.containsKey(scenarioCardExtension) == true &&
      !isScenarioCard;

  String get facilitationRules {
    if (!isScenarioCard) return '';
    final mode = rawExtensions![scenarioCardExtension] as Map;
    return mode['facilitation_rules'] as String? ?? '';
  }

  /// Replace only our recognized selection. Ordinary edits must preserve even
  /// opaque values written by another client or a later card version.
  void setScenarioCard(bool enabled, String rules) {
    if (hasUnsupportedCardMode || (!enabled && !isScenarioCard)) return;
    final extensions = Map<String, dynamic>.of(rawExtensions ?? {});
    if (enabled) {
      final previous = isScenarioCard
          ? Map<String, dynamic>.from(extensions[scenarioCardExtension] as Map)
          : const <String, dynamic>{};
      final trimmedRules = rules.trim();
      extensions[scenarioCardExtension] = {
        ...previous,
        'version': 1,
        'kind': 'scenario',
        if (trimmedRules.isNotEmpty) 'facilitation_rules': trimmedRules,
      };
      if (trimmedRules.isEmpty) {
        (extensions[scenarioCardExtension] as Map).remove('facilitation_rules');
      }
    } else if (isScenarioCard) {
      extensions.remove(scenarioCardExtension);
    }
    // Group row saves distinguish an empty map (clear) from null (omit).
    rawExtensions = extensions;
  }
}

String limitScenarioRules(String rules) =>
    String.fromCharCodes(rules.trim().runes.take(scenarioRulesLimit));

/// The facilitator's premise and examples stay with a conversation when its
/// library card or group template is edited.
class ScenarioCardSnapshot {
  final String setting;
  final String rules;
  final String description;
  final String personality;
  final String examples;

  const ScenarioCardSnapshot({
    required this.setting,
    required this.rules,
    required this.description,
    required this.personality,
    required this.examples,
  });

  static ScenarioCardSnapshot? fromCard(CharacterCard? card) =>
      card == null || !card.isScenarioCard
      ? null
      : ScenarioCardSnapshot(
          setting: card.scenario,
          rules: limitScenarioRules(card.facilitationRules),
          description: card.description,
          personality: card.personality,
          examples: card.mesExample,
        );

  static ScenarioCardSnapshot? fromJson(Object? json) {
    if (json is! Map || json['version'] != 1) return null;
    String string(String key) => json[key] is String ? json[key] as String : '';
    return ScenarioCardSnapshot(
      setting: string('setting'),
      rules: limitScenarioRules(string('rules')),
      description: string('description'),
      personality: string('personality'),
      examples: string('examples'),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'setting': setting,
    'rules': rules,
    'description': description,
    'personality': personality,
    'examples': examples,
  };

  String get guidance => [
    if (description.trim().isNotEmpty) description.trim(),
    if (personality.trim().isNotEmpty) personality.trim(),
    if (rules.isNotEmpty) 'Facilitation rules: $rules',
  ].join('\n');
}

Map<String, ScenarioCardSnapshot> readGroupScenarios(Object? json) {
  if (json is! Map) return {};
  final result = <String, ScenarioCardSnapshot>{};
  for (final entry in json.entries) {
    final snapshot = ScenarioCardSnapshot.fromJson(entry.value);
    if (entry.key is String && snapshot != null) {
      result[entry.key as String] = snapshot;
    }
  }
  return result;
}
