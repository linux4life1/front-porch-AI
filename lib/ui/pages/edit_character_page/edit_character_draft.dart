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
import 'package:front_porch_ai/services/chat/chat.dart' show Pockets;
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Every field the character editor holds between open and Save: the text
/// controllers, the identity chips and the Realism/Needs seeds. Owned (and
/// disposed) by the page State; tabs mutate it and ask the page to rebuild.
class EditCharacterDraft {
  final TextEditingController nameController;
  final StyledTextController descriptionController;
  final StyledTextController personalityController;
  final StyledTextController scenarioController;
  final StyledTextController firstMessageController;
  final StyledTextController mesExampleController;
  final StyledTextController systemPromptController;
  final StyledTextController postHistoryController;

  List<LorebookEntry> loreEntries = [];
  List<String> selectedWorldNames = [];
  List<String> initialWorldNames = const [];
  List<StyledTextController> altGreetingControllers = [];
  List<GreetingRealismSeed?> altGreetingSeeds = [];
  List<String> tags = [];

  /// The character's own TTS voice id; '' means "follow the global
  /// Settings voice". Editable in the Details tab's Voice card.
  String ttsVoice = '';
  final tagController = TextEditingController();

  /// Long-term ambitions (Living Time §6), one per line. Identity — travels
  /// with the card; per-chat progress lives in the Journal.
  // Ambitions are a LIST, not newline-encoded text (see ChipListEditor).
  List<String> ambitions = const [];
  List<String> planLines = const [];
  String occupation = '';
  String occupationBrief = '';
  String hours = '';
  List<int>? workDays;
  String birthday = '';

  /// Likes & Dislikes and the 18+ pair — card-authored identity, same shape
  /// and same chip editor as [ambitions].
  List<String> likes = const [];
  List<String> dislikes = const [];
  List<String> intimateInto = const [];
  List<String> intimateNotInto = const [];

  /// Starting Pockets & Wardrobe, held as the chip text the user sees
  /// (`sundress (rain-soaked)`) rather than as parsed items. The card stores a
  /// map of `{name, state}`; [Pockets] owns both directions of that conversion
  /// so the editor never has to hold two representations at once.
  List<String> worn = const [];
  List<String> carrying = const [];
  final ValueNotifier<int> tokenNotifier = ValueNotifier<int>(0);

  // ── Realism Engine state ──
  bool realismEnabled = false;
  bool realismSettingsModified = false;
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
  bool realismPassageOfTime = true;
  bool realismChaosMode = false;
  bool realismNeedsSim = false;

  /// For a card that says nothing about Needs: the Porch Life value the
  /// switch opened on. Save keeps the card silent unless the switch moved
  /// off it. Null when the card made its own choice.
  bool? needsSimShownForSilent;
  bool realismPocketsEnabled = true;
  bool realismEnjoysLowHygiene = false;

  /// Read-and-write-back only — no editor writes this any more (Ambitions
  /// replaced the "Current Task / Quest" box). It is loaded from the card and
  /// saved straight back so editing anything else about an older character
  /// does not erase the starting quest their chats still import. The create
  /// flows dropped their copies because a NEW card has no task to preserve;
  /// this one is load-bearing.
  String realismCurrentTask = '';
  bool realismVerificationEnabled = false;
  int realismVerificationMaxReprocesses = 1;
  int realismVerificationStrictness = 3;
  bool realismNeedsDirectorAuthority = false;
  String needsPace = 'normal';
  List<String> needsOff = const [];

  // Per-need baseline values (0-100).
  int needsBaselineHunger = 80;
  int needsBaselineBladder = 80;
  int needsBaselineEnergy = 80;
  int needsBaselineSocial = 80;
  int needsBaselineFun = 80;
  int needsBaselineHygiene = 80;
  int needsBaselineComfort = 80;

