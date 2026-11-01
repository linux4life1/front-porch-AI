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

import 'package:front_porch_ai/database/database.dart' show GrowthRingData;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/place_factory.dart';
import 'package:front_porch_ai/services/chat/scene/scene_backdrop.dart';
import 'package:front_porch_ai/services/chat_service.dart';

/// The group lore in play (bodies in [ChatLore]).
extension ChatServiceRealismLore on ChatService {
  /// The post-group-filter active entries of the open group, deduplicated
  /// by content (the sidebar's "in play" list). Empty outside a group.
  List<LorebookEntry> getActiveGroupLoreEntries() =>
      realism.lore.activeGroupLoreEntries();

  /// True when the active group's stored lorebook could not be read, so none
  /// of its entries are in play.
  bool get groupLorebookUnreadable => realism.lore.groupLorebookUnreadable;

  /// The live group-lorebook entries (the instances the scanner marks), for
  /// the phone's lore list.
  List<LorebookEntry> get groupLorebookEntries =>
      realism.lore.groupLorebookEntries;
}

/// Living Worlds: the Setting and Lore slots, climate, the suggested move
/// and the minted place (bodies in [ChatPlaces]).
extension ChatServiceRealismPlaces on ChatService {
  Future<void> setChatWorldIds(List<String> worldIds) =>
      realism.places.setChatWorldIds(worldIds);

  /// Setting + Lore writer (Story Tools / web). Empty both = decided empty.
  Future<void> setChatPlaceSlots({
    String? primaryId,
    List<String> loreIds = const [],
  }) =>
      realism.places.setChatPlaceSlots(primaryId: primaryId, loreIds: loreIds);

  /// Insert a mid-chat climate changeover from the story day onward.
  Future<void> setChatClimate(Biome biome) =>
      realism.places.setChatClimate(biome);

  /// The judge's arrival answer: flags the move for the confirm dialog.
  void flagSuggestedPlaceMove(String id) =>
      realism.places.flagSuggestedPlaceMove(id);

  /// The move the clock judge suggested and the author has not answered
  /// yet — the chat page shows the confirm dialog while this is non-null.
  PendingPlaceMove? get pendingPlaceMove => realism.places.sceneMoves.pending;

  /// Move: the manual path, the old Setting demoted to the top of Lore.
  Future<void> acceptPlaceMove() => realism.places.acceptPlaceMove();

  /// Stay: dismiss the offer and remember the decline for this Setting.
  void declinePlaceMove() => realism.places.declinePlaceMove();

  /// A proposed NEW place the judge heard named in the narration,
  /// awaiting the tap. Nothing exists in the library until then.
  ProposedPlace? get pendingPlaceMint =>
      realism.places.sceneMoves.mints.pending;

  void flagSuggestedPlaceMint(String name, String descriptor) =>
      realism.places.flagSuggestedPlaceMint(name, descriptor);

  /// Add (and optionally move the scene into) the minted place.
  Future<PlaceMintResult> acceptMintedPlace({required bool alsoMove}) =>
      realism.places.acceptMintedPlace(alsoMove: alsoMove);

  /// Ignore: remember the name for this chat until it is re-opened.
  void ignoreMintedPlace() => realism.places.ignoreMintedPlace();

  /// The segment BEFORE the current one (yesterday's night for a morning),
  /// or null on day 1 mornings and whenever weather is off. Reads the class
  /// [currentSegmentWeather] first, as the body always did.
  SegmentWeather? get previousSegmentWeather {
    final now = currentSegmentWeather;
    return now == null ? null : realism.weather.previousSegmentBefore(now);
  }
}

/// The sidebar's tool-calling pill and the web facade (bodies in
/// [EvalTransport]).
extension ChatServiceRealismTools on ChatService {
  /// The current model's tool-calling verdict.
  ToolCallSupport get toolCallSupport => realism.transport.toolCallSupport;
  bool get isTestingToolSupport => realism.transport.isTestingToolSupport;

  /// Re-probe the current backend+model's tool support (pill tap).
  Future<void> testToolCalling() => realism.transport.testToolCalling();

  bool get toolCallingPaused => realism.transport.toolCallingPaused;

  /// Same object for chat-state and POST /api/chat/tool-test (additive keys).
  Map<String, dynamic> get toolSupportJson => realism.transport.toolSupportJson;
}

/// A group member's creation baseline (body in [RealismRestores]).
extension ChatServiceRealismSeeds on ChatService {
  /// The immutable creation-time baseline realism values for a group
  /// member: affection (bond), trust, emotion, timeOfDay, dayCount.
  Map<String, dynamic> getBaselineSeedForGroupCharacter(
    CharacterCard character,
  ) => realism.restores.baselineSeedFor(character);
}

