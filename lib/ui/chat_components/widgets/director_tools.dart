// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/director/director.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The auto-chat run lengths the Director offers (0 = no limit).
const List<int> kDirectorTurnBudgetChoices = [0, 3, 6, 10, 20];

/// The Director panel's tools while the user directs: cue who speaks next,
/// one-tap beats, the pinned scene goal, the private whispers, and how long
/// an auto-chat run goes before it pauses.
class DirectorTools extends StatefulWidget {
  const DirectorTools({
    super.key,
    required this.memberNames,
    this.beats = kDirectorQuickBeats,
    required this.goal,
    required this.whispers,
    required this.turnBudget,
    required this.turnsLeft,
    required this.busy,
    required this.onCue,
    required this.onBeat,
    required this.onGoal,
    required this.onClearWhisper,
    required this.onTurnBudget,
  });

  final List<String> memberNames;
  final List<DirectorBeat> beats;
  final String goal;
  final List<({String id, String name, String text})> whispers;
  final int turnBudget;

  /// Turns left in the running auto-chat, or null when none is limited.
  final int? turnsLeft;

  /// A turn is running: cues and beats wait for it.
  final bool busy;
  final ValueChanged<String> onCue;
  final ValueChanged<String> onBeat;
  final ValueChanged<String> onGoal;
  final ValueChanged<String> onClearWhisper;
  final ValueChanged<int> onTurnBudget;

  @override
  State<DirectorTools> createState() => _DirectorToolsState();
}

class _DirectorToolsState extends State<DirectorTools> {
  final _goalCtrl = TextEditingController();

  @override
  void dispose() {
    _goalCtrl.dispose();
    super.dispose();
  }

  void _pinGoal() {
    final text = _goalCtrl.text.trim();
    if (text.isEmpty) return;
    widget.onGoal(text);
    _goalCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final secondary = AppColors.textSecondary(context);
    final label = TextStyle(color: secondary, fontSize: 11);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text('Cue who speaks next', style: label),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final name in widget.memberNames)
              ActionChip(
                key: ValueKey('director-cue-$name'),
                label: Text(name, style: const TextStyle(fontSize: 11)),
                onPressed: widget.busy ? null : () => widget.onCue(name),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Quick beats', style: label),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final beat in widget.beats)
              ActionChip(
                key: ValueKey('director-beat-${beat.label}'),
                avatar: Icon(Icons.bolt, size: 14, color: amber),
                label: Text(beat.label, style: const TextStyle(fontSize: 11)),
                onPressed: widget.busy ? null : () => widget.onBeat(beat.note),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Scene goal', style: label),
        const SizedBox(height: 4),
        if (widget.goal.isNotEmpty)
          _Pinned(
            key: const ValueKey('director-goal'),
            icon: Icons.push_pin,
            text: widget.goal,
            clearTooltip: 'Clear the scene goal',
            onClear: () => widget.onGoal(''),
          )
        else
          TextField(
            key: const ValueKey('director-goal-input'),
            controller: _goalCtrl,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Where should the scene go?',
              suffixIcon: IconButton(
                tooltip: 'Pin the scene goal',
                icon: Icon(Icons.push_pin_outlined, size: 16, color: amber),
                onPressed: _pinGoal,
              ),
            ),
            onSubmitted: (_) => _pinGoal(),
          ),
        const SizedBox(height: 8),
        Text('Whispers', style: label),
        const SizedBox(height: 4),
        if (widget.whispers.isEmpty)
          Text(
            '/whisper <name> <direction> tells one character something the '
            'others don\'t know.',
            style: TextStyle(color: secondary, fontSize: 10),
          ),
        for (final w in widget.whispers)
          _Pinned(
            key: ValueKey('director-whisper-${w.id}'),
            icon: Icons.hearing,
            text: '${w.name}: ${w.text}',
            clearTooltip: 'Clear the whisper to ${w.name}',
            onClear: () => widget.onClearWhisper(w.id),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Auto-chat run', style: label),
            const Spacer(),
            if (widget.turnsLeft != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${widget.turnsLeft} left',
                  style: TextStyle(color: amber, fontSize: 11),
                ),
              ),
            DropdownButton<int>(
              key: const ValueKey('director-turn-budget'),
              value: kDirectorTurnBudgetChoices.contains(widget.turnBudget)
                  ? widget.turnBudget
                  : 0,
              isDense: true,
              style: TextStyle(color: amber, fontSize: 11),
              underline: const SizedBox.shrink(),
              items: [
                for (final n in kDirectorTurnBudgetChoices)
                  DropdownMenuItem(
                    value: n,
                    child: Text(n == 0 ? 'No limit' : '$n turns'),
                  ),
              ],
              onChanged: (v) {
                if (v != null) widget.onTurnBudget(v);
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _Pinned extends StatelessWidget {
  const _Pinned({
    super.key,
    required this.icon,
    required this.text,
    required this.clearTooltip,
    required this.onClear,
  });

  final IconData icon;
  final String text;
  final String clearTooltip;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: amber),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 11,
              ),
            ),
          ),
          IconButton(
            tooltip: clearTooltip,
            visualDensity: VisualDensity.compact,
            iconSize: 14,
            icon: const Icon(Icons.close),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}
