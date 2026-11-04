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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/place_factory.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/services/world_repository.dart';

/// Living Worlds for the open chat: the Setting slot (weather, prose) and
/// the Lore slots (books only), the climate spans, and the scene move and
/// minted place the clock judge suggests.
class ChatPlaces {
  ChatPlaces(this._g);

  final RealismGraph _g;

  /// Primary Setting + Lore slots for the open session. Loaded on session
  /// open; a group template seeds new chats.
  ChatPlaceSlots slots = const ChatPlaceSlots();

  /// Hydrated mid-chat climate spans + world default (Living Worlds phase 1).
  BiomeSchedule biomes = const BiomeSchedule();

  /// Slice 6: suggested scene move + per-setting decline memory.
  final SceneMoveState sceneMoves = SceneMoveState();

  WorldRepository get _worldRepository => _g.deps.services.worlds;
  String? get _sessionId => _g.session.currentSessionId;
  TimeService get _timeService => _g.time;

  /// Setting slot (0..1) — owns weather / room description for this chat.
  String? get primaryId => slots.primaryId;

  Future<void> reload() async {
    final sid = _sessionId;
    if (sid == null) {
      slots = const ChatPlaceSlots();
      biomes = const BiomeSchedule();
      return;
    }
    final session = _g.session;
    try {
      // A chat opened BEFORE its character had a world predates any decision
      // about attachments, so its empty list means "undecided" — give it the
      // character's worlds now. Chats where the user actually chose (including
      // choosing none) are flagged and skipped, so a deliberate detach sticks.
      final refs = session.activeGroup == null
          ? (session.activeCharacter?.worldNames ?? const <String>[])
          : const <String>[];
      final loreRefs = session.activeGroup == null
          ? session.activeCharacter?.loreWorldNames
          : null;
      if (refs.isNotEmpty || (loreRefs?.isNotEmpty ?? false)) {
        await _worldRepository.backfillChatWorldsFromCharacter(
          chatId: sid,
          characterWorldRefs: refs,
          characterLoreRefs: loreRefs,
        );
      }
      final attached = await _worldRepository.getChatWorldAttachments(sid);
      slots = ChatPlaceSlots(
        primaryId: attached.primaryId,
        loreIds: List.unmodifiable(attached.loreIds),
      );
    } catch (e) {
      debugPrint('[Chat] chat world load failed: $e');
      slots = const ChatPlaceSlots();
    }
    await _reloadBiomeSchedule();
  }

  Future<void> _reloadBiomeSchedule() async {
    final sid = _sessionId;
    if (sid == null) {
      biomes = const BiomeSchedule();
      return;
    }
    try {
      final rows = await _worldRepository.getChatBiomeSpanRows(sid);
      biomes = BiomeSchedule.fromJsonSpans(
        rows: rows,
        worldDefault: _worldDefaultBiome,
      );
    } catch (e) {
      debugPrint('[Chat] biome schedule load failed: $e');
      biomes = BiomeSchedule(worldDefault: _worldDefaultBiome);
    }
  }

  Future<void> setChatWorldIds(List<String> worldIds) async {
    final sid = _sessionId;
    if (sid == null) return;
    // Flat list:
    // - Primary still listed → keep role, remaining become lore (no auto-promote).
    // - Primary empty → seed-style partition (first climate-on → Setting).
    // - Primary dropped from list → stay empty; all listed ids are lore.
    final currentPrimary = slots.primaryId;
    if (currentPrimary != null && worldIds.contains(currentPrimary)) {
      await setChatPlaceSlots(
        primaryId: currentPrimary,
        loreIds: [
          for (final id in worldIds)
            if (id != currentPrimary) id,
        ],
      );
      return;
    }
    if (currentPrimary == null) {
      final partition = partitionLinkedPlaces(
        worldIds: worldIds,
        isClimateEnabled: (id) => _worldRepository.climateAuthorFor(id) != null,
      );
      await setChatPlaceSlots(
        primaryId: partition.primaryId,
        loreIds: partition.loreIds,
      );
      return;
    }
    await setChatPlaceSlots(primaryId: null, loreIds: worldIds);
  }

