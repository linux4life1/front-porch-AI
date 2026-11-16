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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/group_member_start_overlay.dart';
import 'package:front_porch_ai/services/group_member_values.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// What the Edit group page holds while it is open: one controller or value
/// for every field Save writes, so the page can tell whether anything moved
/// and build the group to store. The fields are the 1:1 editor's, plus the
/// group-only turn rules and cast settings.
class EditGroupDraft {
  EditGroupDraft(GroupChat g)
    : name = TextEditingController(text: g.name),
      personality = TextEditingController(text: g.personality),
      scenario = TextEditingController(text: g.scenario),
      systemPrompt = TextEditingController(text: g.systemPrompt),
      postHistory = TextEditingController(text: g.postHistoryInstructions),
      firstMessage = TextEditingController(text: g.firstMessage),
      tagController = TextEditingController(),
      tags = List.of(g.tags),
      altGreetings = List.of(g.alternateGreetings),
      altGreetingSeeds = List.of(g.greetingSeeds),
      turnOrder = g.turnOrder,
      autoAdvance = g.autoAdvance,
      directorMode = g.directorMode,
      inheritCharacterLorebooks = g.inheritCharacterLorebooks,
      chaos = g.chaosModeEnabled,
      verification = g.realismVerificationEnabled,
      verificationStrictness = g.realismVerificationStrictness,
      verificationMaxReprocesses = g.realismVerificationMaxReprocesses,
      directorAuthority = g.needsDirectorAuthority,
      storyStartDate = g.storyStartDate,
      storyStartTime = g.storyStartTime,
      defaultMemberJson = g.defaultMemberRealismState,
      baselineJson = g.baselineRealismState,
      originalRawLorebook = g.groupLorebook {
    final scene = groupSceneOf(g);
    timeOfDay = scene.timeOfDay;
    dayCount = scene.dayCount;
    // The member ids' prompts and notes: controllers are made per member
    // once the roster is known ([member]).
    for (final e in g.characterSystemPrompts.entries) {
      prompts[e.key] = TextEditingController(text: e.value);
    }
    for (final e in g.characterAuthorNotes.entries) {
      notes[e.key] = TextEditingController(text: e.value.note);
      strengths[e.key] = e.value.strength;
    }
  }

  final TextEditingController name;
  final TextEditingController personality;
  final TextEditingController scenario;
  final TextEditingController systemPrompt;
  final TextEditingController postHistory;
  final TextEditingController firstMessage;
  final TextEditingController tagController;
  final List<String> tags;
  List<String> altGreetings;
  List<GreetingRealismSeed?> altGreetingSeeds;
  TurnOrder turnOrder;
  bool autoAdvance;
  bool directorMode;
  bool inheritCharacterLorebooks;
  bool chaos;
  bool verification;
  int verificationStrictness;
  int verificationMaxReprocesses;
  bool directorAuthority;
  late String timeOfDay;
  late int dayCount;
  String? storyStartDate;
  String? storyStartTime;

  /// The definition and baseline blobs: kept as stored, with the scene time
  /// and starting feelings the page edits written onto the definition.
  String defaultMemberJson;
  String baselineJson;
  GroupWorldChoice worldChoice = const GroupWorldChoice();
  GroupWorldChoice worldsAsLoaded = const GroupWorldChoice();
  final List<LorebookEntry> loreEntries = [];
  final String originalRawLorebook;
  bool bookUnreadable = false;

  /// Per member id: the group's system prompt, Author's Note and Strength.
  final Map<String, TextEditingController> prompts = {};
  final Map<String, TextEditingController> notes = {};
  final Map<String, int> strengths = {};

  TextEditingController promptOf(String mid) =>
      prompts.putIfAbsent(mid, TextEditingController.new);
  TextEditingController noteOf(String mid) =>
      notes.putIfAbsent(mid, TextEditingController.new);
  int strengthOf(String mid) => strengths[mid] ?? 4;

  /// Starting feelings, `{from: {to: score}}`, as the definition holds them.
  Map<String, Map<String, int>> get feelings =>
      startingFeelingsIn(defaultMemberJson);

  void setFeeling(String from, String to, int score) {
    defaultMemberJson = withStartingFeeling(
      defaultMemberJson,
      from: from,
      to: to,
      score: score,
    );
  }

  void setScene({String? time, int? day}) {
    if (time != null) timeOfDay = time;
    if (day != null) dayCount = day;
    defaultMemberJson = withGroupSceneTime(
      defaultMemberJson,
      timeOfDay: timeOfDay,
      dayCount: dayCount,
    );
  }

