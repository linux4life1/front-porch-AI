// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings_support.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/member_baseline_seed.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/member_ext_persist.dart';

part 'realism_needs_tab.view.dart';
part 'realism_needs_tab.controls.dart';
part 'realism_needs_tab.member.dart';
part 'realism_needs_tab.verify.dart';
part 'realism_needs_tab.edits.dart';
part 'realism_needs_tab.toggles.dart';

class GroupRealismNeedsTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;
  const GroupRealismNeedsTab({
    super.key,
    required this.chatService,
    this.groupRepo,
  });

  @override
  State<GroupRealismNeedsTab> createState() => _GroupRealismNeedsTabState();
}

class _GroupRealismNeedsTabState extends State<GroupRealismNeedsTab> {
  bool _realismEnabled = false;
  bool _passageOfTimeEnabled = true;
  bool _chaosModeEnabled = false;
  bool _chaosNsfwEnabled = false;
  bool _nsfwEnhancementsEnabled = false;

  // Group-wide Time & Day.
  String _groupTimeOfDay = 'morning';
  int _groupDayCount = 1;
  // Story Calendar seed for fresh sessions (story-calendar.md §3a).
  String? _groupStoryStartDate;
  String? _groupStoryStartTime;
  late final TextEditingController _groupDayCountController;

  List<CharacterCard> _chars = [];

  // Per-member Director/Verifier (Realism Verification) settings for groups.
  // Wired the same as 1:1 via per-member CharacterCard.frontPorchExtensions + impersonation.
  // UI exposed here for existing groups (previously only in creation flow).
  final Map<String, bool> _verificationEnabled = {};
  final Map<String, int> _verificationMaxReprocesses = {};
  final Map<String, int> _verificationStrictness = {};
  final Map<String, bool> _needsDirectorAuthority = {};

  // Baseline seeding state (only bond/trust/emotion/time/day)
  final Map<String, Map<String, dynamic>> _baselineSeeds = {};

  // Per-character editable realism baselines (seeded from baselineSeeds + card ext).
  final Map<String, int> _editShortTermBond = {};
  final Map<String, int> _editLongTermBond = {};
  final Map<String, int> _editTrustLevel = {};
  final Map<String, String> _editEmotion = {};
  final Map<String, String> _editEmotionIntensity = {};

  // Text controllers for inline editing fields.
  final Map<String, TextEditingController> _emotionControllers = {};

  @override
  void initState() {
    super.initState();
    widget.chatService.addListener(_onServiceChanged);
    _initializeFromService();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _initializeFromService() {
    final cs = widget.chatService;
    _chars = cs.groupCharacters;

    _realismEnabled = cs.realismEnabled;
    _passageOfTimeEnabled = cs.timeService.passageOfTimeEnabled;
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
    _groupDayCountController = TextEditingController(
      text: _groupDayCount.toString(),
    );

    // Load immutable creation baseline seeds (only the allowed fields)
    _baselineSeeds.clear();
    for (final c in _chars) {
      final id = _getCharId(c);
      _baselineSeeds[id] = Map<String, dynamic>.from(
        cs.getBaselineSeedForGroupCharacter(c),
      );

      // Load per-member Director/Verifier settings (if present on the member's card ext)
      _verificationEnabled[id] =
          c.frontPorchExtensions?.realismVerificationEnabled ?? false;
      _verificationMaxReprocesses[id] =
          c.frontPorchExtensions?.realismVerificationMaxReprocesses ?? 1;
      _verificationStrictness[id] =
          c.frontPorchExtensions?.realismVerificationStrictness ?? 3;
      _needsDirectorAuthority[id] =
          c.frontPorchExtensions?.realismNeedsDirectorAuthority ?? false;

      // Load the three relationship sliders. Their key mapping, the legacy
      // repair and the clamps all live in the shared leaf (and are tested
      // there) — this is a bug-prone corner, not a two-liner.
      final seed = _baselineSeeds[id]!;
      final bond = bondBaselineFromSeeds(
        baselineSeed: seed,
        perCharSeed: (perCharSeeds[id] as Map?)?.cast<String, dynamic>(),
      );
      _editShortTermBond[id] = bond.shortTerm;
      _editLongTermBond[id] = bond.longTerm;
      _editTrustLevel[id] = bond.trust;
      _editEmotion[id] = (seed['emotion'] as String?) ?? 'neutral';
      _editEmotionIntensity[id] =
          (seed['emotionIntensity'] as String?) ?? 'moderate';
    }
  }

  // The Director/Verifier settings below live on the member's card ext — the
  // blob key each one also writes is read at group CREATION only. The ext only
  // reaches disk through this persister, so without it every one of them was
  // back to its old value on the next launch.
  late final GroupMemberExtPersister _extPersister = GroupMemberExtPersister(
    widget.chatService,
  );

  /// Public setState bridge for the part-file extensions
  /// (same pattern as settings_page's rebuildState).
  void rebuildState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) => _buildRealismTabBody(context);

  // Must be byte-identical to the id every service stores a member under
  // (ChatService._getCharacterIdFromCard). The hand-rolled version answered ''
  // for a member with no avatar file and truncated at the first dot otherwise,
  // so the perChar seed landed under a key the engine never looks up.
  String _getCharId(CharacterCard c) => c.stableGroupId;

  @override
  void dispose() {
    widget.chatService.removeListener(_onServiceChanged);
    _groupDayCountController.dispose();
    _extPersister.dispose();
    super.dispose();
  }
}