  /// Setting + Lore writer (Story Tools / web). Empty both = decided empty.
  Future<void> setChatPlaceSlots({
    String? primaryId,
    List<String> loreIds = const [],
  }) async {
    final sid = _sessionId;
    if (sid == null) return;
    // A move that changes the climate author must not rewrite history:
    // pin the old author's biome from day 1 (only if nothing is pinned
    // there yet — a user's dropdown span at day 1 stays law), then let
    // the new author take over from the current story day. Same
    // ChatBiomeSpans machinery the climate dropdown uses.
    final oldAuthorId = slots.primaryId == null
        ? null
        : _worldRepository.climateAuthorFor(slots.primaryId!)?.id;
    await _worldRepository.setChatWorldAttachments(
      sid,
      primaryId: primaryId,
      loreIds: loreIds,
    );
    final resolvedPrimary = (primaryId != null && primaryId.isNotEmpty)
        ? primaryId
        : null;
    // Slice 6: any Setting change — accepted suggestion, manual dropdown,
    // attach flow — retires the decline memory and any still-open offer,
    // both of which were written AT the old place. ("Stay at the Tea
    // Rooms" must not mean "never move anywhere, ever".)
    if (resolvedPrimary != slots.primaryId) {
      sceneMoves.settingChanged();
    }
    slots = ChatPlaceSlots(
      primaryId: resolvedPrimary,
      loreIds: List.unmodifiable([
        for (final id in loreIds)
          if (id.isNotEmpty && id != resolvedPrimary) id,
      ]),
    );
    final newAuthor = resolvedPrimary == null
        ? null
        : _worldRepository.climateAuthorFor(resolvedPrimary);
    if (newAuthor != null && newAuthor.id != oldAuthorId) {
      final day = _timeService.dayCount < 1 ? 1 : _timeService.dayCount;
      if (oldAuthorId != null && day > 1) {
        final rows = await _worldRepository.getChatBiomeSpanRows(sid);
        if (!rows.any((r) => r.effectiveFromDay == 1)) {
          final oldAuthor = _worldRepository.worldById(oldAuthorId);
          if (oldAuthor != null) {
            await _worldRepository.setChatBiome(
              chatId: sid,
              dayCount: 1,
              biome: biomeOfAuthor(oldAuthor),
            );
          }
        }
      }
      await _worldRepository.setChatBiome(
        chatId: sid,
        dayCount: day,
        biome: biomeOfAuthor(newAuthor),
      );
    }
    await _reloadBiomeSchedule();
    _g.deps.notify();
  }

  /// Insert a mid-chat climate changeover from the story day onward.
  /// No-op when Primary is empty or climate-off (lore never authors climate).
  Future<void> setChatClimate(Biome biome) async {
    final sid = _sessionId;
    if (sid == null) return;
    final chain = slots.primaryId == null
        ? const <World>[]
        : _worldRepository.chainFor(slots.primaryId!);
    if (!chainAllowsClimate(chain)) return;
    final day = _timeService.dayCount < 1 ? 1 : _timeService.dayCount;
    await _worldRepository.setChatBiome(
      chatId: sid,
      dayCount: day,
      biome: biome,
    );
    await _reloadBiomeSchedule();
    _g.deps.notify();
  }

  /// Climate from the Setting's chain author (Living Worlds, locations
  /// slice 2): a location inherits the nearest climate-enabled ancestor;
  /// the custom-climate dropdown id is `world:<climate-author-id>`. Lore
  /// attachments never author the schedule default. Group.worldIds ghost
  /// removed — decided empty stays empty. Temperate is a schedule
  /// placeholder only; the weather gate stays off when the chain has no
  /// climate author.
  /// The full biome an authoring world speaks: built-in id, custom JSON
  /// renamed `world:<id>`, or temperate when it carries no climate data.
  /// One definition for the schedule default and for the changeover spans
  /// a Setting swap records, so the two can never disagree.
  Biome biomeOfAuthor(World w) {
    if (w.biomeId == null && w.biomeJson == null) return Biome.temperate;
    final b = Biome.resolve(biomeId: w.biomeId, biomeJson: w.biomeJson);
    return w.biomeJson != null ? b.withId('world:${w.id}') : b;
  }

  Biome get _worldDefaultBiome {
    final id = slots.primaryId;
    if (id == null) return Biome.temperate;
    final w = _worldRepository.climateAuthorFor(id);
    if (w == null) return Biome.temperate;
    return biomeOfAuthor(w);
  }

  // ── The scene move the clock judge suggests ───────────────────────────

  /// The judge's arrival answer, routed from the clock call (design: the
  /// service only FLAGS). Ignores an id equal to the current Setting —
  /// you are already there, and a stale tool model may say so.
  void flagSuggestedPlaceMove(String id) {
    if (id.isEmpty || id == primaryId) return;
    final name = _worldRepository.worldById(id)?.name ?? id;
    sceneMoves.pending = PendingPlaceMove(id: id, name: name);
    _g.deps.notify();
  }

  /// Move: run the manual path exactly as the Places dropdown does —
  /// the old Setting demotes to the top of Lore so its book stays live
  /// for the rest of the scene, and the biome-span machinery inside
  /// [setChatPlaceSlots] pins the old weather for earlier days.
  Future<void> acceptPlaceMove() async {
    final move = sceneMoves.pending;
    if (move == null) return;
    final old = primaryId;
    await setChatPlaceSlots(
      primaryId: move.id,
      loreIds: [
        if (old != null && old != move.id) old,
        for (final l in slots.loreIds)
          if (l != move.id && l != old) l,
      ],
    );
  }

  /// Stay: dismiss the offer and remember the decline FOR THIS SETTING —
  /// the same place is not re-offered until the scene moves (or the
  /// author moves it), then arrival is honestly re-judged from there.
  void declinePlaceMove() {
    final move = sceneMoves.pending;
    if (move == null) return;
    sceneMoves.decline(move.id, primaryId);
    _g.deps.notify();
  }

