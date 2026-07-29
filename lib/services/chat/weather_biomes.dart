// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Built-in weather biomes for Living Worlds phase 1.
// temperate == today's WeatherEngine tables (byte-identical when biome is null).

import 'dart:convert';

/// Condition order shared with [WeatherEngine]: clear, cloudy, overcast, fog,
/// rain, storm, snow.
const List<String> kWeatherConditions = [
  'clear',
  'cloudy',
  'overcast',
  'fog',
  'rain',
  'storm',
  'snow',
];

const List<String> kSeasons = ['winter', 'spring', 'summer', 'autumn'];

/// Stance for condition skins (phase 2 fully authors these; built-ins carry
/// ordinary/harsh so dressCue can stay one code path).
enum WeatherStance {
  pleasant,
  ordinary,
  harsh,
  dangerous,
  deadly,
}

WeatherStance weatherStanceFromName(String? name) {
  switch (name?.toLowerCase()) {
    case 'pleasant':
      return WeatherStance.pleasant;
    case 'harsh':
      return WeatherStance.harsh;
    case 'dangerous':
      return WeatherStance.dangerous;
    case 'deadly':
      return WeatherStance.deadly;
    default:
      return WeatherStance.ordinary;
  }
}

/// A climate table: season weights, base temps, diurnal amplitude, skins.
///
/// [description] is short UI copy (what the climate *is*).
/// [feel] is story vibe — how weather shows up for characters in chat.
class Biome {
  final String id;
  final String displayName;
  final String description;

  /// Story-facing vibe for the climate picker (what play will *feel* like).
  final String feel;

  /// season → 7 weights (same order as [kWeatherConditions]).
  final Map<String, List<int>> weights;

  /// season → TempBand index 0..4 (cold..hot).
  final Map<String, int> baseTemp;

  /// Scales day–night swing (1.0 = temperate default).
  final double diurnalAmplitude;

  /// Optional per-condition label/emoji/stance overrides.
  final Map<String, ConditionSkin> conditionSkin;

