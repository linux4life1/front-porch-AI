// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PlaceFactory — mints a named place from narration into a child World.
//
// Design: docs/design/locations-within-worlds.md §3 "Minted places".
// The EVAL transport (native tool call first, then the JSON text floor) —
// the same negotiation the clock judge rides — so a local KoboldCpp can
// mint, not just API models. The result persists through
// WorldRepository.saveWorld, so name collisions, cycle checks, export and
// the Stoop envelope behave exactly like a hand-made place. Nothing is
// minted until a human taps: this class is HOW, the dialog is WHEN.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/services/world_repository.dart';

/// Outcome of one mint attempt — reported, never thrown into the chat
/// loop (the SceneGuestFactory discipline).
class PlaceMintResult {
  const PlaceMintResult.success(this.world) : error = null;
  const PlaceMintResult.failure(this.error) : world = null;
  final World? world;
  final String? error;
  bool get ok => world != null;
}

/// Mints a place beside SceneGuestFactory: name + descriptor + the
/// narration lines where the place was portrayed, plus the parent
/// chain's own description and lore as grounding.
class PlaceFactory {
  PlaceFactory(
    this._worldRepository, {
    this.fireToolEval,
    this.fireTextEval,
    this.probe,
    this.getBackendIdentity,
  });
  final WorldRepository _worldRepository;
  final Object? fireToolEval;
  final Future<String?> Function(
    String prompt, {
    void Function(String)? onChunk,
  })?
  fireTextEval;
  final ToolTransportProbe? probe;
  final String Function()? getBackendIdentity;

  /// The injection law gives the Setting ~600 chars total; a minted
  /// description sized above this would immediately start squeezing the
  /// traits out of the prompt it was minted to enrich.
  static const int descriptionBudget = 250;
  Future<PlaceMintResult> mint({
    required String name,
    required String descriptor,
    required World setting,
    required String sceneGrounding,
  }) async {
    // A mint never re-mints an existing place: no "Name (2)" beside the
    // original, no model call burned on a duplicate. The judge only sees
    // the reachable offer, so this is the honest floor under the flag
    // seam's redirect — a name the library already answers to refuses
    // here through the ONE collision key, [placeNameKey]. Collisions
    // between hand-made worlds and imports still rename in saveWorld;
    // only this model path refuses.
    final trimmedName = name.trim();
    final want = placeNameKey(name);
    for (final w in _worldRepository.worlds) {
      if (placeNameKey(w.name) == want) {
        return PlaceMintResult.failure(
          'a place named "${w.name}" already exists',
        );
      }
    }
    if (fireToolEval == null || fireTextEval == null || probe == null) {
      return const PlaceMintResult.failure('the LLM backend is not ready');
    }
    final prompt = _buildPrompt(
      name: name,
      descriptor: descriptor,
      sceneGrounding: sceneGrounding,
      ancestorGrounding: _ancestorGrounding(setting),
    );
    String? raw;
    try {
      raw = await fireStructuredEval(
        probe: probe!,
        backendIdentity: getBackendIdentity?.call() ?? '',
        debugLabel: kPlaceMintTool,
        tools: kPlaceMintTools,
        toolChoice: kPlaceMintTool,
        buildPrompt: ({required bool toolsMode}) => prompt,
        callToText: (resp) => realismToolCallToJson(kPlaceMintTool, resp.calls),
        fireToolEval: fireToolEval!,
        fireTextEval: fireTextEval!,
      );
    } catch (e) {
      debugPrint('[PlaceFactory] transport failed: $e');
      return PlaceMintResult.failure('transport failed: $e');
    }
    final draft = raw == null ? null : _parseDraft(raw);
    if (draft == null) {
      return const PlaceMintResult.failure(
        'the LLM did not produce a valid place draft',
      );
    }
    if (draft.description.trim().isEmpty) {
      return const PlaceMintResult.failure(
        'the LLM did not produce a description',
      );
    }
    if (draft.entries.length < 3 || draft.entries.length > 5) {
      return PlaceMintResult.failure(
        'the LLM did not produce enough lore entries '
        '(${draft.entries.length} of 3–5)',
      );
    }
    final parentId = _parentIdWithinCap(setting);
    if (parentId == null) {
      return const PlaceMintResult.failure(
        'no parent leaves room under the depth cap',
      );
    }
    final world = World(
      name: trimmedName,
      description: _fitBudget(draft.description.trim()),
      lorebook: Lorebook(entries: _entriesWithGroups(draft, setting)),
      parentWorldId: parentId,
      // Design §7: inheritance is the default for a minted child — the
      // palace courtyard takes the palace's weather; minting a climate
      // on the fly is never a thing.
      climateEnabled: false,
    );
    world.placeTraits['madeBy'] = 'model';
    try {
      await _worldRepository.saveWorld(world);
    } catch (e) {
      debugPrint('[PlaceFactory] save failed: $e');
      return PlaceMintResult.failure('failed to save the minted place: $e');
    }
    return PlaceMintResult.success(world);
  }

