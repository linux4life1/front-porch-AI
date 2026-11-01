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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/place_factory.dart';
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
