// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure parse for the chargen Porch Life seed (ambitions, likes, wardrobe,
// optional intimate). Kept out of the `character_gen_*.dart` parts so tests
// can feed a map without standing up CharacterGenService.

import 'dart:convert';

import 'package:front_porch_ai/models/models.dart' show FrontPorchExtensions;
import 'package:front_porch_ai/services/chat/chat.dart' show Pockets, kMaxWorn;

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
  });

  final List<String> ambitions;
  final List<String> likes;
  final List<String> dislikes;
  final List<String> worn;
  final List<String> carrying;
  final List<String> intimateInto;
  final List<String> intimateNotInto;

  bool get isEmpty =>
      ambitions.isEmpty &&
      likes.isEmpty &&
      dislikes.isEmpty &&
      worn.isEmpty &&
      carrying.isEmpty &&
      intimateInto.isEmpty &&
      intimateNotInto.isEmpty;
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
List<Map<String, dynamic>> porchLifeToolSchema({required bool nsfw}) {
  Map<String, dynamic> chips(String description) => {
    'type': 'array',
    'items': {'type': 'string'},
    'description': description,
  };
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

/// Pull chip lists out of a decoded object or a raw JSON/prose blob.
/// Intimate lists are dropped when [nsfw] is false even if the model sent them.
PorchLifeIdentity parsePorchLifeIdentity(Object? raw, {required bool nsfw}) {
  final map = _asStringKeyedMap(raw) ?? _decodeLoose(raw);
  if (map == null) return const PorchLifeIdentity();
  return PorchLifeIdentity(
    ambitions: _chips(map['ambitions']),
    likes: _chips(map['likes']),
    dislikes: _chips(map['dislikes']),
    worn: _chips(map['worn'], cap: kMaxWorn),
    carrying: _chips(map['carrying'], cap: kMaxWorn),
    intimateInto: nsfw
        ? _chips(map['intimate_into'] ?? map['intimateInto'])
        : const [],
    intimateNotInto: nsfw
        ? _chips(map['intimate_not_into'] ?? map['intimateNotInto'])
        : const [],
  );
}

Map<String, dynamic>? _asStringKeyedMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return {for (final e in raw.entries) e.key.toString(): e.value};
  }
  return null;
}

Map<String, dynamic>? _decodeLoose(Object? raw) {
  if (raw is! String) return null;
  final cleaned = raw.trim();
  final start = cleaned.indexOf('{');
  final end = cleaned.lastIndexOf('}');
  if (start < 0 || end <= start) return _regexLists(cleaned);
  try {
    final decoded = json.decode(cleaned.substring(start, end + 1));
    return _asStringKeyedMap(decoded);
  } catch (_) {
    return _regexLists(cleaned);
  }
}

/// When json.decode fails (unescaped quotes), pull each array by key.
Map<String, dynamic> _regexLists(String raw) {
  final out = <String, dynamic>{};
  for (final key in _kChipKeys) {
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

List<String> _chips(Object? raw, {int cap = 8}) {
  if (raw is! List) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final item in raw) {
    var s = item.toString().trim();
    if (s.isEmpty) continue;
    if (s.contains('{{user}}')) continue;
    if (s.length > 80) s = s.substring(0, 80).trim();
    final key = s.toLowerCase();
    if (seen.contains(key)) continue;
    seen.add(key);
    out.add(s);
    if (out.length >= cap) break;
  }
  return out;
}