  // ── Slice 7 mint seam: hold the proposal, hand it to PlaceFactory on the
  // tap, remember ignores ──────────────────────────────────────────────

  void flagSuggestedPlaceMint(String name, String descriptor) {
    if (name.trim().isEmpty) return;
    // A mint never re-mints an existing place. The judge only sees the
    // one-hop reachable offer, so a reply can "arrive" at a name the
    // library already holds on another branch — that arrival rides the
    // MOVE dialog for the place that exists, because a mint of it could
    // only ever save "Name (2)" beside the original. Match runs through
    // the ONE collision key, [placeNameKey] — the same law the mint's
    // own refusal below applies.
    final existing = _existingWorldNamed(name);
    if (existing != null) {
      debugPrint(
        '[Realism:Mint] "$name" already exists (${existing.id}) — '
        'offering the move instead',
      );
      if (sceneMoves.isDeclined(existing.id)) return;
      flagSuggestedPlaceMove(existing.id); // drops it when already there
      return;
    }
    final setting = primaryId == null
        ? null
        : _worldRepository.worldById(primaryId!);
    sceneMoves.mints.pending = ProposedPlace(
      name: name.trim(),
      descriptor: descriptor.trim(),
      settingName: setting?.name ?? '',
    );
    debugPrint('[Realism:Mint] suggested place pending: $name');
    _g.deps.notify();
  }

  /// The library's answer to a proposed place name, matched through the
  /// ONE collision key, [placeNameKey]. When several worlds answer, the
  /// scene can reach decides — a reachable one wins over a far branch.
  World? _existingWorldNamed(String name) {
    final want = placeNameKey(name);
    final matches = _worldRepository.worlds
        .where((w) => placeNameKey(w.name) == want)
        .toList();
    if (matches.isEmpty) return null;
    final setting = primaryId == null
        ? null
        : _worldRepository.worldById(primaryId!);
    if (setting == null) return matches.first;
    final reachable = reachablePlaces(
      setting,
      _worldRepository.placeWorlds,
      _worldRepository.worldById,
    ).map((w) => w.id).toSet();
    return matches.firstWhere(
      (w) => reachable.contains(w.id),
      orElse: () => matches.first,
    );
  }

  /// Add (and optionally move the scene into) the minted place. The
  /// mint reads the live narration window for grounding, saves through
  /// the ONE repository law, and on 'alsoMove' runs the SAME slot swap
  /// a manual move runs (old setting demotes to top of Lore). Returns
  /// the result so the dialog can speak; the pending flag clears on
  /// success or honest failure — a refused draft must not nag, the
  /// author just declined a bad guess.
  Future<PlaceMintResult> acceptMintedPlace({required bool alsoMove}) async {
    final proposal = sceneMoves.mints.pending;
    final settingId = primaryId;
    if (proposal == null) {
      return const PlaceMintResult.failure('nothing is being proposed');
    }
    final setting = settingId == null
        ? null
        : _worldRepository.worldById(settingId);
    if (setting == null) {
      sceneMoves.mints.resolve();
      _g.deps.notify();
      return const PlaceMintResult.failure(
        'the scene has no setting to place it under',
      );
    }
    final messages = _g.session.messages;
    final grounding = [
      for (final m
          in messages.length <= 6
              ? messages
              : messages.sublist(messages.length - 6))
        if (m.displayText.trim().isNotEmpty) m.displayText.trim(),
    ].join('\n');
    // Constructed at the call site like SceneGuestFactory; the eval seams
    // make a local KoboldCpp able to mint too — tools first, text floor
    // (design §7).
    final transport = _g.transport;
    final factory = PlaceFactory(
      _worldRepository,
      fireToolEval: transport.fireToolEval,
      fireTextEval: (p, {onChunk}) =>
          _g.transport.fireLLMEval(p, onChunk: onChunk),
      probe: transport.probe,
      getBackendIdentity: () => transport.backendIdentity,
    );
    final result = await factory.mint(
      name: proposal.name,
      descriptor: proposal.descriptor,
      setting: setting,
      sceneGrounding: grounding,
    );
    sceneMoves.mints.resolve();
    if (result.ok && alsoMove && result.world != null) {
      await setChatPlaceSlots(
        primaryId: result.world!.id,
        loreIds: [
          setting.id,
          for (final l in slots.loreIds)
            if (l != setting.id) l,
        ],
      );
    }
    _g.deps.notify();
    return result;
  }

  /// Ignore: remember the name for this chat — it will not be proposed
  /// again until the chat is re-opened (session-reset law, Scene-Guest
  /// names).
  void ignoreMintedPlace() {
    final proposal = sceneMoves.mints.pending;
    if (proposal == null) return;
    sceneMoves.mints.ignore(proposal.name);
    _g.deps.notify();
  }
}
