// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_craft_mechanics.dart';

const String kWorldLoreEntryToolName = 'write_lorebook_entry';
const String kWorldLoreBatchToolName = 'write_lorebook_entries';
const String kWorldScoutToolName = 'propose_world_cards';

const int kWorldScoutCardMin = 20;
const int kWorldScoutCardMax = 40;

/// Signed cards per write tool call. One Grok/GLM round-trip per batch,
/// not per card.
const int kWorldWriteBatchSize = 8;

const int kWorldLoreContentMin = 160;
const int kWorldLoreContentMax = 330;

const String kWorldClimateToolName = 'write_world_climate';

const String kWorldScoutPrompt =
    'Cast list not table of contents. Merge numbered chapters / drafts / '
    'images into one card when they are the same subject. 20–40 cards. '
    'Role era/hub/leaf/crown. Optional inclusion group slug from this book. '
    'they/them. Do not invent climate. Do not use another setting\'s '
    'faction names.';

/// Scout: one shelf of cards from index titles. Tools-only.
List<Map<String, dynamic>> worldScoutToolSchema() {
  return [
    {
      'type': 'function',
      'function': {
        'name': kWorldScoutToolName,
        'description':
            'Propose 20–40 lorebook cards for this wiki. Cast list, not a '
            'table of contents. Merge numbered chapters, drafts, and image '
            'pages of the same subject into one card. Roles: era, hub, leaf, '
            'crown. Optional group is an inclusion slug from THIS book only.',
        'parameters': {
          'type': 'object',
          'properties': {
            'cards': {
              'type': 'array',
              'description': 'Proposed cards, 20 to 40.',
              'items': {
                'type': 'object',
                'properties': {
                  'name': {
                    'type': 'string',
                    'description':
                        'Short card title (a person, place, or faith).',
                  },
                  'keys': {
                    'description':
                        'Trigger words, comma-separated string or array.',
                  },
                  'role': {
                    'type': 'string',
                    'enum': ['era', 'hub', 'leaf', 'crown'],
                    'description':
                        'era = always-on era card (at most one). '
                        'hub = place/faction that may pull leaves. '
                        'leaf = a person or detail. '
                        'crown = a peak figure or relic in a group.',
                  },
                  'sourceTitles': {
                    'type': 'array',
                    'items': {'type': 'string'},
                    'description':
                        '1–3 index titles to read when this card is signed.',
                  },
                  'group': {
                    'type': 'string',
                    'description':
                        'Optional inclusion group slug from this book '
                        '(a faith, a street, a guild). Not a borrowed setting.',
                  },
                },
                'required': ['name', 'role', 'sourceTitles'],
              },
            },
          },
          'required': ['cards'],
        },
      },
    },
  ];
}

final _loreEntryItem = {
  'type': 'object',
  'properties': {
    'name': {
      'type': 'string',
      'description': 'Short entry title (the card name is fine).',
    },
    'keys': {
      'description': 'Alias trigger words, comma-separated string or array.',
    },
    'content': {
      'type': 'string',
      'description':
          'The lorebook card: 160–330 characters a resident would '
          'know. No wiki markup. No "according to the wiki". they/them '
          'for unnamed scouts or bakers.',
    },
  },
  'required': ['name', 'keys', 'content'],
};

/// Several signed cards in one tool call. Tools-only.
List<Map<String, dynamic>> worldLoreBatchToolSchema() {
  return [
    {
      'type': 'function',
      'function': {
        'name': kWorldLoreBatchToolName,
        'description':
            'Write one lorebook entry per signed card in this batch. '
            'Ground every sentence in that card\'s articles. Do not invent '
            'biomes, weather, or facts the pages do not state. 160–330 '
            'characters each. they/them for unnamed people. Return every '
            'card in this batch.',
        'parameters': {
          'type': 'object',
          'properties': {
            'entries': {
              'type': 'array',
              'description': 'One object per signed card, same names.',
              'items': _loreEntryItem,
            },
          },
          'required': ['entries'],
        },
      },
    },
  ];
}

