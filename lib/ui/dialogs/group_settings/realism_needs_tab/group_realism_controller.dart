// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/utils.dart';
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
  bool _afterglowEnabled = true;

  // Group-wide Time & Day.
  String _groupTimeOfDay = 'morning';
  int _groupDayCount = 1;
  // Story Calendar seed for fresh sessions (story-calendar.md §3a).
  String? _groupStoryStartDate;
  String? _groupStoryStartTime;
  late final TextEditingController groupDayCountController;

  List<CharacterCard> _chars = [];

  // Baseline seeding state (only bond/trust/emotion/time/day)
  final Map<String, Map<String, dynamic>> baselineSeeds = {};

  // A member's Recovery lives on their card ext, which only reaches disk
  // through this persister.
  late final GroupMemberExtPersister _extPersister = GroupMemberExtPersister(
    chatService,
  );

  bool get realismEnabled => _realismEnabled;
  bool get chaosModeEnabled => _chaosModeEnabled;
  bool get chaosNsfwEnabled => _chaosNsfwEnabled;
  bool get afterglowEnabled => _afterglowEnabled;
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
    _afterglowEnabled = cs.afterglowChatSwitch;

    // Group-wide Time & Day.
    final group = cs.activeGroup;
    if (group != null) {
      final gs = group.defaultMemberRealismState;
      if (gs.isNotEmpty && gs != '{}') {
        final map = (jsonDecode(gs) as Map<String, dynamic>?) ?? {};
        _groupTimeOfDay = (map['timeOfDay'] as String?) ?? 'morning';
        _groupDayCount = (map['dayCount'] as num?)?.toInt() ?? 1;
        _groupStoryStartDate = map['storyStartDate'] as String?;
        _groupStoryStartTime = map['storyStartTime'] as String?;
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
    }
  }

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

  /// This group chat's own Afterglow switch.
  void updateAfterglow(bool value) {
    _afterglowEnabled = value;
    notifyListeners();
    chatService.setAfterglowEnabled(value);
  }

  /// A member's own Afterglow switch, on their card in this group.
  void updateMemberAfterglow(CharacterCard char, bool value) {
    chatService.setMemberAfterglowEnabled(char, value).catchError((Object e) {
      debugPrint('[GroupSettings] Afterglow for ${char.name} not saved: $e');
    });
    notifyListeners();
  }

  /// A member's Recovery block, on their card in this group. Saved with the
  /// member's other extensions.
  void updateMemberRecovery(CharacterCard char, RecoveryProfile recovery) {
    char.frontPorchExtensions =
        (char.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
          recovery: recovery,
        );
    char.frontPorchExtensions?.ensureStableId();
    notifyListeners();
    _extPersister.schedule(char);
  }

  void updateChaosNsfw(bool value) {
    _chaosNsfwEnabled = value;
    notifyListeners();
    chatService.setChaosNsfwEnabled(value);
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

  @override
  void dispose() {
    groupDayCountController.dispose();
    _extPersister.dispose();
    super.dispose();
  }
}
