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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Everything the manual creator's steps write: text controllers, tag and
/// lorebook lists, and the Porch Life / Realism / Needs seeds. Owned and
/// disposed by the page State; steps mutate it and ask the page to rebuild.
class CreateCharacterDraft {
  CreateCharacterDraft() {
    // Listen to all text controllers for token counting
    for (final c in allControllers) {
      c.addListener(updateTokenEstimate);
    }
    _blank = fingerprint();
  }

  late String _blank;

  /// True once the wizard holds anything a blank one does not (and [reset]
  /// makes it blank again).
  bool get hasContent => fingerprint() != _blank;

  String fingerprint() => jsonEncode([
    for (final c in allControllers) c.text,
    [for (final s in altGreetingSeeds) s?.toJson()],
    [for (final e in lorebookEntries) e.toJson()],
    tags,
    realismEnabled,
    realismTimeOfDay,
    realismDayCount,
    realismStoryStartDate,
    realismStoryStartTime,
    realismShortTermBond,
    realismLongTermBond,
    realismTrustLevel,
    realismEmotion,
    realismEmotionIntensity,
    realismNsfwCooldown,
    realismChaosMode,
    realismAfterglow,
    realismNeedsSim,
    realismPocketsEnabled,
    realismEnjoysLowHygiene,
    realismAmbitions,
    realismPlanLines,
    realismOccupation,
    realismOccupationBrief,
    realismBirthday,
    realismHours,
    realismWorkDays,
    realismLikes,
    realismDislikes,
    realismIntimateInto,
    realismIntimateNotInto,
    realismRecovery.toJson(),
    realismWorn,
    realismCarrying,
    realismVerificationEnabled,
    realismVerificationMaxReprocesses,
    realismVerificationStrictness,
    realismNeedsDirectorAuthority,
    needsBaselineHunger,
    needsBaselineBladder,
    needsBaselineEnergy,
    needsBaselineSocial,
    needsBaselineFun,
    needsBaselineHygiene,
    needsBaselineComfort,
    needsPace,
    needsOff,
  ]);

  bool _disposed = false;

  // ── Identity (Step 0) ──
  final nameController = TextEditingController();
  final List<String> tags = [];
  final tagController = TextEditingController();

  // ── Personality (Step 1) ──
  final descriptionController = StyledTextController(
    preset: StyledTextPreset.macros,
  );
  final personalityController = StyledTextController(
    preset: StyledTextPreset.macros,
  );
  final scenarioController = StyledTextController(
    preset: StyledTextPreset.macros,
  );
  final systemPromptController = StyledTextController(
    preset: StyledTextPreset.macros,
  );
  final postHistoryController = StyledTextController(
    preset: StyledTextPreset.macros,
  );

  // ── Dialogue (Step 2) ──
  final firstMessageController = StyledTextController(
    preset: StyledTextPreset.prose,
  );
  final exampleDialogueController = StyledTextController(
    preset: StyledTextPreset.prose,
  );
  final List<StyledTextController> altGreetingControllers = [];
  final List<GreetingRealismSeed?> altGreetingSeeds = [];

  // ── Lorebook (Step 3) ──
  final List<LorebookEntry> lorebookEntries = [];

  // ── Realism Engine (Step 4) ──
  bool realismEnabled = false;
  String realismTimeOfDay = 'morning';
  int realismDayCount = 1;
  // Story Calendar authoring (story-calendar.md §3a): null start date =
  // "the day the chat starts"; null time = period default.
  String? realismStoryStartDate;
  String? realismStoryStartTime;
  int realismShortTermBond = 0;
  int realismLongTermBond = 0;
  int realismTrustLevel = 0;
  String realismEmotion = '';
  String realismEmotionIntensity = 'mild';
  bool realismNsfwCooldown = false;
  bool realismChaosMode = false;

  /// How new chats with this character start Afterglow.
  bool realismAfterglow = true;
  // AND-gated at chat start (card && Porch Life global). Default true so
  // a new card does not silently veto Needs — the form used to hide this
  // toggle unless the engine was on, so every manual create baked false.
  bool realismNeedsSim = true;
  bool realismPocketsEnabled = true;
  bool realismEnjoysLowHygiene = false;

  /// Long-term ambitions (approved sketch §4) — a list, not newline text.
  List<String> realismAmbitions = const [];
  List<String> realismPlanLines = const [];
  String realismOccupation = '';
  String realismOccupationBrief = '';
  String realismBirthday = '';
  String realismHours = '';
  List<int>? realismWorkDays;
  List<String> realismLikes = const [];
  List<String> realismDislikes = const [];
  List<String> realismIntimateInto = const [];
  List<String> realismIntimateNotInto = const [];

  /// Recovery profile authored on the Realism step (recovery overhaul PR 2).
  /// `auto` — the judge and the (here unset) structured sex — is the default.
  RecoveryProfile realismRecovery = const RecoveryProfile();

  /// Starting Pockets & Wardrobe as chip text (`sundress (rain-soaked)`).
  /// `Pockets` owns the conversion to and from the card's `{name, state}` map.
  List<String> realismWorn = const [];
  List<String> realismCarrying = const [];
  bool realismVerificationEnabled = false;
  int realismVerificationMaxReprocesses = 1;
  int realismVerificationStrictness = 3;
  bool realismNeedsDirectorAuthority = false;

