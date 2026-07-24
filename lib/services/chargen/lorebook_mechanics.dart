// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/chargen/char_macro.dart';

/// One lorebook entry as the AI creator's LLM emits it: prose + a category.
///
/// The category (not raw SillyTavern config) is what the model produces — a
/// small, robust schema any local model can get right — and [assignLoreMechanics]
/// deterministically maps it to the World Info fields the runtime engine honors.
/// That keeps generated lorebooks "smart" without betting a weak model on ~40
/// config fields it would fumble.
///
/// Later stages will carry secondary keywords (contextual firing) and related-
/// entry names (recursion chains); Stage 1 uses [category] only.
class GeneratedLoreEntry {
  const GeneratedLoreEntry({
    required this.name,
    required this.key,
    required this.content,
    required this.category,
    this.secondary = '',
  });

  final String name;
  final String key;
  final String content;

  /// Raw category string from the model; normalized via [normalizeLoreCategory].
  final String category;

  /// Optional secondary/context keywords (Stage 2): comma-separated words that
  /// must ALSO be present (alongside a primary key) for the entry to fire, so it
  /// only surfaces in the right scene. Empty → the entry fires on its keys alone.
  final String secondary;
}

/// Stage 2: interchangeable ambient flavor (rumors, gossip, minor local events)
/// share ONE inclusion group, so only ONE surfaces at a time instead of dumping
/// every rumor at once. The engine's group winner is stable within a scene and
/// shifts as the scene's active lore changes (it is not re-randomized per turn).
const String kAmbientLoreGroup = 'ambient';

/// Stage 2: ambient flavor fires probabilistically (not on every triggered
/// turn), for unpredictability. Core lore stays at 100%.
const int kAmbientLoreProbability = 75;

/// The category vocabulary the generator prompt offers the model. Ordered from
/// world-defining (premise) to ambient (custom).
const List<String> kLoreCategories = [
  'premise',
  'faction',
  'location',
  'figure',
  'history',
  'item',
  'custom',
];

/// Survival/insertion `order` for a normalized category.
///
/// The engine fills its token budget in DESCENDING order and emits each block
/// ascending (verified: `lorebook_injector.dart` fill sort + per-position emit),
/// so a HIGHER value both survives a tight budget and sits closer to the
/// generation point. World-defining lore therefore outranks ambient flavor and
/// is never the first thing dropped when context is scarce.
int loreOrderForCategory(String category) {
  switch (normalizeLoreCategory(category)) {
    case 'premise':
      return 300;
    case 'faction':
      return 200;
    case 'location':
    case 'figure':
    case 'history':
    case 'item':
      return 120;
    case 'custom':
      return 60;
    default:
      // Unclassified (blank or unrecognized category): the neutral default —
      // the same tier a flat, category-less entry always had. Not demoted below
      // ambient 'custom', not promoted; just a normal keyword entry.
      return 100;
  }
}

/// Fold a model-emitted category string onto the canonical [kLoreCategories]
/// vocabulary, tolerating synonyms and casing (local models paraphrase).
///
/// Matching is WHOLE-WORD, not substring, so freeform values don't mis-map
/// (e.g. "underworld" is NOT premise, "folklore" is NOT history). A blank or
/// genuinely unrecognized value returns `''` — "unclassified" — which
/// [loreOrderForCategory] treats as the neutral 100 tier and which is never the
/// premise anchor.
String normalizeLoreCategory(String raw) {
  final c = raw.trim().toLowerCase();
  if (c.isEmpty) return '';
  if (kLoreCategories.contains(c)) return c;
  final words = c.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toSet();
  bool hasWord(Set<String> syn) => words.any(syn.contains);
  if (hasWord({'premise', 'setting', 'world', 'backdrop', 'overview'})) {
    return 'premise';
  }
  if (hasWord({'faction', 'order', 'guild', 'organization', 'power', 'group'})) {
    return 'faction';
  }
  if (hasWord({'location', 'place', 'region', 'city', 'realm', 'area'})) {
    return 'location';
  }
  if (hasWord({'figure', 'npc', 'person', 'character', 'individual'})) {
    return 'figure';
  }
  if (hasWord({'history', 'event', 'war', 'past'})) return 'history';
  if (hasWord({'item', 'artifact', 'relic', 'object', 'weapon', 'tech'})) {
    return 'item';
  }
  if (hasWord({'custom', 'rumor', 'ambient', 'legend', 'myth', 'culture'})) {
    return 'custom';
  }
  return '';
}

