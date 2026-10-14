// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure parse for the chargen Porch Life seed (ambitions, likes, wardrobe,
// optional intimate). Kept out of the `character_gen_*.dart` parts so tests
// can feed a map without standing up CharacterGenService.

import 'dart:convert';

import 'package:front_porch_ai/models/models.dart' show FrontPorchExtensions;
import 'package:front_porch_ai/services/chat/chat.dart'
    show Pockets, StoryClock, kMaxWorn;

/// Chip lists the AI creator can seed onto a new card.
class PorchLifeIdentity {
  const PorchLifeIdentity({
    this.ambitions = const [],
    this.likes = const [],
    this.dislikes = const [],
    this.worn = const [],
    this.carrying = const [],
    this.intimateInto = const [],
    this.intimateNotInto = const [],
    this.characterEmotion = '',
    this.emotionIntensity = '',
    this.timeOfDay = '',
    this.storyStartTime = '',
  });

  final List<String> ambitions;
  final List<String> likes;
  final List<String> dislikes;
  final List<String> worn;
  final List<String> carrying;
  final List<String> intimateInto;
  final List<String> intimateNotInto;

  /// The greeting-time read (`identityDone`): the mood as the greeting opens
  /// (mild / moderate / strong), the story period it opens in (one of
  /// [StoryClock.periods]) and its `HH:MM` clock. '' when not read.
  final String characterEmotion;
  final String emotionIntensity;
  final String timeOfDay;
  final String storyStartTime;

  bool get isEmpty =>
      ambitions.isEmpty &&
      likes.isEmpty &&
      dislikes.isEmpty &&
      worn.isEmpty &&
      carrying.isEmpty &&
      intimateInto.isEmpty &&
      intimateNotInto.isEmpty &&
      characterEmotion.isEmpty &&
      emotionIntensity.isEmpty &&
      timeOfDay.isEmpty &&
      storyStartTime.isEmpty;
}

const kPorchLifeToolName = 'set_porch_life';

const _kChipKeys = [
  'ambitions',
  'likes',
  'dislikes',
  'worn',
  'carrying',
  'intimate_into',
  'intimate_not_into',
];

/// OpenAI-style tool the extract pass asks for. Intimate fields are omitted
/// unless [nsfw] — the schema must not invite 18+ lists on an SFW run.
/// [identityDone]: the identity facts pass already wrote the lists, so ask
/// only what the greeting decides (outfit, pockets, mood, time).
List<Map<String, dynamic>> porchLifeToolSchema({
  required bool nsfw,
  bool identityDone = false,
}) {
  Map<String, dynamic> chips(String description) => {
    'type': 'array',
    'items': {'type': 'string'},
    'description': description,
  };
  if (identityDone) return _openingSceneToolSchema(chips);
  final properties = <String, dynamic>{
    'ambitions': chips(
      '2-4 long-term goals across the whole story, not today\'s errand.',
    ),
    'likes': chips('3-6 small specific things they warm to.'),
    'dislikes': chips('2-4 things that make them bristle.'),
    'worn': chips(
      'What they are wearing in the opening scene. "item (condition)" is fine.',
    ),
    'carrying': chips(
      'What is in their pockets or hands as the greeting opens.',
    ),
  };
  if (nsfw) {
    properties['intimate_into'] = chips(
      'Suggestive tastes for 18+ scenes. Short phrases.',
    );
    properties['intimate_not_into'] = chips(
      'Hard limits / not interested. Short phrases.',
    );
  }
  return [
    {
      'type': 'function',
      'function': {
        'name': kPorchLifeToolName,
        'description':
            'Seed this character\'s Porch Life identity: ambitions, tastes, '
            'and what they are wearing and carrying when the first chat opens.',
        'parameters': {
          'type': 'object',
          'properties': properties,
          'required': ['ambitions', 'likes', 'dislikes', 'worn', 'carrying'],
        },
      },
    },
  ];
}

