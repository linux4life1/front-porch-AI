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

import 'package:flutter/widgets.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/services/group_opening_generator.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'group_wizard_steps.dart';

/// Everything the Create Group wizard edits: roster, prompts, lore, realism
/// seeds, and the current step. The page rebuilds on every
/// [notifyListeners]; mutations that never rebuilt the page do not notify.
class GroupWizardDraft extends ChangeNotifier {
  GroupWizardDraft() {
    nameController.addListener(updateEstimates);
    scenarioController.addListener(updateEstimates);
    firstMessageController.addListener(updateEstimates);
    _blank = fingerprint();
  }

  bool _disposed = false;
  late final String _blank;

  /// True once the wizard holds anything a fresh one does not. The step and
  /// the generating flags are where the user is, not what they made.
  bool get hasContent => fingerprint() != _blank;

  String fingerprint() => jsonEncode([
    [for (final m in members) stableId(m)],
    nameController.text,
    turnOrder.name,
    autoAdvance,
    directorMode,
    scenarioController.text,
    firstMessageController.text,
    altGreetings,
    [for (final s in altGreetingSeeds) s?.toJson()],
    {
      for (final e in characterSystemPrompts.entries)
        if (e.value.text.isNotEmpty) e.key: e.value.text,
    },
    characterVoices,
    [for (final e in groupLoreEntries) e.toJson()],
    worldChoice.settingId,
    worldChoice.loreIds,
    inheritCharacterLorebooks,
    realismEnabled,
    memberRealismSeeds,
    chaosModeEnabled,
    chaosNsfwEnabled,
    needsSimEnabled,
    afterglowEnabled,
    memberNeedsBaselines,
    globalTimeOfDay,
    globalDayCount,
    globalStoryStartDate,
    globalStoryStartTime,
  ], toEncodable: (o) => o.toString());

  /// One of [GroupWizardSteps].
  int currentStep = GroupWizardSteps.members;

  // ── Core State ─────────────────────────────────────────────────────
  final List<CharacterCard> members = [];

  // Identity
  final nameController = TextEditingController();

  /// The member-list name last put in [nameController]. While the box still
  /// holds it (or is empty) the name follows the roster; once the user types
  /// something else, it is theirs.
  String _autoGroupName = '';

  // Behavior
  TurnOrder turnOrder = TurnOrder.roundRobin;
  bool autoAdvance = false;
  bool directorMode = false;

  // Opening
  final scenarioController = StyledTextController(
    preset: StyledTextPreset.prose,
  );
  final firstMessageController = StyledTextController(
    preset: StyledTextPreset.prose,
  );
  List<String> altGreetings = [];
  List<GreetingRealismSeed?> altGreetingSeeds = [];
  bool isGeneratingScenario = false;
  bool isGeneratingFirst = false;

  // Prompts
  final Map<String, TextEditingController> characterSystemPrompts =
      {}; // charId -> prompt

  /// Members step Voice picks, charId → a voice id, or '' for "Use the global
  /// voice". A member with no entry keeps the card's own voice.
  final Map<String, String> characterVoices = {};

  // Lore & Worlds
  final List<LorebookEntry> groupLoreEntries = [];

  /// Where new chats meet: one Setting and any lore-only worlds.
  GroupWorldChoice worldChoice = const GroupWorldChoice();
  bool inheritCharacterLorebooks = false;

  // Realism / Chaos / Needs (group level + per-member seeds)
  bool realismEnabled =
      true; // Master group toggle — this is the only realism on/off control
  final Map<String, Map<String, dynamic>> memberRealismSeeds = {};
  bool chaosModeEnabled = false;
  bool chaosNsfwEnabled = false;
  bool needsSimEnabled = true;

  /// How the group's new chats start Afterglow.
  bool afterglowEnabled = true;

  // Per-member needs baselines (0-100) — mirrors memberRealismSeeds keys.
  final Map<String, Map<String, int>> memberNeedsBaselines = {};

  // Global time/day for the whole group (not per-character — prevents footgun)
  String globalTimeOfDay = 'morning';
  int globalDayCount = 1;
  // Story Calendar authoring (story-calendar.md §3a): null start date =
  // "the day the chat starts"; null time = period default.
  String? globalStoryStartDate;
  String? globalStoryStartTime;

