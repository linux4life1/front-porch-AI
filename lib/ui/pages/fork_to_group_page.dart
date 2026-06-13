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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/pages/fork_to_group_characters_step.dart';
import 'package:front_porch_ai/ui/pages/fork_to_group_steps.dart';
import 'package:front_porch_ai/utils/character_id.dart';

/// Stepped wizard for forking the active 1:1 chat into a group.
///
/// Replaces the old single `showDialog` popup so each added character can get
/// its own optional entrance. Uses the same linear step pattern as
/// create_group_chat_page.dart (top-bar dots, AnimatedSwitcher, nav buttons).
/// Step bodies live in fork_to_group_steps.dart to keep each file small.
///
/// Steps are dynamic: Characters → Setup → one Entrance step per added
/// character → Review.
class ForkToGroupPage extends StatefulWidget {
  const ForkToGroupPage({super.key});

  @override
  State<ForkToGroupPage> createState() => _ForkToGroupPageState();
}

class _ForkToGroupPageState extends State<ForkToGroupPage> {
  int _currentStep = 0;
  bool _forking = false;

  CharacterCard? _original;
  final List<CharacterCard> _added = [];

  final _nameController = TextEditingController();
  final _scenarioController = TextEditingController();
  bool _nameManuallyEdited = false;
  TurnOrder _turnOrder = TurnOrder.roundRobin;

  // Per-character entrance state, keyed by character name (stable across the
  // member copy that the fork performs).
  final Map<String, TextEditingController> _entranceCtrls = {};
  final Map<String, bool> _entranceCreative = {};

  @override
  void initState() {
    super.initState();
    _original = context.read<ChatService>().activeCharacter;
    _nameController.text = _original?.name ?? 'Group';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scenarioController.dispose();
    for (final c in _entranceCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Derived state ──────────────────────────────────────────────────────

  // Characters: 0, Setup: 1, one Entrance step per added char, then Review.
  int get _totalSteps => 2 + _added.length + 1;
  int get _reviewStep => _totalSteps - 1;
  bool get _isEntranceStep =>
      _currentStep >= 2 && _currentStep < 2 + _added.length;

  List<CharacterCard> get _availableCharacters {
    final repo = context.read<CharacterRepository>();
    final originalId = _original?.stableGroupId;
    final addedIds = _added.map((c) => c.stableGroupId).toSet();
    return repo.characters
        .where(
          (c) =>
              c.stableGroupId != originalId &&
              !addedIds.contains(c.stableGroupId),
        )
        .toList();
  }

  // ── Mutations ──────────────────────────────────────────────────────────

  void _addCharacter(CharacterCard card) {
    setState(() {
      _added.add(card);
      _entranceCtrls.putIfAbsent(card.stableGroupId, () => TextEditingController());
      _entranceCreative.putIfAbsent(card.stableGroupId, () => false);
      _refreshAutoName();
    });
  }

  void _removeCharacter(CharacterCard card) {
    setState(() {
      _added.remove(card);
      _entranceCtrls.remove(card.stableGroupId)?.dispose();
      _entranceCreative.remove(card.stableGroupId);
      _refreshAutoName();
      if (_currentStep >= _totalSteps) _currentStep = _totalSteps - 1;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      _added.insert(newIndex, _added.removeAt(oldIndex));
    });
  }

  void _refreshAutoName() {
    if (_nameManuallyEdited) return;
    final names = [
      if (_original != null) _original!.name,
      ..._added.map((c) => c.name),
    ];
    _nameController.text = names.join(' & ');
  }

  // ── Navigation ─────────────────────────────────────────────────────────

  bool get _canAdvance {
    if (_currentStep == 0) return _added.isNotEmpty;
    if (_currentStep == 1) return _nameController.text.trim().isNotEmpty;
    return true;
  }

  void _next() {
    if (_currentStep >= _reviewStep) {
      _fork();
      return;
    }
    setState(() => _currentStep++);
  }

  void _back() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  Future<void> _fork() async {
    if (_forking) return;
    final chat = context.read<ChatService>();
    final groupRepo = context.read<GroupChatRepository>();

    // Keyed by stableGroupId (unique) so two characters that happen to share a
    // name don't overwrite each other's entrance.
    final entrances = <String, ({String text, bool creative})>{};
    for (final c in _added) {
      final id = c.stableGroupId;
      final text = _entranceCtrls[id]?.text.trim() ?? '';
      if (text.isNotEmpty) {
        entrances[id] = (
          text: text,
          creative: _entranceCreative[id] ?? false,
        );
      }
    }

    setState(() => _forking = true);
    final group = await chat.forkToGroupChat(
      List.of(_added),
      groupRepo,
      groupName: _nameController.text.trim(),
      scenario: _scenarioController.text.trim(),
      turnOrder: _turnOrder,
      entrances: entrances,
    );

    if (!mounted) return;
    if (group != null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Group "${group.name}" created from fork!')),
      );
    } else {
      setState(() => _forking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not fork this chat into a group.')),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        title: Row(
          children: [
            Icon(Icons.call_split, color: forkAccent(context), size: 20),
            const SizedBox(width: 10),
            const Flexible(child: Text('Fork to Group Chat')),
            const Spacer(),
            Flexible(child: _buildStepIndicator()),
          ],
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _forking
            ? const Center(child: CircularProgressIndicator())
            : _scaffoldFor(_buildStepContent()),
      ),
    );
  }

  Widget _scaffoldFor(Widget content) {
    return SingleChildScrollView(
      key: ValueKey(_currentStep),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [content, _buildNavButtons()],
      ),
    );
  }

