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

import 'package:front_porch_ai/database/database.dart' show Objective;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/group_objectives/group_objectives.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The Objectives section's body in a group: the focused member's own
/// goals. The 1:1 [ObjectivePanel] edits the chat's loaded list, which in a
/// group holds the NEXT speaker's; this panel reads and writes [member]'s
/// goals directly (never swapping that list), so tapping another cast chip
/// shows and edits that member's quests and nobody else's.
class GroupObjectivesPanel extends StatefulWidget {
  const GroupObjectivesPanel({
    super.key,
    required this.chatService,
    required this.member,
  });

  final ChatService chatService;
  final CharacterCard member;

  @override
  State<GroupObjectivesPanel> createState() => _GroupObjectivesPanelState();
}

class _GroupObjectivesPanelState extends State<GroupObjectivesPanel> {
  List<Objective> _objectives = const [];
  bool _loading = true;
  bool _generatingTasks = false;
  final _generation = ObjectiveGenerationSettings();

  /// What last moved on the chat that can change a goal: a reply landing, a
  /// completion check. Re-reading the database on every notify (each streamed
  /// token) would be wasteful.
  Object? _signature;

  ChatService get _chat => widget.chatService;

  Object _signatureOf() =>
      (_chat.messages.length, _chat.isGenerating, _chat.isCheckingCompletion);

  @override
  void initState() {
    super.initState();
    _signature = _signatureOf();
    _chat.addListener(_onChat);
    _load();
  }

  @override
  void didUpdateWidget(GroupObjectivesPanel old) {
    super.didUpdateWidget(old);
    if (old.member.name != widget.member.name ||
        _chat.characterIdFor(old.member) !=
            _chat.characterIdFor(widget.member)) {
      setState(() => _loading = true);
      _load();
    }
  }

  @override
  void dispose() {
    _chat.removeListener(_onChat);
    super.dispose();
  }

  void _onChat() {
    final now = _signatureOf();
    if (now == _signature) return;
    _signature = now;
    _load();
  }

  Future<void> _load() async {
    final member = widget.member;
    final list = await _chat.getActiveObjectivesFor(member);
    // A slower read for the member tapped before must not paint over the
    // member shown now.
    if (!mounted || !identical(member, widget.member)) return;
    setState(() {
      _objectives = list;
      _loading = false;
    });
  }

  Objective? get _primary =>
      _objectives.where((o) => o.isPrimary && o.active).firstOrNull;
  List<Objective> get _secondaries =>
      _objectives.where((o) => !o.isPrimary && o.active).toList();

  Future<void> _add({required bool isPrimary}) async {
    final goal = await promptForObjectiveText(
      context,
      title: isPrimary ? 'New Primary Objective' : 'New Secondary Objective',
      confirmLabel: 'Add',
      hint: 'Goal description',
    );
    if (goal == null || !mounted) return;
    await _chat.setObjective(
      goal,
      isPrimary: isPrimary,
      targetCharacter: widget.member,
    );
    await _load();
  }

  Future<void> _regenerateTasks(Objective obj) async {
    setState(() => _generatingTasks = true);
    await _chat.generateObjectiveTasks(
      obj,
      taskCount: _generation.taskCount,
      nsfw: _generation.nsfw,
    );
    if (mounted) setState(() => _generatingTasks = false);
    await _load();
  }

  Widget _card(Objective obj, {required bool isPrimary}) => GroupObjectiveCard(
    key: ValueKey('group-objective-${obj.id}'),
    objective: obj,
    isPrimary: isPrimary,
    generatingTasks: _generatingTasks,
    onDelete: () async {
      await _chat.clearObjective(obj);
      await _load();
    },
    onToggleTask: (i) async {
      await _chat.toggleTask(obj, i);
      await _load();
    },
    onEditTask: (i, text) async {
      await _chat.updateTask(obj, i, text);
      await _load();
    },
    onRegenerateTasks: () => _regenerateTasks(obj),
    onPromote: () async {
      // In place: keeps the id and task progress.
      await _chat.promoteObjective(obj);
      await _load();
    },
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final label = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary(context),
    );
    final primary = _primary;
    final secondaries = _secondaries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("${widget.member.name}'s primary objective", style: label),
        const SizedBox(height: 6),
        if (primary != null)
          _card(primary, isPrimary: true)
        else
          Row(
            children: [
              Expanded(
                child: Text(
                  'No primary objective set.',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _add(isPrimary: true),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Set', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Text('Secondary objectives', style: label)),
            if (secondaries.length < kMaxSecondaryObjectives)
              TextButton.icon(
                onPressed: () => _add(isPrimary: false),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        if (secondaries.isEmpty)
          Text(
            'None set.',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppColors.textTertiary(context),
            ),
          )
        else
          for (final s in secondaries)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _card(s, isPrimary: false),
            ),
      ],
    );
  }
}
