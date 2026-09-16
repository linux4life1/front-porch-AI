// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/capability.dart';

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
    climateEnabled: climateEnabled,
    biomeId: custom ? 'custom' : null,
    biomeJson: custom ? jsonEncode(biome) : null,
  );
}