List<Map<String, dynamic>> _openingSceneToolSchema(
  Map<String, dynamic> Function(String) chips,
) => [
  {
    'type': 'function',
    'function': {
      'name': kPorchLifeToolName,
      'description':
          'Read the opening scene: what this character is wearing and '
          'carrying, how they feel, and when the greeting takes place.',
      'parameters': {
        'type': 'object',
        'properties': {
          'worn': chips(
            'What they are wearing in the opening scene. "item (condition)" '
            'is fine.',
          ),
          'carrying': chips(
            'What is in their pockets or hands as the greeting opens.',
          ),
          'character_emotion': {
            'type': 'string',
            'description': 'One word for how they feel as the greeting opens.',
          },
          'emotion_intensity': {'type': 'string', 'enum': kEmotionIntensities},
          'time_of_day': {
            'type': 'string',
            'enum': StoryClock.periods,
            'description': 'The part of the day the greeting takes place in.',
          },
          'story_start_time': {
            'type': 'string',
            'description': 'The clock as the greeting opens, 24-hour "HH:MM".',
          },
        },
        'required': ['worn', 'carrying'],
      },
    },
  },
];

/// How strongly the opening mood is felt, as the card stores it.
const kEmotionIntensities = ['mild', 'moderate', 'strong'];

/// Pull chip lists out of a decoded object or a raw JSON/prose blob.
/// Intimate lists are dropped when [nsfw] is false even if the model sent them.
PorchLifeIdentity parsePorchLifeIdentity(Object? raw, {required bool nsfw}) {
  final map = porchLifeJsonMap(raw);
  if (map == null) return const PorchLifeIdentity();
  return PorchLifeIdentity(
    ambitions: porchLifeChips(map['ambitions']),
    likes: porchLifeChips(map['likes']),
    dislikes: porchLifeChips(map['dislikes']),
    worn: porchLifeChips(map['worn'], cap: kMaxWorn),
    carrying: porchLifeChips(map['carrying'], cap: kMaxWorn),
    intimateInto: nsfw
        ? porchLifeChips(map['intimate_into'] ?? map['intimateInto'])
        : const [],
    intimateNotInto: nsfw
        ? porchLifeChips(map['intimate_not_into'] ?? map['intimateNotInto'])
        : const [],
    characterEmotion: _emotion(map['character_emotion']),
    emotionIntensity: _oneOf(map['emotion_intensity'], kEmotionIntensities),
    timeOfDay: _oneOf(map['time_of_day'], StoryClock.periods),
    storyStartTime: _clock(map['story_start_time']),
  );
}

String _emotion(Object? raw) {
  if (raw is! String) return '';
  final s = raw.trim().toLowerCase();
  if (s.isEmpty || s.length > 30 || s.contains('{{')) return '';
  return s;
}

String _oneOf(Object? raw, List<String> allowed) {
  if (raw is! String) return '';
  final s = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
  return allowed.contains(s) ? s : '';
}

/// `H:MM` / `HH:MM` on a 24-hour clock, written `HH:MM`; '' otherwise.
String _clock(Object? raw) {
  if (raw is! String) return '';
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
  if (m == null) return '';
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return '';
  return '${h.toString().padLeft(2, '0')}:${m.group(2)}';
}

/// The string-keyed map inside [raw]: a decoded map as is, or the JSON
/// object salvaged from a model's text (preamble, unescaped quotes). When
/// the text will not decode, [chipKeys] arrays and [scalarKeys] strings or
/// numbers are pulled out one by one.
Map<String, dynamic>? porchLifeJsonMap(
  Object? raw, {
  List<String> chipKeys = _kChipKeys,
  List<String> scalarKeys = _kSceneKeys,
}) {
  final map = _asStringKeyedMap(raw);
  if (map != null) return map;
  if (raw is! String) return null;
  final cleaned = raw.trim();
  final start = cleaned.indexOf('{');
  final end = cleaned.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      final decoded = _asStringKeyedMap(
        json.decode(cleaned.substring(start, end + 1)),
      );
      if (decoded != null) return decoded;
    } on FormatException {
      // Unescaped quotes and the like: salvage key by key below.
    }
  }
  return {
    ..._regexLists(cleaned, chipKeys),
    ..._regexScalars(cleaned, scalarKeys),
  };
}

const _kSceneKeys = [
  'character_emotion',
  'emotion_intensity',
  'time_of_day',
  'story_start_time',
];

Map<String, dynamic>? _asStringKeyedMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return {for (final e in raw.entries) e.key.toString(): e.value};
  }
  return null;
}