  /// Mint under the Setting; at the cap (town › building › room = two
  /// levels below the root) the new place joins the Setting's PARENT as
  /// a sibling — design §3 "or its parent when the depth cap is hit".
  String? _parentIdWithinCap(World setting) {
    final depth = worldChain(setting, _worldRepository.worldById).length - 1;
    if (depth >= 2) return setting.parentWorldId;
    return setting.id;
  }

  String _ancestorGrounding(World setting) {
    final parts = <String>[
      for (final w in worldChain(setting, _worldRepository.worldById)) ...[
        if (w.description.trim().isNotEmpty) w.description.trim(),
        for (final e in w.lorebook.entries.where((e) => e.enabled))
          if (e.content.trim().isNotEmpty) e.content.trim(),
      ],
    ];
    return parts.join('\n\n');
  }

  /// The inclusion-group law (design §3): where an ancestor entry shares
  /// a key with a minted one, the new entry joins that group, so the
  /// palace teacup reads as the palace's version and exactly one of the
  /// group injects. Keys first-seen wins the group, mirroring how a
  /// hand-edited book is authored.
  List<LorebookEntry> _entriesWithGroups(_Draft draft, World setting) {
    final ancestorGroups = <({Set<String> keys, String group})>[
      for (final w in worldChain(setting, _worldRepository.worldById))
        for (final e in w.lorebook.entries.where((e) => e.enabled))
          if (e.group.isNotEmpty)
            (
              keys: e.keys.map((k) => k.toLowerCase().trim()).toSet(),
              group: e.group,
            ),
    ];
    return [
      for (final d in draft.entries)
        () {
          final keys = d.keysString
              .split(',')
              .map((k) => k.trim())
              .where((k) => k.isNotEmpty)
              .toList();
          final keySet = keys.map((k) => k.toLowerCase()).toSet();
          final match = ancestorGroups.where(
            (a) => a.keys.intersection(keySet).isNotEmpty,
          );
          return LorebookEntry(
            name: d.name.trim(),
            keys: keys,
            content: d.content.trim(),
            group: match.isEmpty ? '' : match.first.group,
          );
        }(),
    ];
  }

  String _fitBudget(String description) =>
      description.length <= descriptionBudget
      ? description
      : '${description.substring(0, descriptionBudget - 1).trimRight()}…';
  String _buildPrompt({
    required String name,
    required String descriptor,
    required String sceneGrounding,
    required String ancestorGrounding,
  }) {
    final context = ancestorGrounding.isEmpty
        ? ''
        : '\nThe setting and its ancestors (match their voice, do not '
              'contradict them):\n$ancestorGrounding\n';
    return 'You are drafting a place that a story just arrived at.\n'
        'Name: $name\nIt is: $descriptor\n'
        'The narration that portrayed it:\n$sceneGrounding\n$context\n'
        'Write "short_description" (at most $descriptionBudget characters — '
        'it reaches the model every turn as scene-setting prose) and '
        '"lore_entries": 3 to 5 entries that make THIS place specific, '
        'each with "name", comma-separated trigger "keys", and "content". '
        'Ground everything in the narration; invent nothing that '
        'contradicts the ancestors.\n'
        'Respond with ONLY a flat JSON object containing '
        '"short_description" and "lore_entries" — no markdown.';
  }

  _Draft? _parseDraft(String text) {
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final entries = [
      for (final raw
          in decoded['lore_entries'] is List
              ? decoded['lore_entries'] as List
              : const [])
        if (raw is Map &&
            raw['name']?.toString().trim().isNotEmpty == true &&
            raw['content']?.toString().trim().isNotEmpty == true)
          _DraftEntry(
            name: raw['name'].toString(),
            keysString: raw['keys']?.toString() ?? '',
            content: raw['content'].toString(),
          ),
    ];
    return _Draft(
      description: decoded['short_description']?.toString() ?? '',
      entries: entries,
    );
  }
}

class _Draft {
  const _Draft({required this.description, required this.entries});
  final String description;
  final List<_DraftEntry> entries;
}

class _DraftEntry {
  const _DraftEntry({
    required this.name,
    required this.keysString,
    required this.content,
  });
  final String name;
  final String keysString;
  final String content;
}
