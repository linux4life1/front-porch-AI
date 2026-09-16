// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_craft_mechanics.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_tools.dart';

/// Copy on the Setup step when Generate/Next is locked.
const String kWorldFromWikiToolsCopy =
    'Pick a tool-calling model (Qwen 27B, etc.). This wizard needs tools — '
    'it will not dump the wiki into one prompt.';

const int kWorldFromWikiScanDepth = 10;
const int kWorldFromWikiTokenBudget = 2800;

/// True when the wizard may run. Remote `/models` `tools` wins. Local GGUF
/// has no catalog advertisement, so a known tool-calling family is required.
bool worldFromWikiToolsOk({
  ModelApiCapabilities? remoteCaps,
  required bool isLocalBackend,
  String modelId = '',
}) {
  if (remoteCaps != null) return remoteCaps.advertisesTools;
  if (!isLocalBackend) return false;
  return localGgufLooksToolCapable(modelId);
}

/// Filename / remote id heuristic for local Kobold (no OpenRouter catalog).
bool localGgufLooksToolCapable(String modelId) {
  final n = modelId.toLowerCase();
  if (n.isEmpty) return false;
  const needles = <String>[
    'qwen',
    'glm',
    'llama-3',
    'llama3',
    'mistral',
    'mixtral',
    'command-r',
    'commandr',
    'gemma-3',
    'gemma3',
    'phi-4',
    'phi4',
    'deepseek',
    'kimi',
    'internlm',
    'yi-1',
    'nemotron',
    'hermes',
    'toolace',
    'functionary',
    'firefunction',
  ];
  for (final needle in needles) {
    if (n.contains(needle)) return true;
  }
  return false;
}

/// Build the library World. Climate off → no biome json, no place traits.
/// Climate-on without a custom biome fails closed (no stock Temperate).
/// Book recursion on, scan depth 10, token budget 2800.
World worldFromWikiDraft({
  required String name,
  required String description,
  required List<LorebookEntry> entries,
  bool climateEnabled = false,
  Map<String, dynamic>? biome,
}) {
  final trimmed = name.trim();
  final custom = climateEnabled && biome != null && biome.isNotEmpty;
  return World(
    name: trimmed.isEmpty ? 'Untitled world' : trimmed,
    description: description.trim(),
    lorebook: Lorebook(
      entries: List<LorebookEntry>.from(entries),
      recursiveScanning: true,
      scanDepth: kWorldFromWikiScanDepth,
      tokenBudget: kWorldFromWikiTokenBudget,
    ),
    climateEnabled: custom,
    biomeId: custom ? 'custom' : null,
    biomeJson: custom ? jsonEncode(biome) : null,
  );
}

/// Preview/Save gate. Abort or an empty signed shelf must not persist.
bool worldFromWikiCanSave({
  required bool aborted,
  required bool lorebooksOn,
  required List<LorebookEntry> entries,
}) {
  if (aborted) return false;
  if (!lorebooksOn) return true;
  return entries.isNotEmpty;
}

/// Client write payload. Empty, unsigned, or ToC-sized lists are rejected.
List<WorldProposedCard> parseSignedWorldWriteCards(dynamic raw) {
  if (raw is! List) return const [];
  final out = <WorldProposedCard>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final map = Map<String, dynamic>.from(e);
    if (!_signedFlag(map['signed'])) continue;
    final card = WorldProposedCard.tryParse(map);
    if (card == null) continue;
    out.add(card);
    if (out.length > kWorldScoutCardMax) return const [];
  }
  return out;
}

/// Pair generated prose to signed cards by name. No leftover force-pick.
List<WorldCraftDraft> matchWorldWriteBatch(
  List<WorldProposedCard> cards,
  List<WorldLoreWrite> generated,
) {
  final leftover = [...generated];
  final out = <WorldCraftDraft>[];
  for (final card in cards) {
    final want = card.name.toLowerCase();
    var hit = -1;
    for (var j = 0; j < leftover.length; j++) {
      if (leftover[j].name.toLowerCase() == want) {
        hit = j;
        break;
      }
    }
    if (hit < 0) continue;
    final g = leftover.removeAt(hit);
    out.add(
      WorldCraftDraft(
        name: g.name == 'Untitled' ? card.name : g.name,
        keys: g.keys.isEmpty ? card.keys : g.keys,
        content: g.content,
        role: card.role,
        group: card.group,
      ),
    );
  }
  return out;
}

bool _signedFlag(dynamic raw) {
  if (raw == true || raw == 1) return true;
  if (raw is String) {
    final s = raw.trim().toLowerCase();
    return s == 'true' || s == '1';
  }
  return false;
}
