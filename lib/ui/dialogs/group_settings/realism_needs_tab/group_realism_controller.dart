// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings_support.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/member_baseline_seed.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/member_ext_persist.dart';

/// Editing state and write-through logic behind the Group Settings Realism
/// tab. Notifies after every edit that should repaint the tab.
class GroupRealismNeedsController extends ChangeNotifier {
  GroupRealismNeedsController(this.chatService) {
    _initializeFromService();
  }

  final ChatService chatService;

  bool _realismEnabled = false;
  bool _chaosModeEnabled = false;
  bool _chaosNsfwEnabled = false;
  bool _nsfwEnhancementsEnabled = false;

  // Group-wide Time & Day.
  String _groupTimeOfDay = 'morning';
  int _groupDayCount = 1;
  // Story Calendar seed for fresh sessions (story-calendar.md §3a).
  String? _groupStoryStartDate;
  String? _groupStoryStartTime;
  late final TextEditingController groupDayCountController;

  List<CharacterCard> _chars = [];

  // Per-member Director/Verifier (Realism Verification) settings for groups.
  // Wired the same as 1:1 via per-member CharacterCard.frontPorchExtensions + impersonation.
  // UI exposed here for existing groups (previously only in creation flow).
  final Map<String, bool> verificationEnabled = {};
  final Map<String, int> verificationMaxReprocesses = {};
  final Map<String, int> verificationStrictness = {};
  final Map<String, bool> needsDirectorAuthority = {};

  // Baseline seeding state (only bond/trust/emotion/time/day)
  final Map<String, Map<String, dynamic>> baselineSeeds = {};

  // Per-character editable realism baselines (seeded from baselineSeeds + card ext).
  final Map<String, int> editShortTermBond = {};
  final Map<String, int> editLongTermBond = {};
  final Map<String, int> editTrustLevel = {};
  final Map<String, String> editEmotion = {};
  final Map<String, String> editEmotionIntensity = {};

  // Text controllers for inline editing fields.
  final Map<String, TextEditingController> _emotionControllers = {};

  // The Director/Verifier settings below live on the member's card ext — the
  // blob key each one also writes is read at group CREATION only. The ext only
  // reaches disk through this persister, so without it every one of them was
  // back to its old value on the next launch.
  late final GroupMemberExtPersister _extPersister = GroupMemberExtPersister(
    chatService,
  );

  bool get realismEnabled => _realismEnabled;
  bool get chaosModeEnabled => _chaosModeEnabled;
  bool get chaosNsfwEnabled => _chaosNsfwEnabled;
  bool get nsfwEnhancementsEnabled => _nsfwEnhancementsEnabled;
  String get groupTimeOfDay => _groupTimeOfDay;
  String? get groupStoryStartDate => _groupStoryStartDate;
  String? get groupStoryStartTime => _groupStoryStartTime;
  List<CharacterCard> get chars => _chars;

  void _initializeFromService() {
    final cs = chatService;
    _chars = cs.groupCharacters;

    _realismEnabled = cs.realismEnabled;
    _chaosModeEnabled = cs.chaosModeService.chaosModeEnabled;
    _chaosNsfwEnabled = cs.chaosModeService.chaosNsfwEnabled;
    // Group NSFW Enhancements (arousal/Lust + post-climax cooldowns). Uses the
    // stable per-member group flag (the live nsfwService scalar is per-speaker
    // volatile in groups); the write side propagates to every member.
    _nsfwEnhancementsEnabled = cs.isGroupNsfwEnabled;

    // Group-wide Time & Day, plus the per-member seed blob the ENGINE reads on
    // a fresh chat (parseGroupRealismSeeds → GroupMemberRealism).
    Map<String, dynamic> perCharSeeds = const {};
    final group = cs.activeGroup;
    if (group != null) {
      final gs = group.defaultMemberRealismState;
      if (gs.isNotEmpty && gs != '{}') {
        final map = (jsonDecode(gs) as Map<String, dynamic>?) ?? {};
        _groupTimeOfDay = (map['timeOfDay'] as String?) ?? 'morning';
        _groupDayCount = (map['dayCount'] as num?)?.toInt() ?? 1;
        _groupStoryStartDate = map['storyStartDate'] as String?;
        _groupStoryStartTime = map['storyStartTime'] as String?;
        perCharSeeds =
            (map['perChar'] as Map?)?.cast<String, dynamic>() ?? const {};
      }
    }
    groupDayCountController = TextEditingController(
      text: _groupDayCount.toString(),
    );

    // Load immutable creation baseline seeds (only the allowed fields)
    baselineSeeds.clear();
    for (final c in _chars) {
      final id = groupMemberStoreId(c);
      baselineSeeds[id] = Map<String, dynamic>.from(
        cs.getBaselineSeedForGroupCharacter(c),
      );

      // Load per-member Director/Verifier settings (if present on the member's card ext)
      verificationEnabled[id] =
          c.frontPorchExtensions?.realismVerificationEnabled ?? false;
      verificationMaxReprocesses[id] =
          c.frontPorchExtensions?.realismVerificationMaxReprocesses ?? 1;
      verificationStrictness[id] =
          c.frontPorchExtensions?.realismVerificationStrictness ?? 3;
      needsDirectorAuthority[id] =
          c.frontPorchExtensions?.realismNeedsDirectorAuthority ?? false;

      // Load the three relationship sliders. Their key mapping, the legacy
      // repair and the clamps all live in the shared leaf (and are tested
      // there) — this is a bug-prone corner, not a two-liner.
      final seed = baselineSeeds[id]!;
      final bond = bondBaselineFromSeeds(
        baselineSeed: seed,
        perCharSeed: (perCharSeeds[id] as Map?)?.cast<String, dynamic>(),
      );
      editShortTermBond[id] = bond.shortTerm;
      editLongTermBond[id] = bond.longTerm;
      editTrustLevel[id] = bond.trust;
      editEmotion[id] = (seed['emotion'] as String?) ?? 'neutral';
      editEmotionIntensity[id] = emotionIntensityFromSeed(
        seed['emotionIntensity'],
      );
    }
  }

