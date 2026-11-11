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

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Everything the group editor's Save writes to the group's row, as the page
/// holds it: the one place that says what "changed" means (the leave guard
/// compares [fingerprint]s) and how the row is built from it.
class EditGroupValues {
  EditGroupValues({
    required this.name,
    required this.firstMessage,
    required this.altGreetings,
    required this.altGreetingSeeds,
    required this.scenario,
    required this.systemPrompt,
    required this.turnOrder,
    required this.autoAdvance,
    required this.directorMode,
    required this.worldChoice,
    required this.inheritCharacterLorebooks,
    required this.charPrompts,
    required this.loreEntries,
    required this.defaultMemberRealismState,
    required this.baselineRealismState,
    required this.memberExtensions,
  });

  final String name;
  final String firstMessage;
  final List<String> altGreetings;
  final List<GreetingRealismSeed?> altGreetingSeeds;
  final String scenario;
  final String systemPrompt;
  final TurnOrder turnOrder;
  final bool autoAdvance;
  final bool directorMode;
  final GroupWorldChoice worldChoice;
  final bool inheritCharacterLorebooks;

  /// Non-empty per-member prompts only, as Save drops the empty ones.
  final Map<String, String> charPrompts;
  final List<LorebookEntry> loreEntries;
  final String defaultMemberRealismState;
  final String baselineRealismState;

  /// Each member's extensions as JSON (their defaults for new chats), keyed
  /// by member id.
  final Map<String, String> memberExtensions;

  /// Changes whenever anything Save writes changes.
  String get fingerprint => jsonEncode([
    name,
    firstMessage,
    altGreetings,
    [for (final s in altGreetingSeeds) s?.toJson()],
    scenario,
    systemPrompt,
    turnOrder.name,
    autoAdvance,
    directorMode,
    worldChoice.settingId,
    worldChoice.loreIds,
    inheritCharacterLorebooks,
    charPrompts,
    [for (final e in loreEntries) e.toJson()],
    defaultMemberRealismState,
    baselineRealismState,
    memberExtensions,
  ]);

  /// The row Save writes, over [base] (which keeps its portable id and the
  /// chaos flags, neither of which this page edits). [loreJson] is the
  /// lorebook to store and [worlds] the world fields.
  GroupChat toGroup(
    GroupChat base, {
    required String loreJson,
    required ({List<String> worldIds, List<String>? loreWorldIds}) worlds,
  }) => GroupChat(
    id: base.id,
    stableId: base.stableId,
    name: name.isEmpty ? base.name : name,
    turnOrder: turnOrder,
    autoAdvance: autoAdvance,
    directorMode: directorMode,
    firstMessage: firstMessage,
    alternateGreetings: List.of(altGreetings),
    greetingSeeds: List.of(altGreetingSeeds),
    scenario: scenario,
    systemPrompt: systemPrompt,
    defaultMemberRealismState: withGroupOpeningAlts(
      defaultMemberRealismState,
      alternateGreetings: altGreetings,
      greetingSeeds: altGreetingSeeds,
    ),
    baselineRealismState: baselineRealismState,
    characterSystemPrompts: Map.of(charPrompts),
    worldIds: worlds.worldIds,
    loreWorldIds: worlds.loreWorldIds,
    groupLorebook: loreJson,
    inheritCharacterLorebooks: inheritCharacterLorebooks,
    chaosModeEnabled: base.chaosModeEnabled,
    chaosNsfwEnabled: base.chaosNsfwEnabled,
  );
}

/// The group's lorebook as the editor holds it. A stored book that cannot be
/// read is kept as stored ([raw]) unless the user, asked on Save, replaces it.
class EditGroupLorebook {
  EditGroupLorebook(this.raw) {
    try {
      final book = parseGroupLorebookJson(raw);
      if (book != null) entries.addAll(book.entries);
    } catch (e) {
      debugPrint('[EditGroup] group lorebook could not be read: $e');
      unreadable = true;
    }
  }

  final String raw;
  final List<LorebookEntry> entries = [];
  bool unreadable = false;

  /// What Save stores: the stored text when [keepRaw], else the entries.
  String toSave({required bool keepRaw}) =>
      keepRaw ? raw : jsonEncode(Lorebook(entries: List.of(entries)).toJson());
}