  /// Seeds every field from [character]. A card with no lorebook gets an empty
  /// one attached here, and [loreEntries] is that same list.
  /// [porchLifeNeedsDefault] is asked only when the card says nothing about
  /// Needs (see [needsSimShownForSilent]).
  EditCharacterDraft(
    CharacterCard character, {
    required bool Function() porchLifeNeedsDefault,
  }) : nameController = TextEditingController(text: character.name),
       descriptionController = StyledTextController(
         text: character.description,
         preset: StyledTextPreset.macros,
       ),
       personalityController = StyledTextController(
         text: character.personality,
         preset: StyledTextPreset.macros,
       ),
       scenarioController = StyledTextController(
         text: character.scenario,
         preset: StyledTextPreset.macros,
       ),
       firstMessageController = StyledTextController(
         text: character.firstMessage,
         preset: StyledTextPreset.prose,
       ),
       mesExampleController = StyledTextController(
         text: character.mesExample,
         preset: StyledTextPreset.prose,
       ),
       systemPromptController = StyledTextController(
         text: character.systemPrompt,
         preset: StyledTextPreset.macros,
       ),
       postHistoryController = StyledTextController(
         text: character.postHistoryInstructions,
         preset: StyledTextPreset.macros,
       ) {
    if (character.lorebook != null) {
      loreEntries = List.from(character.lorebook!.entries);
    } else {
      character.lorebook = Lorebook(entries: []);
      loreEntries = character.lorebook!.entries;
    }

    selectedWorldNames = List.from(character.worldNames);
    // Snapshot for the save-time diff: only worlds ADDED in this edit get
    // pushed onto the character's existing chats.
    initialWorldNames = List.from(character.worldNames);

    altGreetingControllers = character.alternateGreetings
        .map(
          (g) => StyledTextController(text: g, preset: StyledTextPreset.prose),
        )
        .toList();
    altGreetingSeeds = alignGreetingSeeds(
      character.frontPorchExtensions?.greetingSeeds ?? const [],
      altGreetingControllers.length,
    );

    tags = List.from(character.tags);
    ttsVoice = character.ttsVoice ?? '';

    final ext = character.frontPorchExtensions;
    if (ext != null) {
      _seedRealism(ext, porchLifeNeedsDefault);
    } else {
      realismNeedsSim = needsSimShownForSilent = porchLifeNeedsDefault();
    }
    _seedIdentity(ext);

    // Listen for token count updates
    for (final c in [
      nameController,
      descriptionController,
      personalityController,
      scenarioController,
      firstMessageController,
      mesExampleController,
      systemPromptController,
      postHistoryController,
    ]) {
      c.addListener(updateTokenCount);
    }
    for (final c in altGreetingControllers) {
      c.addListener(updateTokenCount);
    }
    updateTokenCount();
    _start = fingerprint();
  }

  late final String _start;

  /// True once anything Save would write differs from what the editor opened
  /// with. Moving a field and moving it back is not an edit.
  bool get isDirty => fingerprint() != _start;

  String fingerprint() => jsonEncode([
    for (final c in [
      nameController,
      descriptionController,
      personalityController,
      scenarioController,
      firstMessageController,
      mesExampleController,
      systemPromptController,
      postHistoryController,
      ...altGreetingControllers,
    ])
      c.text,
    [for (final s in altGreetingSeeds) s?.toJson()],
    [for (final e in loreEntries) e.toJson()],
    selectedWorldNames,
    tags,
    ttsVoice,
    ambitions,
    planLines,
    occupation,
    occupationBrief,
    hours,
    workDays,
    birthday,
    likes,
    dislikes,
    intimateInto,
    intimateNotInto,
    worn,
    carrying,
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
    realismPassageOfTime,
    realismChaosMode,
    realismNeedsSim,
    realismPocketsEnabled,
    realismEnjoysLowHygiene,
    realismVerificationEnabled,
    realismVerificationMaxReprocesses,
    realismVerificationStrictness,
    realismNeedsDirectorAuthority,
    needsPace,
    needsOff,
    needsBaselineHunger,
    needsBaselineBladder,
    needsBaselineEnergy,
    needsBaselineSocial,
    needsBaselineFun,
    needsBaselineHygiene,
    needsBaselineComfort,
  ]);

