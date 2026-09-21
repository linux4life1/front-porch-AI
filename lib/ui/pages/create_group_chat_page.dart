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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/lorebook_entry_dialog.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/group_alternate_greetings_editor.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/widgets/relationship_scale.dart'
    show relationshipTierName, relationshipScaleColor;
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;
import 'package:front_porch_ai/database/database.dart' as db;

part 'create_group_chat_page.member_realism_card.dart';
part 'create_group_chat_page.steps_cast.dart';
part 'create_group_chat_page.steps_dynamics.dart';
part 'create_group_chat_page.steps_lore.dart';
part 'create_group_chat_page.steps_opening.dart';
part 'create_group_chat_page.steps_realism.dart';
part 'create_group_chat_page.steps_review.dart';
part 'create_group_chat_page.roster.dart';
part 'create_group_chat_page.generate.dart';
part 'create_group_chat_page.commit.dart';

/// First-class, menu-driven Group Chat Creator (pure create flow).
///
/// Launched from the sidebar "Create Group" button.
/// Uses the exact same linear step wizard UI (top-bar dots, _currentStep,
/// AnimatedSwitcher, _buildNavButtons) as create_character_page.dart.
/// Edit flows now use the dedicated tabbed EditGroupPage (matching EditCharacterPage style).
class CreateGroupChatPage extends StatefulWidget {
  const CreateGroupChatPage({super.key});

  @override
  State<CreateGroupChatPage> createState() => _CreateGroupChatPageState();
}

class _CreateGroupChatPageState extends State<CreateGroupChatPage> {
  /// Re-exposes the protected [setState] for the `part of` extensions
  /// (`create_group_chat_page.*.dart`) — the wizard step builders can't call
  /// a State's protected members directly. Same bridge as settings_page.dart
  /// and chat_page.dart.
  void rebuildState(VoidCallback fn) => setState(fn);

  int _currentStep = 0;
  // 0 = Members
  // 1 = Identity
  // 2 = Opening
  // 3 = Prompts
  // 4 = Lore
  // 5 = Realism
  // 6 = Group Dynamics (only for groups of 4 or fewer)
  // 7 = Review

  // ── Core State ─────────────────────────────────────────────────────
  final List<CharacterCard> _members = [];
  // (reserved for future multi-select voice bulk actions)

  // Identity
  final _nameController = TextEditingController();

  // Behavior
  TurnOrder _turnOrder = TurnOrder.roundRobin;
  bool _autoAdvance = false;
  bool _directorMode = false;

  // Opening
  final _scenarioController = StyledTextController(
    preset: StyledTextPreset.prose,
  );
  final _firstMessageController = StyledTextController(
    preset: StyledTextPreset.prose,
  );
  List<String> _altGreetings = [];
  List<GreetingRealismSeed?> _altGreetingSeeds = [];
  bool _isGeneratingScenario = false;
  bool _isGeneratingFirst = false;

  // Prompts
  final _groupSystemController = StyledTextController(
    preset: StyledTextPreset.prose,
  );
  final Map<String, TextEditingController> _characterSystemPrompts =
      {}; // charId -> prompt

  // Voices (charId -> voiceId or '')
  final Map<String, String> _characterVoices = {};

  // Lore & Worlds
  final List<LorebookEntry> _groupLoreEntries = [];
  final List<String> _worldIds = [];
  bool _inheritCharacterLorebooks = false;
  // (reserved for future entry dialog state if we go non-modal)

  // Realism / Chaos / Needs (group level + per-member seeds)
  bool _realismEnabled =
      true; // Master group toggle — this is the only realism on/off control
  final Map<String, Map<String, dynamic>> _memberRealismSeeds = {};
  bool _chaosModeEnabled = false;
  bool _chaosNsfwEnabled = false;
  bool _needsSimEnabled = true;

  // Per-member needs baselines (0-100) — mirrors _memberRealismSeeds keys.
  final Map<String, Map<String, int>> _memberNeedsBaselines = {};

  // Global time/day for the whole group (not per-character — prevents footgun)
  String _globalTimeOfDay = 'morning';
  int _globalDayCount = 1;
  // Story Calendar authoring (story-calendar.md §3a): null start date =
  // "the day the chat starts"; null time = period default.
  String? _globalStoryStartDate;
  String? _globalStoryStartTime;

  // Token-ish estimate (lightweight)
  int _contentTokenEstimate = 0;

  @override
  void initState() {
    super.initState();

    _nameController.addListener(_updateEstimates);
    _scenarioController.addListener(_updateEstimates);
    _firstMessageController.addListener(_updateEstimates);
    _groupSystemController.addListener(_updateEstimates);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scenarioController.dispose();
    _firstMessageController.dispose();
    _groupSystemController.dispose();
    // Dispose per-character controllers
    for (final ctrl in _characterSystemPrompts.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _updateEstimates() {
    int total = 0;
    total += (_nameController.text.length / 4).ceil();
    total += (_scenarioController.text.length / 4).ceil();
    total += (_firstMessageController.text.length / 4).ceil();
    total += (_groupSystemController.text.length / 4).ceil();
    for (final ctrl in _characterSystemPrompts.values) {
      total += (ctrl.text.length / 4).ceil();
    }
    for (final e in _groupLoreEntries) {
      total += ((e.name.length + e.key.length + e.content.length) / 4).ceil();
    }
    if (mounted && total != _contentTokenEstimate) {
      setState(() => _contentTokenEstimate = total);
    }
  }

  /// Delegates to the canonical stable group ID.
  /// See [StableGroupId.stableGroupId] in lib/utils/character_id.dart
  String _stableId(CharacterCard c) => c.stableGroupId;

  // ── SECTION NAV ────────────────────────────────────────────────────

  bool get _canLeaveMembersStep => _members.length >= 2;

  int? _getEffectiveNextStep(int current) {
    int next = current + 1;

    // Skip Group Dynamics (now step 5) if group is too large
    if (next == 5 && _members.length > 4) {
      next = 6; // jump to Opening
    }

    if (next > 7) return null; // beyond Review
    return next;
  }

  void _goToPreviousStep(int current) {
    int prev = current - 1;

    // If we are coming back from Review and skipped Dynamics, go to Realism instead
    if (current == 7 && _members.length > 4) {
      prev = 4; // Realism
    }

    if (prev < 0) prev = 0;
    setState(() => _currentStep = prev);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── BUILD ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            Icon(
              Icons.group_add,
              color: AppColors.resolve(
                context,
                AppColors.logLoading,
                AppColors.userBubble,
              ),
              size: 22,
            ),
            const SizedBox(width: 10),
            const Text('Create Group Chat'),
            const Spacer(),
            _buildStepIndicator(),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _tokenBadge(),
          ),
        ],
      ),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _currentStep == 0
                ? _buildMembersStep()
                : _currentStep == 1
                ? _buildIdentityStep()
                : _currentStep == 2
                ? _buildPromptsStep()
                : _currentStep == 3
                ? _buildLoreStep()
                : _currentStep == 4
                ? _buildRealismStep()
                : _currentStep == 5
                ? (_members.length <= 4
                      ? _buildGroupDynamicsStep()
                      : _buildGroupDynamicsDisabledStep())
                : _currentStep == 6
                ? _buildOpeningStep()
                : _buildReviewStep(),
          ),
        ],
      ),
    );
  }
}