  /// The group's values for [mid] as the page holds them now, for the
  /// member's editor.
  GroupMemberValues valuesOf(String mid, GroupChat stored) {
    final probe = toGroup(stored, worldFields: null, loreJson: null);
    return groupMemberValuesOf(probe, mid);
  }

  /// Takes [values] a member's editor saved: they become the page's, saved
  /// with its Save.
  void takeValues(String mid, GroupMemberValues values) {
    promptOf(mid).text = values.systemPrompt;
    noteOf(mid).text = values.note;
    strengths[mid] = values.strength;
    for (final e in values.feelings.entries) {
      if ((feelings[mid]?[e.key]) != e.value) setFeeling(mid, e.key, e.value);
    }
  }

  /// Everything Save writes, so leaving can tell whether anything changed.
  /// Empty per-character prompts and notes are dropped, as Save drops them.
  String fingerprint() => jsonEncode([
    name.text.trim(),
    personality.text.trim(),
    scenario.text.trim(),
    systemPrompt.text.trim(),
    postHistory.text.trim(),
    firstMessage.text.trim(),
    tags,
    altGreetings,
    [for (final s in altGreetingSeeds) s?.toJson()],
    turnOrder.name,
    autoAdvance,
    directorMode,
    worldChoice.settingId,
    worldChoice.loreIds,
    inheritCharacterLorebooks,
    chaos,
    verification,
    verificationStrictness,
    verificationMaxReprocesses,
    directorAuthority,
    storyStartDate,
    storyStartTime,
    {
      for (final e in prompts.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    },
    {
      for (final e in notes.entries)
        if (e.value.text.trim().isNotEmpty)
          e.key: [e.value.text.trim(), strengthOf(e.key)],
    },
    [for (final e in loreEntries) e.toJson()],
    defaultMemberJson,
    baselineJson,
  ]);

  /// The group to store: [stored] with this page's fields on it. [worldFields]
  /// and [loreJson] are null while only a copy for reading is wanted.
  GroupChat toGroup(
    GroupChat stored, {
    required ({List<String> worldIds, List<String>? loreWorldIds})? worldFields,
    required String? loreJson,
  }) {
    final notesOut = <String, MemberAuthorNote>{
      for (final e in notes.entries)
        if (e.value.text.trim().isNotEmpty)
          e.key: MemberAuthorNote(e.value.text.trim(), strengthOf(e.key)),
    };
    return GroupChat(
      id: stored.id,
      // Preserve the portable stable id (in-place Stoop updates).
      stableId: stored.stableId,
      name: name.text.trim().isEmpty ? stored.name : name.text.trim(),
      turnOrder: turnOrder,
      autoAdvance: autoAdvance,
      directorMode: directorMode,
      firstMessage: firstMessage.text.trim(),
      alternateGreetings: List.of(altGreetings),
      greetingSeeds: List.of(altGreetingSeeds),
      scenario: scenario.text.trim(),
      systemPrompt: systemPrompt.text.trim(),
      defaultMemberRealismState: withGroupOpeningAlts(
        defaultMemberJson,
        alternateGreetings: altGreetings,
        greetingSeeds: altGreetingSeeds,
      ),
      baselineRealismState: baselineJson,
      characterSystemPrompts: {
        for (final e in prompts.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
      },
      characterAuthorNotes: notesOut,
      worldIds: worldFields?.worldIds ?? stored.worldIds,
      loreWorldIds: worldFields == null
          ? stored.loreWorldIds
          : worldFields.loreWorldIds,
      groupLorebook: loreJson ?? stored.groupLorebook,
      inheritCharacterLorebooks: inheritCharacterLorebooks,
      chaosModeEnabled: chaos,
      chaosNsfwEnabled: stored.chaosNsfwEnabled,
      personality: personality.text.trim(),
      postHistoryInstructions: postHistory.text.trim(),
      mesExample: stored.mesExample,
      tags: List.of(tags),
      storyStartDate: storyStartDate,
      storyStartTime: storyStartTime,
      realismVerificationEnabled: verification,
      realismVerificationStrictness: verificationStrictness,
      realismVerificationMaxReprocesses: verificationMaxReprocesses,
      needsDirectorAuthority: directorAuthority,
    );
  }

  void dispose() {
    for (final c in [
      name,
      personality,
      scenario,
      systemPrompt,
      postHistory,
      firstMessage,
      tagController,
      ...prompts.values,
      ...notes.values,
    ]) {
      c.dispose();
    }
  }
}