  Widget _buildStepContent() {
    if (_currentStep == 0) {
      return ForkCharactersStep(
        original: _original,
        added: _added,
        available: _availableCharacters,
        onAdd: _addCharacter,
        onRemove: _removeCharacter,
        onReorder: _reorder,
      );
    }
    if (_currentStep == 1) {
      return ForkSetupStep(
        nameController: _nameController,
        scenarioController: _scenarioController,
        turnOrder: _turnOrder,
        onNameChanged: (_) {
          _nameManuallyEdited = true;
          setState(() {});
        },
        onTurnOrderChanged: (v) => setState(() => _turnOrder = v),
      );
    }
    if (_isEntranceStep) {
      final c = _added[_currentStep - 2];
      return ForkEntranceStep(
        character: c,
        controller: _entranceCtrls[c.stableGroupId]!,
        creative: _entranceCreative[c.stableGroupId] ?? false,
        turnOrder: _turnOrder,
        onCreativeChanged: (v) =>
            setState(() => _entranceCreative[c.stableGroupId] = v),
      );
    }
    return ForkReviewStep(
      name: _nameController.text.trim(),
      turnOrder: _turnOrder,
      scenario: _scenarioController.text.trim(),
      added: _added,
      entranceTextFor: (c) => _entranceCtrls[c.stableGroupId]?.text.trim() ?? '',
      creativeFor: (c) => _entranceCreative[c.stableGroupId] ?? false,
    );
  }

  // ── Step indicator (dynamic; mirrors create_group_chat_page pattern) ─────

  Widget _buildStepIndicator() {
    final labels = <String>[
      'Characters',
      'Setup',
      ..._added.map((c) => c.name),
      'Review',
    ];
    final children = <Widget>[];
    for (int i = 0; i < labels.length; i++) {
      children.add(_stepDot(i, labels[i]));
      if (i < labels.length - 1) children.add(_stepLine());
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _stepDot(int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? forkAccent(context)
                : AppColors.surfaceContainerOf(context),
            border: Border.all(
              color: isCurrent
                  ? AppColors.textPrimary(context)
                  : AppColors.borderOf(context).withValues(alpha: 0.4),
              width: isCurrent ? 2 : 1,
            ),
          ),
          child: Center(
            child: isActive && !isCurrent
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isActive
                          ? Colors.white
                          : AppColors.textTertiary(context),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: 56,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              color: isActive
                  ? AppColors.textSecondary(context)
                  : AppColors.textTertiary(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepLine() => Container(
    width: 16,
    height: 2,
    margin: const EdgeInsets.only(bottom: 14),
    color: AppColors.borderOf(context).withValues(alpha: 0.35),
  );

  // ── Nav buttons ──────────────────────────────────────────────────────────

  Widget _buildNavButtons() {
    final isLast = _currentStep >= _reviewStep;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_currentStep > 0)
            OutlinedButton.icon(
              onPressed: _back,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary(context),
                side: BorderSide(color: AppColors.borderOf(context)),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _canAdvance ? _next : null,
            icon: Icon(
              isLast ? Icons.call_split : Icons.arrow_forward,
              size: 18,
            ),
            label: Text(isLast ? 'Fork to Group' : 'Next'),
            style: ElevatedButton.styleFrom(
              backgroundColor: forkAccent(context),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