  // ── Needs Simulation baselines (0-100) ──
  int needsBaselineHunger = 80;
  int needsBaselineBladder = 80;
  int needsBaselineEnergy = 80;
  int needsBaselineSocial = 80;
  int needsBaselineFun = 80;
  int needsBaselineHygiene = 80;
  int needsBaselineComfort = 80;
  String needsPace = 'normal';
  List<String> needsOff = const [];

  /// Picture for the first save (a persona's, when seeded from one);
  /// null writes the placeholder the Portrait step replaces.
  String? portraitSourcePath;

  /// Start from a persona: name, description, birthday and picture.
  void applyPersonaSeed(PersonaCharacterSeed seed) {
    nameController.text = seed.name;
    descriptionController.text = seed.description;
    personalityController.text = seed.personality;
    realismBirthday = seed.birthday;
    portraitSourcePath = seed.portraitPath;
    updateTokenEstimate();
    // The persona is where this draft starts, not an edit.
    _blank = fingerprint();
  }

  // ── Token counter ──
  final ValueNotifier<int> tokenNotifier = ValueNotifier<int>(0);

  List<TextEditingController> get allControllers => [
    nameController,
    descriptionController,
    personalityController,
    scenarioController,
    systemPromptController,
    postHistoryController,
    firstMessageController,
    exampleDialogueController,
    ...altGreetingControllers,
  ];

  void updateTokenEstimate() {
    int total = 0;
    for (final c in allControllers) {
      // Rough estimate: ~4 chars per token
      total += (c.text.length / 4).ceil();
    }
    // Add lorebook entries
    for (final entry in lorebookEntries) {
      total +=
          ((entry.name.length + entry.key.length + entry.content.length) / 4)
              .ceil();
    }
    if (!_disposed) {
      tokenNotifier.value = total;
    }
  }

  void addAltGreeting() {
    final ctrl = StyledTextController(preset: StyledTextPreset.prose);
    ctrl.addListener(updateTokenEstimate);
    altGreetingControllers.add(ctrl);
    altGreetingSeeds.add(null);
  }

  void removeAltGreeting(int idx) {
    altGreetingControllers[idx].dispose();
    altGreetingControllers.removeAt(idx);
    if (idx < altGreetingSeeds.length) {
      altGreetingSeeds.removeAt(idx);
    }
  }

  GreetingRealismSeed? altGreetingSeedAt(int idx) =>
      idx < altGreetingSeeds.length ? altGreetingSeeds[idx] : null;

  void setAltGreetingSeed(int idx, GreetingRealismSeed? next) {
    while (altGreetingSeeds.length <= idx) {
      altGreetingSeeds.add(null);
    }
    altGreetingSeeds[idx] = next;
  }

  /// Back to a blank wizard after "Done".
  void reset() {
    nameController.clear();
    descriptionController.clear();
    personalityController.clear();
    scenarioController.clear();
    firstMessageController.clear();
    exampleDialogueController.clear();
    systemPromptController.clear();
    postHistoryController.clear();
    for (final c in altGreetingControllers) {
      c.dispose();
    }
    altGreetingControllers.clear();
    altGreetingSeeds.clear();
    lorebookEntries.clear();
    tags.clear();
    realismEnabled = false;
    realismTimeOfDay = 'morning';
    realismDayCount = 1;
    realismStoryStartDate = null;
    realismStoryStartTime = null;
    realismShortTermBond = 0;
    realismLongTermBond = 0;
    realismTrustLevel = 0;
    realismEmotion = '';
    realismEmotionIntensity = 'mild';
    realismNsfwCooldown = false;
    realismChaosMode = false;
    realismAfterglow = true;
    realismNeedsSim = true;
    realismPocketsEnabled = true;
    realismEnjoysLowHygiene = false;
    realismAmbitions = const [];
    realismPlanLines = const [];
    realismOccupation = '';
    realismOccupationBrief = '';
    realismBirthday = '';
    realismHours = '';
    realismWorkDays = null;
    realismLikes = const [];
    realismDislikes = const [];
    realismIntimateInto = const [];
    realismIntimateNotInto = const [];
    realismRecovery = const RecoveryProfile();
    realismWorn = const [];
    realismCarrying = const [];
    realismVerificationEnabled = false;
    realismVerificationMaxReprocesses = 1;
    realismVerificationStrictness = 3;
    realismNeedsDirectorAuthority = false;
    needsBaselineHunger = 80;
    needsBaselineBladder = 80;
    needsBaselineEnergy = 80;
    needsBaselineSocial = 80;
    needsBaselineFun = 80;
    needsBaselineHygiene = 80;
    needsBaselineComfort = 80;
    needsPace = 'normal';
    needsOff = const [];
    portraitSourcePath = null;
    tokenNotifier.value = 0;
  }

  void dispose() {
    _disposed = true;
    nameController.dispose();
    tagController.dispose();
    descriptionController.dispose();
    personalityController.dispose();
    scenarioController.dispose();
    systemPromptController.dispose();
    postHistoryController.dispose();
    firstMessageController.dispose();
    exampleDialogueController.dispose();
    for (final c in altGreetingControllers) {
      c.dispose();
    }
    tokenNotifier.dispose();
  }
}