List<Map<String, dynamic>> worldClimateToolSchema() {
  return [
    {
      'type': 'function',
      'function': {
        'name': kWorldClimateToolName,
        'description':
            'Author a custom biome for THIS wiki plus up to 3 weather '
            'lorebook cards (current, boreal, storm). Ground in the articles. '
            'Do not copy Earth "temperate Midwest" filler. Season ids stay '
            'winter/spring/summer/autumn. Weights are 7 ints (clear, cloudy, '
            'overcast, fog, rain, storm, snow) summing near 100.',
        'parameters': {
          'type': 'object',
          'properties': {
            'displayName': {'type': 'string'},
            'description': {'type': 'string'},
            'feel': {'type': 'string'},
            'diurnalAmplitude': {'type': 'number'},
            'seasonLabels': {
              'type': 'object',
              'description': 'winter/spring/summer/autumn display names',
            },
            'baseTemp': {
              'type': 'object',
              'description': 'season → 0-4 band index',
            },
            'weights': {'type': 'object', 'description': 'season → 7 integers'},
            'conditionSkin': {
              'type': 'object',
              'description':
                  'clear/cloudy/overcast/fog/rain/storm/snow → '
                  '{label, emoji, stance, flavour}',
            },
            'loreCards': {
              'type': 'array',
              'description': 'Up to 3 weather doorbell cards.',
              'items': _loreEntryItem,
            },
          },
          'required': [
            'displayName',
            'description',
            'feel',
            'weights',
            'baseTemp',
          ],
        },
      },
    },
  ];
}

class WorldLoreWrite {
  const WorldLoreWrite({
    required this.name,
    required this.keys,
    required this.content,
  });

  final String name;
  final List<String> keys;
  final String content;
}

WorldLoreWrite? parseWorldLoreToolCall(Map<String, dynamic> args) {
  final content = clipLoreContent(args['content']?.toString() ?? '');
  if (content.isEmpty) return null;
  final name = args['name']?.toString().trim() ?? '';
  final keys = _keysOf(args['keys']);
  return WorldLoreWrite(
    name: name.isEmpty ? 'Untitled' : name,
    keys: keys,
    content: content,
  );
}

/// Batch tool, or a single-entry call treated as a one-item batch.
List<WorldLoreWrite> parseWorldLoreBatchCalls(List<LlmToolCall> calls) {
  final out = <WorldLoreWrite>[];
  for (final call in calls) {
    if (call.name == kWorldLoreBatchToolName) {
      final raw = call.arguments['entries'] ?? call.arguments['cards'];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final parsed = parseWorldLoreToolCall(Map<String, dynamic>.from(e));
          if (parsed != null) out.add(parsed);
        }
      }
      continue;
    }
    if (call.name == kWorldLoreEntryToolName) {
      final parsed = parseWorldLoreToolCall(call.arguments);
      if (parsed != null) out.add(parsed);
    }
  }
  return out;
}

class WorldClimateWrite {
  const WorldClimateWrite({required this.biome, this.lore = const []});

  final Map<String, dynamic> biome;
  final List<WorldLoreWrite> lore;
}

WorldClimateWrite? parseWorldClimateCalls(List<LlmToolCall> calls) {
  for (final call in calls) {
    if (call.name != kWorldClimateToolName) continue;
    final args = call.arguments;
    final raw = <String, dynamic>{
      'id': 'custom',
      'displayName': args['displayName']?.toString() ?? 'Custom',
      'description': args['description']?.toString() ?? '',
      'feel': args['feel']?.toString() ?? '',
      if (args['weights'] is Map) 'weights': args['weights'],
      if (args['baseTemp'] is Map) 'baseTemp': args['baseTemp'],
      if (args['seasonLabels'] is Map) 'seasonLabels': args['seasonLabels'],
      if (args['conditionSkin'] is Map) 'conditionSkin': args['conditionSkin'],
      if (args['diurnalAmplitude'] is num)
        'diurnalAmplitude': (args['diurnalAmplitude'] as num).toDouble(),
    };
    final biome = Biome.fromJson(raw);
    if (biome.validate().isNotEmpty) continue;
    final lore = <WorldLoreWrite>[];
    final cards = args['loreCards'] ?? args['entries'];
    if (cards is List) {
      for (final e in cards.take(3)) {
        if (e is! Map) continue;
        final parsed = parseWorldLoreToolCall(Map<String, dynamic>.from(e));
        if (parsed != null) lore.add(parsed);
      }
    }
    return WorldClimateWrite(biome: biome.toJson(), lore: lore);
  }
  return null;
}