  const Biome({
    required this.id,
    required this.displayName,
    required this.description,
    this.feel = '',
    required this.weights,
    required this.baseTemp,
    this.diurnalAmplitude = 1.0,
    this.conditionSkin = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'description': description,
        if (feel.isNotEmpty) 'feel': feel,
        'weights': weights,
        'baseTemp': baseTemp,
        'diurnalAmplitude': diurnalAmplitude,
        if (conditionSkin.isNotEmpty)
          'conditionSkin': {
            for (final e in conditionSkin.entries) e.key: e.value.toJson(),
          },
      };

  factory Biome.fromJson(Map<String, dynamic> json) {
    final weightsRaw = json['weights'];
    final weights = <String, List<int>>{};
    if (weightsRaw is Map) {
      for (final e in weightsRaw.entries) {
        final list = e.value;
        if (list is List) {
          weights[e.key.toString()] = [
            for (final v in list) (v as num).toInt(),
          ];
        }
      }
    }
    final baseRaw = json['baseTemp'] ?? json['base_temp'];
    final baseTemp = <String, int>{};
    if (baseRaw is Map) {
      for (final e in baseRaw.entries) {
        baseTemp[e.key.toString()] = (e.value as num).toInt();
      }
    }
    final skins = <String, ConditionSkin>{};
    final skinRaw = json['conditionSkin'] ?? json['condition_skin'];
    if (skinRaw is Map) {
      for (final e in skinRaw.entries) {
        if (e.value is Map) {
          skins[e.key.toString()] = ConditionSkin.fromJson(
            Map<String, dynamic>.from(e.value as Map),
          );
        }
      }
    }
    return Biome(
      id: json['id']?.toString() ?? 'custom',
      displayName: json['displayName']?.toString() ??
          json['display_name']?.toString() ??
          'Custom',
      description: json['description']?.toString() ?? '',
      feel: json['feel']?.toString() ?? '',
      weights: weights.isEmpty ? Map.from(temperate.weights) : weights,
      baseTemp: baseTemp.isEmpty ? Map.from(temperate.baseTemp) : baseTemp,
      diurnalAmplitude:
          (json['diurnalAmplitude'] as num?)?.toDouble() ??
          (json['diurnal_amplitude'] as num?)?.toDouble() ??
          1.0,
      conditionSkin: skins,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static Biome? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return Biome.fromJson(decoded);
      if (decoded is Map) {
        return Biome.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }

  /// Validate authoring invariants (phase 1/2 shared).
  List<String> validate() {
    final errors = <String>[];
    for (final season in kSeasons) {
      final w = weights[season];
      if (w == null || w.length != kWeatherConditions.length) {
        errors.add('$season: need ${kWeatherConditions.length} weights');
        continue;
      }
      final sum = w.fold<int>(0, (a, b) => a + b);
      if (sum <= 0) errors.add('$season: weights sum to 0');
      final nonzero = w.where((x) => x > 0).length;
      if (nonzero < 2) {
        errors.add('$season: need ≥2 non-zero conditions');
      }
      final t = baseTemp[season];
      if (t == null || t < 0 || t > 4) {
        errors.add('$season: baseTemp must be 0..4');
      }
    }
    for (final e in conditionSkin.entries) {
      if (e.value.label.trim().isNotEmpty &&
          e.value.stance == WeatherStance.ordinary &&
          e.value.label.toLowerCase() != e.key) {
        // Rename without explicit harsh+ stance is a soft warning only when
        // stance omitted at parse — we always have a stance. Hard rule for
        // renames is enforced at the editor (phase 2).
      }
    }
    return errors;
  }

  // ── Built-ins ────────────────────────────────────────────────────────

  /// Today's engine tables, renamed. NULL biome ⇒ this.
  static const temperate = Biome(
    id: 'temperate',
    displayName: 'Temperate',
    description: 'Four familiar seasons with mixed rain, sun, and the odd storm.',
    feel:
        'Like most of Europe or the US Midwest — jacket weather in spring/fall, '
        'real winter cold, summer heat that can break into thunder.',
    weights: {
      'winter': [20, 20, 20, 10, 10, 2, 18],
      'spring': [30, 25, 15, 8, 18, 4, 0],
      'summer': [45, 22, 8, 2, 12, 11, 0],
      'autumn': [24, 24, 20, 10, 16, 6, 0],
    },
    baseTemp: {
      'winter': 0,
      'spring': 2,
      'summer': 3,
      'autumn': 1,
    },
    diurnalAmplitude: 1.0,
  );

  static const rainforest = Biome(
    id: 'rainforest',
    displayName: 'Rainforest',
    description: 'Humid and wet most days — grey skies, drizzle, fog.',
    feel:
        'Always a little damp. Characters notice humidity, soft rain, and '
        'mud more than snow or hard freezes. Storms exist but heavy downpours '
        'are less common than steady wet.',
    weights: {
      'winter': [8, 15, 30, 18, 25, 4, 0],
      'spring': [10, 15, 28, 15, 28, 4, 0],
      'summer': [12, 12, 25, 12, 32, 7, 0],
      'autumn': [10, 15, 28, 16, 26, 5, 0],
    },
    baseTemp: {
      'winter': 2,
      'spring': 3,
      'summer': 3,
      'autumn': 2,
    },
    diurnalAmplitude: 0.7,
  );

  static const desert = Biome(
    id: 'desert',
    displayName: 'Desert',
    description: 'Clear, dry, almost no rain — brutal day-to-night swings.',
    feel:
        'Scorching sun by day, coat-weather nights. Rain is rare and memorable. '
        'Good for Mars-like dust worlds, dunes, or arid coasts.',
    weights: {
      'winter': [70, 18, 6, 2, 3, 1, 0],
      'spring': [75, 15, 5, 1, 3, 1, 0],
      'summer': [80, 12, 4, 0, 2, 2, 0],
      'autumn': [72, 16, 6, 2, 3, 1, 0],
    },
    baseTemp: {
      'winter': 1,
      'spring': 3,
      'summer': 4,
      'autumn': 2,
    },
    diurnalAmplitude: 2.2,
  );

  static const continental = Biome(
    id: 'continental',
    displayName: 'Continental',
    description: 'Harsh winters with real snow; hot, stormy summers.',
    feel:
        'Winter can bury you. Summer is loud — heat and thunderstorms. '
        'Think prairie, Russian steppe, or deep inland cities.',
    weights: {
      'winter': [15, 15, 15, 8, 8, 2, 37],
      'spring': [25, 22, 15, 8, 22, 6, 2],
      'summer': [35, 18, 8, 2, 18, 19, 0],
      'autumn': [22, 22, 18, 10, 18, 8, 2],
    },
    baseTemp: {
      'winter': 0,
      'spring': 2,
      'summer': 4,
      'autumn': 1,
    },
    diurnalAmplitude: 1.3,
  );

  static const tropical = Biome(
    id: 'tropical',
    displayName: 'Tropical',
    description: 'Hot and sticky year-round; storms as daily rhythm.',
    feel:
        'No real winter. Characters sweat, seek shade, and plan around '
        'afternoon downpours. Snow almost never happens.',
    weights: {
      'winter': [35, 20, 12, 5, 20, 8, 0],
      'spring': [30, 18, 12, 5, 22, 13, 0],
      'summer': [28, 15, 10, 4, 25, 18, 0],
      'autumn': [32, 18, 12, 5, 22, 11, 0],
    },
    baseTemp: {
      'winter': 3,
      'spring': 4,
      'summer': 4,
      'autumn': 3,
    },
    diurnalAmplitude: 0.6,
  );

  static const mediterranean = Biome(
    id: 'mediterranean',
    displayName: 'Mediterranean',
    description: 'Dry, hot summers; rain comes in the mild winters.',
    feel:
        'Summer is bright and parched — wildfire season energy. Winter is '
        'cooler and wetter, not frozen. Think California coast or Greece.',
    weights: {
      'winter': [25, 20, 15, 8, 28, 4, 0],
      'spring': [40, 25, 12, 5, 15, 3, 0],
      'summer': [70, 18, 5, 1, 4, 2, 0],
      'autumn': [35, 22, 15, 6, 18, 4, 0],
    },
    baseTemp: {
      'winter': 1,
      'spring': 2,
      'summer': 4,
      'autumn': 2,
    },
    diurnalAmplitude: 1.1,
  );

  static const highland = Biome(
    id: 'highland',
    displayName: 'Highland',
    description: 'Colder than the lowlands — snow lingers, fog and quick shifts.',
    feel:
        'Thin air and sharp weather changes. Spring can still snow. Characters '
        'dress warmer; valleys and peaks feel different.',
    weights: {
      'winter': [12, 15, 18, 15, 10, 3, 27],
      'spring': [18, 18, 18, 15, 15, 4, 12],
      'summer': [30, 22, 15, 10, 15, 6, 2],
      'autumn': [18, 18, 18, 14, 16, 5, 11],
    },
    baseTemp: {
      'winter': 0,
      'spring': 1,
      'summer': 2,
      'autumn': 0,
    },
    diurnalAmplitude: 1.5,
  );

  static const List<Biome> builtIns = [
    temperate,
    rainforest,
    desert,
    continental,
    tropical,
    mediterranean,
    highland,
  ];

  static final Map<String, Biome> _byId = {
    for (final b in builtIns) b.id: b,
  };

  static Biome? builtInById(String? id) {
    if (id == null || id.isEmpty) return null;
    return _byId[id];
  }

  /// Resolve a world/chat biome: custom JSON, then built-in id, else temperate.
  static Biome resolve({String? biomeId, String? biomeJson}) {
    final custom = tryParse(biomeJson);
    if (custom != null) return custom;
    return builtInById(biomeId) ?? temperate;
  }
}

class ConditionSkin {
  final String label;
  final String? emoji;
  final WeatherStance stance;
  final String? flavour;

  const ConditionSkin({
    required this.label,
    this.emoji,
    this.stance = WeatherStance.ordinary,
    this.flavour,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        if (emoji != null) 'emoji': emoji,
        'stance': stance.name,
        if (flavour != null && flavour!.isNotEmpty) 'flavour': flavour,
      };

  factory ConditionSkin.fromJson(Map<String, dynamic> json) => ConditionSkin(
        label: json['label']?.toString() ?? '',
        emoji: json['emoji']?.toString(),
        stance: weatherStanceFromName(json['stance']?.toString()),
        flavour: json['flavour']?.toString() ?? json['flavor']?.toString(),
      );
}