  /// The member's Starting Emotion field controller, created on first use.
  TextEditingController emotionControllerFor(String id) =>
      _emotionControllers[id] ??= TextEditingController(
        text: editEmotion[id] ?? 'neutral',
      );

  // ── Master toggles ──

  void updateRealism(bool value) {
    _realismEnabled = value;
    notifyListeners();
    chatService.setRealismEnabled(value);
  }

  void updateChaosMode(bool value) {
    _chaosModeEnabled = value;
    notifyListeners();
    // ChatService wrapper — saves + notifies (the raw service does neither).
    chatService.setChaosModeEnabled(value);
  }

  void updateChaosNsfw(bool value) {
    _chaosNsfwEnabled = value;
    notifyListeners();
    chatService.setChaosNsfwEnabled(value);
  }

  void updateNsfwEnhancements(bool value) {
    _nsfwEnhancementsEnabled = value;
    notifyListeners();
    // Same setter the sidebar gear uses; in a group it propagates the flag to
    // every member's realism state (1:1 just sets the scalar).
    chatService.setNsfwCooldownEnabled(value);
  }

  // ── Time & Day ──

  void updateGroupTimeOfDay(String value) {
    _groupTimeOfDay = value;
    notifyListeners();
    _persistGroupTimeDay();
  }

  void updateGroupDayCount(int value) {
    _groupDayCount = value;
    notifyListeners();
    groupDayCountController.text = value.toString();
    _persistGroupTimeDay();
  }

  void updateGroupStoryStartDate(String? value) {
    _groupStoryStartDate = value;
    notifyListeners();
    _persistGroupTimeDay();
  }

  void updateGroupStoryStartTime(String? value) {
    _groupStoryStartTime = value;
    notifyListeners();
    _persistGroupTimeDay();
  }

  void _persistGroupTimeDay() {
    final group = chatService.activeGroup;
    if (group == null) return;
    try {
      final map =
          group.defaultMemberRealismState.isNotEmpty &&
              group.defaultMemberRealismState != '{}'
          ? (jsonDecode(group.defaultMemberRealismState)
                    as Map<String, dynamic>?) ??
                {}
          : <String, dynamic>{};
      map['timeOfDay'] = _groupTimeOfDay;
      map['dayCount'] = _groupDayCount;
      if (_groupStoryStartDate != null) {
        map['storyStartDate'] = _groupStoryStartDate;
      } else {
        map.remove('storyStartDate');
      }
      if (_groupStoryStartTime != null) {
        map['storyStartTime'] = _groupStoryStartTime;
      } else {
        map.remove('storyStartTime');
      }
      group.defaultMemberRealismState = jsonEncode(map);
    } catch (_) {
      // Non-fatal
    }
  }

  // ── Resets ──

  void resetAllRealismStates() {
    final cs = chatService;
    if (cs.activeGroup == null) return;

    for (final c in cs.groupCharacters) {
      cs.resetRealismForGroupCharacter(c);
    }
  }

  void resetCharacterRealism(CharacterCard character) {
    chatService.resetRealismForGroupCharacter(character);
  }

  // ── Editable realism baselines ──

  void updateEditShortTermBond(CharacterCard char, int value) =>
      _updateEdit(char, (id) => editShortTermBond[id] = value);

  void updateEditLongTermBond(CharacterCard char, int value) =>
      _updateEdit(char, (id) => editLongTermBond[id] = value);

  void updateEditTrustLevel(CharacterCard char, int value) =>
      _updateEdit(char, (id) => editTrustLevel[id] = value);