/// Parse scout tool calls into proposed cards. Drops unknown roles, empty
/// names, and (when [catalog] is set) cards whose sources miss the index.
/// Matched sources keep the catalog's original title casing so later
/// `getArticleFull` hits the same page MediaWiki/Tiddly listed.
List<WorldProposedCard> parseWorldScoutToolCalls(
  List<LlmToolCall> calls, {
  Iterable<String>? catalog,
}) {
  final byLower = catalog == null
      ? null
      : {for (final t in catalog) t.toLowerCase(): t};
  final out = <WorldProposedCard>[];
  final seen = <String>{};
  for (final call in calls) {
    if (call.name != kWorldScoutToolName) continue;
    for (final item in _cardMaps(call.arguments)) {
      final parsed = WorldProposedCard.tryParse(item);
      if (parsed == null) continue;
      var sources = parsed.sourceTitles;
      if (byLower != null) {
        sources = [
          for (final t in sources)
            if (byLower[t.toLowerCase()] != null) byLower[t.toLowerCase()]!,
        ];
        if (sources.isEmpty) continue;
      }
      final key = parsed.name.toLowerCase();
      if (!seen.add(key)) continue;
      out.add(
        WorldProposedCard(
          name: parsed.name,
          keys: parsed.keys,
          role: parsed.role,
          sourceTitles: sources.take(3).toList(),
          group: parsed.group,
        ),
      );
      if (out.length >= kWorldScoutCardMax) return out;
    }
  }
  return out;
}

List<Map<String, dynamic>> _cardMaps(Map<String, dynamic> args) {
  final cards = args['cards'] ?? args['card'];
  if (cards is List) {
    return [
      for (final e in cards)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }
  if (cards is Map) return [Map<String, dynamic>.from(cards)];
  if (args['name'] != null && args['role'] != null) {
    return [args];
  }
  return const [];
}

List<String> _keysOf(dynamic raw) {
  final parts = <String>[];
  void add(String s) {
    for (final p in s.split(',')) {
      final t = p.trim();
      if (t.isNotEmpty) parts.add(t);
    }
  }

  if (raw is List) {
    for (final e in raw) {
      add(e.toString());
    }
  } else {
    add(raw?.toString() ?? '');
  }
  return parts;
}

/// Collapse whitespace and cut at a sentence near [kWorldLoreContentMax].
String clipLoreContent(String raw) {
  final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s.length <= kWorldLoreContentMax) return s;
  final cut = s.substring(0, kWorldLoreContentMax);
  var at = cut.lastIndexOf('. ');
  final bang = cut.lastIndexOf('! ');
  final q = cut.lastIndexOf('? ');
  if (bang > at) at = bang;
  if (q > at) at = q;
  if (at >= kWorldLoreContentMin - 1) {
    return cut.substring(0, at + 1).trim();
  }
  return cut.trim();
}

bool wikiTitleLooksClimate(String title) {
  final n = title.toLowerCase();
  if (n.startsWith(r'$:/') || n.contains('draft of')) return false;
  if (n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.gif')) {
    return false;
  }
  const needles = [
    'climate',
    'current',
    'boreal',
    'storm',
    'wind',
    'leyline',
    'mana',
  ];
  for (final needle in needles) {
    if (n.contains(needle)) return true;
  }
  return false;
}