/// Build real [LorebookEntry]s from the generator's output, assigning the
/// SillyTavern mechanics the runtime engine honors.
///
/// **STAGE 1** — an always-on `premise` anchor + priority tiers by category.
/// **STAGE 2** — contextual firing (secondary keys the model supplies, kept at
/// the engine's default `andAny` logic so an entry needs a primary key AND a
/// secondary), plus variety for ambient flavor: every `custom` entry joins one
/// inclusion group (one surfaces per scan) and fires at [kAmbientLoreProbability]
/// so it's not on every turn.
/// **STAGE 3** — interconnected lore: [buildSmartLorebook] turns book-level
/// recursion ON so an entry whose content names another entry pulls that one in
/// (a faction → the ritual it guards → the relic). Every entry stays directly
/// reachable by its own keys — recursion is a bonus, never the only path, so a
/// model that doesn't interconnect just yields independent entries (no dead
/// reveals). The always-on anchor gets `preventRecursion` so it doesn't drag in
/// everything it happens to name. Everything else stays at [LorebookEntry]'s
/// defaults.
List<LorebookEntry> assignLoreMechanics(List<GeneratedLoreEntry> generated) {
  final entries = <LorebookEntry>[];
  var anchorUsed = false; // at most ONE always-on premise anchor
  for (final g in generated) {
    if (g.content.trim().isEmpty) continue; // skip empties from a sloppy model
    final category = normalizeLoreCategory(g.category);
    // The world backdrop is always in context (never keyword-gated) — but only
    // the FIRST premise becomes that anchor. Extra "premise" entries (a rambly
    // model, or a synonym over-match) stay high-priority yet keyword-gated, so
    // we never stack multiple always-injected blobs that silently eat the
    // token budget (constant entries still count against it).
    final isAnchor = category == 'premise' && !anchorUsed;
    if (isAnchor) anchorUsed = true;
    final isAmbient = category == 'custom';
    entries.add(
      LorebookEntry(
        name: g.name,
        key: g.key,
        // Stage 3: normalize any single-brace {pick}/{roll} the model emitted so
        // the dynamic "living detail" macro actually resolves at injection.
        content: fixDynamicMacroBraces(g.content),
        enabled: true,
        constant: isAnchor,
        order: loreOrderForCategory(category),
        // Stage 2 contextual firing. secondaryKeys with the default andAny logic
        // = fires only when a primary key AND ≥1 secondary are present. Empty on
        // most entries (fire on their keys alone); inert on the constant anchor.
        secondaryKeys: LorebookEntry.parseKeyList(g.secondary),
        // Stage 2 variety: ambient flavor shares one inclusion group (only one
        // surfaces at a time) and fires probabilistically; core lore is certain.
        group: isAmbient ? kAmbientLoreGroup : '',
        probability: isAmbient ? kAmbientLoreProbability : 100,
        // Stage 3: the always-on anchor's content is NOT rescanned for further
        // matches, so the backdrop never auto-drags in every faction it names;
        // recursion chains form among the contextually-triggered entries.
        preventRecursion: isAnchor,
      ),
    );
  }
  return entries;
}

/// Build the finished [Lorebook] from the generator's output: entries with their
/// assigned mechanics, plus book-level `recursiveScanning` ON (Stage 3) so the
/// interconnected lore fires regardless of the user's GLOBAL recursion setting —
/// the generated book opts into recursion because its content is written to
/// reference itself. Returns null when nothing usable was generated.
Lorebook? buildSmartLorebook(List<GeneratedLoreEntry> generated) {
  final entries = assignLoreMechanics(generated);
  if (entries.isEmpty) return null;
  return Lorebook(entries: entries, recursiveScanning: true);
}