/// The story day, the backdrop and the Setting's world (bodies on the
/// graph's clock and places).
extension ChatServiceRealismLiving on ChatService {
  /// The story clock's current day, for consumers outside the service — the
  /// Pockets sidebar rows and the web facade filter set-aside clothing by it
  /// (yesterday's outfit must not survive the story's morning). One
  /// forwarder rather than exposing TimeService whole.
  ///
  /// MORNING-anchored since 2026-08-15 (maintainer-approved): every consumer
  /// of this accessor is a set-aside surface, and the calendar day flipping
  /// at 00:00 deleted the outfit mid-scene the moment a night ran past
  /// midnight — the docs always promised "the next story morning". Story
  /// stamps (journal cards, calendars) keep the calendar `dayCount`.
  int get storyDayCount => realism.time.morningAnchoredDayCount;

  /// The picture behind the chat: the Setting place's cover, or the nearest
  /// ancestor's, read live from the Setting's chain so a scene move paints
  /// the new place at once (`sceneBackdropOf`). Null when the chat has no
  /// Setting or no place in its chain has a picture, and the chat keeps the
  /// background it chose. Independent of the Ambient scene level: the
  /// picture is the ground the weather paints on, not part of the weather.
  SceneBackdrop? get sceneBackdrop {
    final primaryId = realism.places.slots.primaryId;
    if (primaryId == null) return null;
    return sceneBackdropOf(realism.deps.services.worlds.chainFor(primaryId));
  }

  /// The top-level world holding the chat's Setting, for a story made from
  /// this chat. The story's `worldName` names the world, not the place
  /// (stories-in-worlds §3.1), and `chainFor` is leaf-first, so this is the
  /// chain's last entry. Null when the chat has no Setting or its place is
  /// gone from the library.
  String? get chatSettingWorldName {
    final primaryId = realism.places.slots.primaryId;
    if (primaryId == null) return null;
    return realism.deps.services.worlds
        .chainFor(primaryId)
        .lastOrNull
        ?.name
        .trim();
  }
}

/// The group-realism test hooks (Reprocess Needs is on the edits bridge;
/// the post-gen abort latch is in chat_service_generation_postgen).
/// Public extension members: no fake overrides them.
extension ChatServiceRealismDoors on ChatService {
  /// Test-only: pin the group speaker the same way `_generateResponse` does
  /// ([GroupRealismStore.turnSpeakerId]). Do not assign `_session.activeCharacter`.
  @visibleForTesting
  void debugPinTurnSpeakerForRealism(String? charId) {
    realism.groups.turnSpeakerId = charId;
  }

  /// Test-only: set the glance bit on a group member slot.
  @visibleForTesting
  void debugSetGroupWithUser(String charId, bool? v) {
    realism.groups.memberForWrite(charId).withUser = v;
  }

  /// Test-only: live position injection through the wired BehavioralInjection.
  /// Does not stub `getOccupationBrief`.
  @visibleForTesting
  String debugBuildPositionInjection() =>
      realism.behavioralInjection.buildPositionInjection();

  /// Test-only: first-speaker [RealismDance.loadIntoScalars] without a turn.
  @visibleForTesting
  void debugReloadFirstGroupSpeakerScalars() {
    if (groupCharacters.isEmpty) return;
    realism.dance.loadIntoScalars(characterIdFor(groupCharacters.first));
  }

  /// Test-only: emotion sitting in a group member slot (not live scalars).
  @visibleForTesting
  String debugGroupSlotEmotion(String charId) =>
      realism.groups.members[charId]?.emotion ?? '';

  /// Test-only: stored needs for a group member. Empty when the slot has
  /// never carried a vector (does not invent [NeedsSimulation.needDefaults]).
  @visibleForTesting
  Map<String, int> debugGroupNeeds(String charId) =>
      realism.groups.needsOf(charId);

  /// Test-only: seed a member slot so a later soft turn can prove it does
  /// not leak this member's Needs / bond into the guest prompt, or so the
  /// member card can show that member's own mood, Lust and recovery.
  @visibleForTesting
  void debugSeedGroupSpeakerState(
    String charId, {
    Map<String, int>? needs,
    int? longTermTier,
    String? emotion,
    int? arousal,
    Refractory? refractory,
  }) {
    final groups = realism.groups;
    if (needs != null) groups.setNeeds(charId, needs);
    if (longTermTier != null) {
      groups.memberForWrite(charId).longTermTier = longTermTier;
    }
    if (emotion != null) groups.memberForWrite(charId).emotion = emotion;
    if (arousal != null) groups.memberForWrite(charId).arousal = arousal;
    if (refractory != null) {
      groups.memberForWrite(charId).refractory = refractory;
    }
  }
}