/// The same salvage for string and number values: a string runs to the
/// quote that closes the field, so a stray quote inside it survives.
Map<String, dynamic> _regexScalars(String raw, List<String> keys) {
  final out = <String, dynamic>{};
  for (final key in keys) {
    final text = RegExp(
      '"$key"\\s*:\\s*"(.*?)"\\s*(?=[,}\\n]|\$)',
      dotAll: true,
    ).firstMatch(raw);
    if (text != null) {
      out[key] = text.group(1)!.replaceAll(r'\"', '"');
      continue;
    }
    final number = RegExp('"$key"\\s*:\\s*(-?\\d+)').firstMatch(raw);
    if (number != null) out[key] = int.parse(number.group(1)!);
  }
  return out;
}

/// When json.decode fails (unescaped quotes), pull each array by key.
Map<String, dynamic> _regexLists(String raw, List<String> keys) {
  final out = <String, dynamic>{};
  for (final key in keys) {
    final match = RegExp('"$key"\\s*:\\s*\\[').firstMatch(raw);
    if (match == null) continue;
    final open = raw.indexOf('[', match.start);
    if (open < 0) continue;
    final close = raw.indexOf(']', open);
    if (close < 0) continue;
    try {
      out[key] = json.decode(raw.substring(open, close + 1));
    } catch (_) {
      final inner = raw.substring(open + 1, close);
      out[key] = [
        for (final part in inner.split(RegExp(r'"\s*,\s*"')))
          part.replaceAll('"', '').trim(),
      ].where((s) => s.isNotEmpty).toList();
    }
  }
  return out;
}

/// Keep [authored] for any list [proposed] left empty. A mute or partial
/// Porch Life proposal must not silently wipe an authored wardrobe.
PorchLifeIdentity mergePorchLifeIdentity(
  PorchLifeIdentity authored,
  PorchLifeIdentity proposed,
) {
  List<String> keep(List<String> next, List<String> prior) =>
      next.isEmpty ? prior : next;
  return PorchLifeIdentity(
    ambitions: keep(proposed.ambitions, authored.ambitions),
    likes: keep(proposed.likes, authored.likes),
    dislikes: keep(proposed.dislikes, authored.dislikes),
    worn: keep(proposed.worn, authored.worn),
    carrying: keep(proposed.carrying, authored.carrying),
    intimateInto: keep(proposed.intimateInto, authored.intimateInto),
    intimateNotInto: keep(proposed.intimateNotInto, authored.intimateNotInto),
  );
}

/// Stamp a merged Porch Life proposal onto the duplicate's extensions.
/// Empty proposed lists keep the authored chips already on [base].
FrontPorchExtensions applyPorchLifeProposal(
  FrontPorchExtensions? base,
  PorchLifeIdentity proposed,
) {
  final merged = mergePorchLifeIdentity(porchLifeIdentityOf(base), proposed);
  final ext = base ?? FrontPorchExtensions();
  return ext.copyWith(
    ambitions: merged.ambitions,
    likes: merged.likes,
    dislikes: merged.dislikes,
    intimateInto: merged.intimateInto,
    intimateNotInto: merged.intimateNotInto,
    inventory: Pockets.cardJsonFrom(
      worn: merged.worn,
      carrying: merged.carrying,
    ),
  );
}

/// Chip lists already stored on a card — the Enhance review "Before" column.
PorchLifeIdentity porchLifeIdentityOf(FrontPorchExtensions? ext) {
  if (ext == null) return const PorchLifeIdentity();
  final p = Pockets.fromJson(ext.inventory);
  return PorchLifeIdentity(
    ambitions: List<String>.from(ext.ambitions),
    likes: List<String>.from(ext.likes),
    dislikes: List<String>.from(ext.dislikes),
    worn: p.wornDisplay,
    carrying: p.carryingDisplay,
    intimateInto: List<String>.from(ext.intimateInto),
    intimateNotInto: List<String>.from(ext.intimateNotInto),
  );
}

/// A model's list as chips: trimmed, no `{{user}}` belongings, each cut to
/// [maxLen], case-insensitive duplicates dropped, at most [cap]. Shared by
/// the Porch Life seed and the identity facts pass.
List<String> porchLifeChips(Object? raw, {int cap = 8, int maxLen = 80}) {
  if (raw is! List) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final item in raw) {
    var s = item.toString().trim();
    if (s.isEmpty) continue;
    if (s.contains('{{user}}')) continue;
    if (s.length > maxLen) s = s.substring(0, maxLen).trim();
    final key = s.toLowerCase();
    if (seen.contains(key)) continue;
    seen.add(key);
    out.add(s);
    if (out.length >= cap) break;
  }
  return out;
}