  // Token-ish estimate (lightweight)
  int contentTokenEstimate = 0;

  @override
  void dispose() {
    _disposed = true;
    nameController.dispose();
    scenarioController.dispose();
    firstMessageController.dispose();
    // Dispose per-character controllers
    for (final ctrl in characterSystemPrompts.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  /// Applies [fn], then rebuilds the page.
  void update(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  void updateEstimates() {
    int total = 0;
    total += (nameController.text.length / 4).ceil();
    total += (scenarioController.text.length / 4).ceil();
    total += (firstMessageController.text.length / 4).ceil();
    for (final ctrl in characterSystemPrompts.values) {
      total += (ctrl.text.length / 4).ceil();
    }
    for (final e in groupLoreEntries) {
      total += ((e.name.length + e.key.length + e.content.length) / 4).ceil();
    }
    if (!_disposed && total != contentTokenEstimate) {
      update(() => contentTokenEstimate = total);
    }
  }

  /// Delegates to the canonical stable group ID.
  /// See [StableGroupId.stableGroupId] in lib/utils/character_id.dart
  String stableId(CharacterCard c) => c.stableGroupId;

  // ── SECTION NAV ────────────────────────────────────────────────────

  bool get canLeaveMembersStep => members.length >= 2;

  int? effectiveNextStep(int current) => GroupWizardSteps.next(current);

  void goToStep(int step) => update(() => currentStep = step);

  void goToPreviousStep(int current) =>
      goToStep(GroupWizardSteps.previous(current));

  void setWorldChoice(GroupWorldChoice choice) =>
      update(() => worldChoice = choice);

  bool canAdvanceFromStep(int step) {
    if (step == GroupWizardSteps.members) return canLeaveMembersStep;
    if (step == GroupWizardSteps.opening) {
      return members.length >= 2 && nameController.text.trim().isNotEmpty;
    }
    return true;
  }

  // ── MEMBER MANAGEMENT (heart of the experience) ────────────────────

  /// Library characters not yet on the roster.
  List<CharacterCard> availableFrom(List<CharacterCard> all) {
    final memberIds = members.map(stableId).toSet();
    return all.where((c) => !memberIds.contains(stableId(c))).toList();
  }

  void addMember(CharacterCard card) {
    final id = stableId(card);
    if (members.any((m) => stableId(m) == id)) return;
    update(() {
      members.add(card);
      if (!memberRealismSeeds.containsKey(id)) {
        memberRealismSeeds[id] = defaultRealismSeedFor(card);
      }
      _syncNeedsBaselines(id);

      // Initialize empty relationships map for small groups
      if (members.length <= 4) {
        final seed = memberRealismSeeds[id]!;
        seed['relationships'] ??= <String, int>{};
      }

      _followRosterInGroupName();
      updateEstimates();
    });
  }

  void removeMember(String id) {
    update(() {
      members.removeWhere((c) => stableId(c) == id);
      characterVoices.remove(id);
      characterSystemPrompts.remove(id);
      memberRealismSeeds.remove(id);

      // Clean up any references to this member from other characters' relationship maps
      for (final seed in memberRealismSeeds.values) {
        final rels = seed['relationships'];
        if (rels is Map) {
          rels.remove(id);
        }
      }

      _followRosterInGroupName();
    });
  }

  // onReorderItem (unlike the retired onReorder) delivers newIndex already
  // adjusted for the removal at oldIndex — no manual decrement.
  void reorderMembers(int oldIndex, int newIndex) {
    update(() {
      final moved = members.removeAt(oldIndex);
      members.insert(newIndex, moved);
      _followRosterInGroupName();
    });
  }

  /// Names the group after every member ("Juniper & Marlow") until the user
  /// types a name of their own; a typed name is never overwritten.
  void _followRosterInGroupName() {
    final current = nameController.text.trim();
    if (current.isNotEmpty && current != _autoGroupName) return;
    _autoGroupName = defaultGroupName([for (final c in members) c.name]);
    nameController.text = _autoGroupName;
  }

  void setVoice(String charId, String? voiceId) {
    update(() {
      characterVoices[charId] = voiceId ?? '';
    });
  }

  /// Where [c]'s member starts: their card's bonds, mood and Needs settings
  /// (see groupMemberSeedFromCard), the same seed the committer lays the
  /// wizard's edits over.
  Map<String, dynamic> defaultRealismSeedFor(CharacterCard c) =>
      groupMemberSeedFromCard(c);

  /// Reset to character defaults: the member's whole seed back to their
  /// card's, their Group Dynamics row included.
  void seedRealismFromCard(String charId) {
    final card = members.firstWhere(
      (c) => stableId(c) == charId,
      orElse: () => members.first,
    );
    update(() {
      memberRealismSeeds[charId] = defaultRealismSeedFor(card);
      _syncNeedsBaselines(charId);
    });
  }

  /// Neutral and High Bond: each member's card seed with the preset's bonds
  /// and mood. Long-Term Bond is set to the preset's Short-Term Bond, so the
  /// slider and the saved seed agree (the web's presets set the same keys).
  void bulkSeedRealism(String mode) {
    final preset = switch (mode) {
      'neutral' => const {
        'affection': 35,
        'longTermScore': 35,
        'trust': 40,
        'emotion': 'neutral',
        'emotionIntensity': 'mild',
      },
      'highBond' => const {
        'affection': 75,
        'longTermScore': 75,
        'trust': 70,
        'emotion': 'affection',
        'emotionIntensity': 'moderate',
      },
      _ => null,
    };
    if (preset == null) return;
    update(() {
      for (final c in members) {
        final id = stableId(c);
        memberRealismSeeds[id] = defaultRealismSeedFor(c)..addAll(preset);
        _syncNeedsBaselines(id);
      }
    });
  }

  /// [memberNeedsBaselines] for [id], read back from their seed, which the
  /// Needs sliders draw from.
  void _syncNeedsBaselines(String id) {
    final s = memberRealismSeeds[id] ?? const <String, dynamic>{};
    memberNeedsBaselines[id] = {
      for (final need in groupSeedNeeds)
        need: s[groupSeedBaselineKey(need)] as int? ?? 80,
      'enjoysLowHygiene': s['enjoysLowHygiene'] == true ? 1 : 0,
    };
  }

  // ── REALISM HELPERS ────────────────────────────────────────────────

  void updateMemberRealism(String charId, Map<String, dynamic> values) {
    update(() {
      memberRealismSeeds[charId] = {
        ...(memberRealismSeeds[charId] ??
            defaultRealismSeedFor(
              members.firstWhere((c) => stableId(c) == charId),
            )),
        ...values,
      };
    });
  }

  void updateRelationship(String fromId, String toId, int value) {
    update(() {
      final seed = memberRealismSeeds[fromId] ??= defaultRealismSeedFor(
        members.firstWhere((c) => stableId(c) == fromId),
      );

      final rels =
          (seed['relationships'] as Map<String, int>?)?.cast<String, int>() ??
          {};
      rels[toId] = value;
      seed['relationships'] = rels;
    });
  }

  // ── LORE & WORLDS ──────────────────────────────────────────────────

  /// Replaces the entry at [index], or appends when [index] is out of range.
  void putLoreEntry(LorebookEntry result, int? index) {
    update(() {
      if (index != null && index >= 0 && index < groupLoreEntries.length) {
        groupLoreEntries[index] = result;
      } else {
        groupLoreEntries.add(result);
      }
      updateEstimates();
    });
  }

  void deleteLoreEntry(int index) {
    update(() => groupLoreEntries.removeAt(index));
  }

  // ── GENERATION CONTEXT ─────────────────────────────────────────────

  /// Builds a rich, explanatory summary of the current hidden inter-character
  /// relationships (Group Dynamics, on the Realism step) to feed into AI generation.
  /// Includes guidance on the -300 to +300 scale so the model actually understands
  /// how to use the data when writing the opening scene.
  String buildDynamicsContextForGeneration() {
    // Realism off hides Group Dynamics and the committer drops them, so
    // relationships seeded before the switch went off must not leak here.
    if (!realismEnabled) return '';
    return groupDynamicsContext(
      [for (final m in members) (id: stableId(m), name: m.name)],
      {
        for (final m in members)
          stableId(m):
              (memberRealismSeeds[stableId(m)]?['relationships'] as Map?)
                  ?.cast<String, int>() ??
              const {},
      },
    );
  }
}