  void _seedRealism(
    FrontPorchExtensions ext,
    bool Function() porchLifeNeedsDefault,
  ) {
    realismEnabled = ext.realismEnabled;
    realismTimeOfDay = ext.timeOfDay;
    realismDayCount = ext.dayCount;
    realismStoryStartDate = ext.storyStartDate;
    realismStoryStartTime = ext.storyStartTime;
    realismShortTermBond = ext.shortTermBond;
    realismLongTermBond = ext.longTermBond;
    realismTrustLevel = ext.trustLevel;
    realismEmotion = ext.characterEmotion;
    realismEmotionIntensity = ext.emotionIntensity;
    realismNsfwCooldown = ext.nsfwCooldownEnabled;
    realismPassageOfTime = ext.passageOfTimeEnabled;
    realismChaosMode = ext.chaosModeEnabled;
    if (ext.needsSimChoice == null) {
      realismNeedsSim = needsSimShownForSilent = porchLifeNeedsDefault();
    } else {
      realismNeedsSim = ext.needsSimChoice!;
    }
    realismPocketsEnabled = ext.pocketsEnabled;
    realismEnjoysLowHygiene = ext.enjoysLowHygiene;
    realismCurrentTask = ext.currentTask;
    realismVerificationEnabled = ext.realismVerificationEnabled;
    realismVerificationMaxReprocesses = ext.realismVerificationMaxReprocesses;
    realismVerificationStrictness = ext.realismVerificationStrictness;
    realismNeedsDirectorAuthority = ext.realismNeedsDirectorAuthority;
    needsPace = ext.needsPace;
    needsOff = List<String>.from(ext.needsOff);
    needsBaselineHunger = ext.needsBaselineHunger;
    needsBaselineBladder = ext.needsBaselineBladder;
    needsBaselineEnergy = ext.needsBaselineEnergy;
    needsBaselineSocial = ext.needsBaselineSocial;
    needsBaselineFun = ext.needsBaselineFun;
    needsBaselineHygiene = ext.needsBaselineHygiene;
    needsBaselineComfort = ext.needsBaselineComfort;
  }

  void _seedIdentity(FrontPorchExtensions? ext) {
    ambitions = List<String>.from(ext?.ambitions ?? const []);
    planLines = List<String>.from(ext?.planLines ?? const []);
    occupation = ext?.occupation ?? '';
    occupationBrief = ext?.occupationBrief ?? '';
    hours = ext?.hours ?? '';
    workDays = ext?.workDays;
    birthday = ext?.birthday ?? '';
    likes = List<String>.from(ext?.likes ?? const []);
    dislikes = List<String>.from(ext?.dislikes ?? const []);
    intimateInto = List<String>.from(ext?.intimateInto ?? const []);
    intimateNotInto = List<String>.from(ext?.intimateNotInto ?? const []);
    // Through Pockets.fromJson rather than a hand-rolled cast: it is the one
    // reader that already tolerates both entry shapes a card can carry (a bare
    // string, or {name, state}) and applies the same caps the runtime does.
    final startingPockets = Pockets.fromJson(ext?.inventory);
    worn = startingPockets.wornDisplay;
    carrying = startingPockets.carryingDisplay;
  }

  void updateTokenCount() {
    int totalChars =
        nameController.text.length +
        descriptionController.text.length +
        personalityController.text.length +
        scenarioController.text.length +
        firstMessageController.text.length +
        mesExampleController.text.length +
        systemPromptController.text.length +
        postHistoryController.text.length;
    for (final c in altGreetingControllers) {
      totalChars += c.text.length;
    }
    tokenNotifier.value = (totalChars / 4).ceil();
  }

  void addAltGreeting() {
    final c = StyledTextController(preset: StyledTextPreset.prose);
    c.addListener(updateTokenCount);
    altGreetingControllers.add(c);
    altGreetingSeeds.add(null);
  }

  void removeAltGreeting(int idx) {
    altGreetingControllers[idx].dispose();
    altGreetingControllers.removeAt(idx);
    if (idx < altGreetingSeeds.length) {
      altGreetingSeeds.removeAt(idx);
    }
  }

  void setAltGreetingSeed(int idx, GreetingRealismSeed? next) {
    while (altGreetingSeeds.length <= idx) {
      altGreetingSeeds.add(null);
    }
    altGreetingSeeds[idx] = next;
  }

  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    personalityController.dispose();
    scenarioController.dispose();
    firstMessageController.dispose();
    mesExampleController.dispose();
    systemPromptController.dispose();
    postHistoryController.dispose();
    for (final c in altGreetingControllers) {
      c.dispose();
    }
    tagController.dispose();
    tokenNotifier.dispose();
  }
}