/// Pockets & Wardrobe and Growth Rings doors for the sidebar, the web facade
/// and the other parts (bodies in [PocketsLedger] and [GrowthDesk]). Public
/// extension members: no fake overrides them.
extension ChatServiceMemoryDoors on ChatService {
  /// Combined Pockets gate: Porch Life global AND this character's card flag.
  /// The global is read through the class member first, as the extension
  /// body always did: the golden FakeChatService answers it (false) and the
  /// sidebar must not reach the ledger on a fake.
  bool pocketsEnabledFor(String characterId) =>
      pocketsFeatureEnabled &&
      realism.pocketsLedger.pocketsEnabledFor(characterId);

  /// Put one item into a character's kit by hand (gift, conjured, or a
  /// record correction). The gate is read here first, as the extension body
  /// did, so a fake with Pockets off returns before reaching the ledger.
  Future<void> addPocketItem(
    String characterId, {
    required PocketSection section,
    required String name,
    bool gift = false,
    bool correction = false,
  }) async {
    if (!pocketsEnabledFor(characterId)) return;
    return realism.pocketsLedger.addPocketItem(
      characterId,
      section: section,
      name: name,
      gift: gift,
      correction: correction,
    );
  }

  /// Strike one item off by hand; also retires its item-memory card. No
  /// record (the class [pocketsFor], which fakes answer) returns first.
  Future<void> removePocketItem(
    String characterId, {
    required PocketSection section,
    required int index,
  }) async {
    if (pocketsFor(characterId) == null) return;
    return realism.pocketsLedger.removePocketItem(
      characterId,
      section: section,
      index: index,
    );
  }

  /// Persist [p] back to wherever that character's record lives.
  void setPocketsFor(String characterId, Pockets p) =>
      realism.pocketsLedger.setPocketsFor(characterId, p);

  /// What [c]'s card says they START a chat with.
  Pockets startingPocketsFor(CharacterCard c) =>
      PocketsLedger.startingPocketsFor(c);

  /// Seed every speaker's card kit unless the chat already has one. Every
  /// conversation entry path calls this.
  void seedPocketsFromCards() {
    if (!pocketsFeatureEnabled) return;
    realism.pocketsLedger.seedPocketsFromCards();
  }

  /// Review parking door for the sidebar banner + review dialog.
  GrowthReview get growthReview => realism.growthDesk.growthReview;

  /// Every ring for one owner in the current chat (active first, then past).
  List<GrowthRingData> growthRingsForOwner(String ownerId) =>
      realism.growthDesk.growthRingsForOwner(ownerId);

  /// Active-ring count for badges (group member cards, sidebar).
  int growthRingCountFor(CharacterCard card) =>
      realism.growthDesk.growthRingCountFor(card);

  /// Whether an owner still has an undistilled legacy evolved blob.
  bool hasLegacyGrowthBlobFor(String ownerId) =>
      realism.growthDesk.hasLegacyGrowthBlobFor(ownerId);

  /// Manually plant a pinned, user-authored ring.
  Future<void> plantGrowthRingFor(
    String ownerId,
    String text, {
    String category = 'trait',
  }) =>
      realism.growthDesk.plantGrowthRingFor(ownerId, text, category: category);

  /// Edit a ring's wording/category in place.
  Future<void> editGrowthRing(
    GrowthRingData ring, {
    required String text,
    String? category,
  }) => realism.growthDesk.editGrowthRing(ring, text: text, category: category);

  Future<void> setGrowthRingPinned(String ringId, bool pinned) =>
      realism.growthDesk.setGrowthRingPinned(ringId, pinned);

  /// Demote a ring to Past growth (reversible).
  Future<void> retireGrowthRing(String ringId) =>
      realism.growthDesk.retireGrowthRing(ringId);

  /// Bring a Past ring back into the active set.
  Future<void> unretireGrowthRing(GrowthRingData ring) =>
      realism.growthDesk.unretireGrowthRing(ring);

  /// Hard-delete one ring.
  Future<void> deleteGrowthRing(String ringId) =>
      realism.growthDesk.deleteGrowthRing(ringId);

  /// Reset one owner's growth in this chat (rings and legacy blob).
  Future<void> resetGrowthFor(String ownerId) =>
      realism.growthDesk.resetGrowthFor(ownerId);

  /// Manual "Check now". Force-runs even on an empty window.
  Future<void> forceGrowthPass() => realism.growthDesk.forceGrowthPass();
}