  void updateEditEmotion(CharacterCard char, String value) =>
      _updateEdit(char, (id) => editEmotion[id] = value);

  void updateEditEmotionIntensity(CharacterCard char, String value) =>
      _updateEdit(char, (id) => editEmotionIntensity[id] = value);

  void _updateEdit(CharacterCard char, void Function(String id) write) {
    final id = groupMemberStoreId(char);
    write(id);
    notifyListeners();
    _applyEditToBaselineSeedAndCard(char, id);
  }

  void _applyEditToBaselineSeedAndCard(CharacterCard char, String id) {
    final ext = char.frontPorchExtensions ?? FrontPorchExtensions();
    char.frontPorchExtensions = ext.copyWith(
      shortTermBond: editShortTermBond[id] ?? 50,
      longTermBond: editLongTermBond[id] ?? 50,
      trustLevel: editTrustLevel[id] ?? 50,
      characterEmotion: editEmotion[id] ?? 'neutral',
      emotionIntensity: editEmotionIntensity[id] ?? 'moderate',
    );

    // Update the baseline seed via ChatService.
    try {
      chatService.setBaselineSeedForGroupCharacter(char, {
        'affection': editShortTermBond[id] ?? 50,
        'longTermScore': editLongTermBond[id] ?? 50,
        'trust': editTrustLevel[id] ?? 50,
        'emotion': editEmotion[id] ?? 'neutral',
        'emotionIntensity': editEmotionIntensity[id] ?? 'moderate',
      });
    } catch (_) {
      // Non-fatal
    }

    // Persist to group defaultMemberRealismState.
    try {
      final group = chatService.activeGroup;
      if (group != null) {
        final map =
            group.defaultMemberRealismState.isNotEmpty &&
                group.defaultMemberRealismState != '{}'
            ? (jsonDecode(group.defaultMemberRealismState)
                      as Map<String, dynamic>? ??
                  {})
            : <String, dynamic>{};
        final perChar = (map['perChar'] as Map<String, dynamic>? ?? {})
            .cast<String, dynamic>();
        final current = (perChar[id] as Map<String, dynamic>? ?? {})
            .cast<String, dynamic>();
        // ENGINE key names — the card-ext names written here before made four
        // of the five sliders a no-op (GroupMemberRealism reads only
        // affection/longTermScore/trust/emotion/emotionIntensity and passes
        // everything else through untouched).
        applyBaselineToMemberSeed(
          current,
          affection: editShortTermBond[id] ?? 50,
          longTermScore: editLongTermBond[id] ?? 50,
          trust: editTrustLevel[id] ?? 50,
          emotion: editEmotion[id] ?? 'neutral',
          emotionIntensity: editEmotionIntensity[id] ?? 'moderate',
        );
        perChar[id] = current;
        map['perChar'] = perChar;
        group.defaultMemberRealismState = jsonEncode(map);
      }
    } catch (_) {
      // Non-fatal
    }
  }

  // ── Per-member Director/Verifier ──

  void updateMemberVerificationEnabled(CharacterCard char, bool value) =>
      _updateMemberVerifier(
        char,
        'verificationEnabled',
        value,
        (id) => verificationEnabled[id] = value,
        (ext) => ext.copyWith(realismVerificationEnabled: value),
      );

  void updateMemberVerificationMaxReprocesses(CharacterCard char, int value) =>
      _updateMemberVerifier(
        char,
        'verificationMaxReprocesses',
        value,
        (id) => verificationMaxReprocesses[id] = value,
        (ext) => ext.copyWith(realismVerificationMaxReprocesses: value),
      );

  void updateMemberVerificationStrictness(CharacterCard char, int value) =>
      _updateMemberVerifier(
        char,
        'verificationStrictness',
        value,
        (id) => verificationStrictness[id] = value,
        (ext) => ext.copyWith(realismVerificationStrictness: value),
      );

  void updateMemberNeedsDirectorAuthority(CharacterCard char, bool value) =>
      _updateMemberVerifier(
        char,
        'needsDirectorAuthority',
        value,
        (id) => needsDirectorAuthority[id] = value,
        (ext) => ext.copyWith(realismNeedsDirectorAuthority: value),
      );

  void _updateMemberVerifier(
    CharacterCard char,
    String blobKey,
    Object value,
    void Function(String id) write,
    FrontPorchExtensions Function(FrontPorchExtensions) patch,
  ) {
    final id = groupMemberStoreId(char);
    write(id);
    char.frontPorchExtensions = patch(
      char.frontPorchExtensions ?? FrontPorchExtensions(),
    );
    char.frontPorchExtensions?.ensureStableId();
    notifyListeners();

    persistGroupMemberPref(chatService, id, blobKey, value);
    _extPersister.schedule(char);
  }

  @override
  void dispose() {
    groupDayCountController.dispose();
    _extPersister.dispose();
    super.dispose();
  }
}
