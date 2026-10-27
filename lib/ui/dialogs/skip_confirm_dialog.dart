// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Did time pass?" (#629): the desktop face of the chat's pending skip
// question. The skips on offer come from the engine (`PendingSkip`), best
// guess first; "No skip" and "Other…" (read like `/skip 8h`) sit beside
// them. Pops the picked verdict, or null when dismissed (the guess
// stands). Closes itself when the question goes away under it: answered
// on the web, or the chat changed.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/body_clock.dart'
    show kLongSkipMinutes;
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_skip/time_skip.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';

/// What the primary button says for [verdict] at [clock].
String skipConfirmAction(SkipVerdict verdict, DateTime clock) {
  final at = verdict.landing(clock);
  return at == null
      ? 'Send without a skip'
      : 'Skip to ${StoryClock.formatClock(at)}';
}

/// The line under the chips for [verdict] at [clock], or null.
String? skipConfirmNote(SkipVerdict verdict, DateTime clock) {
  final at = verdict.landing(clock);
  if (at == null) return null;
  if (at.difference(clock).inMinutes >= kLongSkipMinutes) {
    return 'A narrator card fills in the time that passed.';
  }
  return verdict.slept ? 'Everyone wakes rested.' : null;
}

/// Opens the question for [question] while [isLive] holds; [changes]
/// fires when it may not.
Future<SkipVerdict?> showSkipConfirmDialog(
  BuildContext context, {
  required PendingSkip question,
  required Listenable changes,
  required bool Function() isLive,
}) => showWarmDialogOf<SkipVerdict>(
  context,
  builder: (_) =>
      SkipConfirmDialog(question: question, changes: changes, isLive: isLive),
);

class SkipConfirmDialog extends StatefulWidget {
  const SkipConfirmDialog({
    super.key,
    required this.question,
    required this.changes,
    required this.isLive,
  });

  final PendingSkip question;
  final Listenable changes;
  final bool Function() isLive;

  @override
  State<SkipConfirmDialog> createState() => _SkipConfirmDialogState();
}

/// A chip: an offered skip by index, no skip, or other.
const int _none = -1;
const int _other = -2;

class _SkipConfirmDialogState extends State<SkipConfirmDialog> {
  final _otherText = TextEditingController();
  int? _picked;
  bool _closed = false;

  PendingSkip get _q => widget.question;

  @override
  void initState() {
    super.initState();
    // Pick B: with no reading there is no guess to preselect.
    if (_q.reason != SkipAskReason.noReading && _q.choices.isNotEmpty) {
      _picked = 0;
    }
    widget.changes.addListener(_closeIfGone);
  }

  @override
  void dispose() {
    widget.changes.removeListener(_closeIfGone);
    _otherText.dispose();
    super.dispose();
  }

  void _closeIfGone() {
    if (_closed || widget.isLive() || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  SkipVerdict? get _verdict => switch (_picked) {
    null => null,
    _none => SkipVerdict.none,
    _other => SkipTag.readArgs(_otherText.text),
    final i => _q.choices[i].verdict,
  };

  void _answer() {
    final verdict = _verdict;
    if (verdict == null || _closed) return;
    _closed = true;
    Navigator.of(context).pop(verdict);
  }

  @override
  Widget build(BuildContext context) {
    final verdict = _verdict;
    final note = verdict == null ? null : skipConfirmNote(verdict, _q.clock);
    final otherBad =
        _picked == _other &&
        _otherText.text.trim().isNotEmpty &&
        verdict == null;
    return WarmDialog(
      title: 'Did time pass?',
      icon: Icons.schedule,
      width: 380,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WarmDialogText(_q.question),
            const SizedBox(height: 6),
            Text(
              '“${_clip(_q.line)}”',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontStyle: FontStyle.italic,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _q.choices.length; i++)
                  _chip(context, i, _q.choices[i].label),
                _chip(context, _none, 'No skip'),
                _chip(context, _other, 'Other…'),
              ],
            ),
            if (_picked == _other) ...[
              const SizedBox(height: 10),
              TextField(
                key: const Key('skip-other-field'),
                controller: _otherText,
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '8h, 2d, morning, 7:30 pm',
                  errorText: otherBad ? kSkipTagUsage : null,
                  errorMaxLines: 3,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _answer(),
              ),
            ],
            if (note != null) ...[
              const SizedBox(height: 10),
              Text(
                note,
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          key: const Key('skip-confirm'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.porchAmberOf(context),
            foregroundColor: AppColors.onAccentOf(context),
          ),
          onPressed: verdict == null ? null : _answer,
          child: Text(
            verdict == null ? 'Pick one' : skipConfirmAction(verdict, _q.clock),
          ),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, int value, String label) {
    final on = _picked == value;
    return ChoiceChip(
      key: Key('skip-choice-$value'),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: on
              ? AppColors.onAccentOf(context)
              : AppColors.textSecondary(context),
        ),
      ),
      selected: on,
      showCheckmark: false,
      backgroundColor: AppColors.surfaceContainerOf(context),
      selectedColor: AppColors.porchAmberOf(context),
      side: BorderSide(color: AppColors.borderOf(context)),
      onSelected: (_) => setState(() => _picked = value),
    );
  }

  static String _clip(String line) {
    final one = line.trim().replaceAll(RegExp(r'\s+'), ' ');
    return one.length <= 140 ? one : '${one.substring(0, 139)}…';
  }
}
