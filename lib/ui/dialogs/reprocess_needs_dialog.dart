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

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

const kReprocessNeedsIntro =
    'Enter your critique to correct the Needs Simulation deltas. The Realism Director will re-evaluate the scene based on this input.';
const kReprocessNeedsHint =
    'e.g., They rested on the sofa — energy should have improved.';
const kReprocessNeedsEmptyHelper =
    'Nothing selected — every need shown here is re-evaluated.';
const kReprocessNeedsSomeHelper =
    'Only the selected needs change. The others keep their current deltas.';

String reprocessNeedsOneEnabledLine(String need, String name) {
  final label = needTitle(need);
  return 'Only $label is on for $name, so only $label is re-evaluated.';
}

const kReprocessNeedsNothing =
    'There\'s nothing to reprocess for this message.';

// The Feelings choice. Keep in lockstep with web_ui ReprocessNeedsModal.
const kReprocessChoicePrompt = 'What should be redone?';
const kReprocessChoiceNeeds = 'Needs';
const kReprocessChoiceFeelings = 'Feelings (bond, trust, mood)';
const kReprocessFeelingsTitle = 'Reprocess Feelings';
const kReprocessFeelingsButton = 'Score again';
const kReprocessFeelingsDone = 'Feelings scored again for this reply.';
const kReprocessFeelingsFailed =
    "The model's answer couldn't be read, so this reply keeps the feelings "
    'it had. You can try again.';
const kReprocessFeelingsRefused = "This reply can't be scored again right now.";

String reprocessFeelingsIntro(String name) =>
    'Ask the model again how $name feels about your last message. This '
    "reply's bond, trust and mood are replaced, not added on top. The reply "
    'itself stays as it is.';

enum ReprocessChoice { needs, feelings }

/// "Manual Reprocess" — redo a reply's Needs (critique the outcome and have
/// the Realism Director re-evaluate it) or its Feelings (the Realism judges
/// asked again about the user's line).
///
/// The Needs chips list only the speaker's enabled needs. Nothing selected
/// means every need shown here; ticking narrows the pass so the rest keep
/// the deltas they already had. Both targets are read when the dialog
/// builds, so a stale sheet sees a flip off.
void showReprocessNeedsDialog(BuildContext context, int index) {
  final chatService = Provider.of<ChatService>(context, listen: false);
  final host = context;
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) {
    if (!host.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  showDialog(
    context: context,
    builder: (context) => ReprocessNeedsDialog(
      index: index,
      onSubmit: (text, scope) async {
        var success = false;
        try {
          success = await chatService.manualReprocessNeeds(
            index,
            text,
            onlyNeeds: scope,
          );
        } catch (e) {
          debugPrint('[Realism:Needs] reprocess error: $e');
        }
        say(
          success
              ? (scope.isEmpty
                    ? 'Needs deltas reprocessed with your critique.'
                    : 'Reprocessed ${scope.join(', ')} with your critique.')
              : 'Reprocess received no response from the model. Original deltas preserved.',
        );
      },
      onSubmitFeelings: () async {
        var result = FeelingsRescore.unreadable;
        try {
          result = await chatService.reprocessFeelings(index);
        } catch (e) {
          debugPrint('[Realism:Rescore] error: $e');
        }
        say(switch (result) {
          FeelingsRescore.scored => kReprocessFeelingsDone,
          FeelingsRescore.refused => kReprocessFeelingsRefused,
          FeelingsRescore.unreadable => kReprocessFeelingsFailed,
        });
      },
    ),
  );
}

/// The Manual Reprocess sheet. [showReprocessNeedsDialog] hosts this; tests
/// pump it with a [ChatService] so the resolvers are a fresh read.
class ReprocessNeedsDialog extends StatefulWidget {
  const ReprocessNeedsDialog({
    super.key,
    required this.index,
    required this.onSubmit,
    this.onSubmitFeelings,
  });

  final int index;
  final Future<void> Function(String critique, Set<String> onlyNeeds) onSubmit;

  /// Null hides the Feelings choice.
  final Future<void> Function()? onSubmitFeelings;

  @override
  State<ReprocessNeedsDialog> createState() => _ReprocessNeedsDialogState();
}

class _ReprocessNeedsDialogState extends State<ReprocessNeedsDialog> {
  final _controller = TextEditingController();
  final _selected = <String>{};
  ReprocessChoice? _picked;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final chat = Provider.of<ChatService>(context, listen: false);
    final enabled =
        chat.reprocessNeedsTargetFor(widget.index)?.enabled ?? const <String>[];
    final scope = enabled.length == 1
        ? <String>{}
        : Set.of(_selected.where(enabled.contains));
    Navigator.of(context).pop();
    await widget.onSubmit(text, scope);
  }

  Future<void> _submitFeelings() async {
    Navigator.of(context).pop();
    await widget.onSubmitFeelings?.call();
  }

  @override
  Widget build(BuildContext context) {
    final chat = Provider.of<ChatService>(context);
    final target = chat.reprocessNeedsTargetFor(widget.index);
    final enabled = target?.enabled ?? const <String>[];
    _selected.removeWhere((need) => !enabled.contains(need));
    final needsOk = target != null && enabled.isNotEmpty;
    final feelingsName = widget.onSubmitFeelings == null
        ? null
        : chat.reprocessFeelingsTargetFor(widget.index);
    final feelingsOk = feelingsName != null;
    final choice = switch (_picked) {
      ReprocessChoice.needs when needsOk => ReprocessChoice.needs,
      ReprocessChoice.feelings when feelingsOk => ReprocessChoice.feelings,
      _ when needsOk => ReprocessChoice.needs,
      _ when feelingsOk => ReprocessChoice.feelings,
      _ => null,
    };
    final feelings = choice == ReprocessChoice.feelings;
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      title: Text(
        feelings ? kReprocessFeelingsTitle : 'Reprocess Needs Deltas',
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: choice == null
              ? Text(
                  kReprocessNeedsNothing,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 13,
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (needsOk && feelingsOk) _choiceRow(context, choice),
                    if (feelings)
                      Text(
                        reprocessFeelingsIntro(feelingsName!),
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 13,
                        ),
                      )
                    else
                      _enabledBody(context, target!.enabled, target.speaker),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            choice == null ? 'Close' : 'Cancel',
            style: TextStyle(color: AppColors.textTertiary(context)),
          ),
        ),
        if (choice != null)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.porchAmberOf(context),
              foregroundColor: AppColors.onChaosAccent,
            ),
            onPressed: () => feelings ? _submitFeelings() : _submit(),
            child: Text(feelings ? kReprocessFeelingsButton : 'Reprocess'),
          ),
      ],
    );
  }

  Widget _choiceRow(BuildContext context, ReprocessChoice choice) {
    Widget option(ReprocessChoice value, String label) {
      final on = choice == value;
      return ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: on
                ? AppColors.onChaosAccent
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kReprocessChoicePrompt,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              option(ReprocessChoice.needs, kReprocessChoiceNeeds),
              option(ReprocessChoice.feelings, kReprocessChoiceFeelings),
            ],
          ),
        ],
      ),
    );
  }

  Widget _enabledBody(
    BuildContext context,
    List<String> enabled,
    String speaker,
  ) {
    final one = enabled.length == 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kReprocessNeedsIntro,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _controller,
          maxLines: 5,
          minLines: 2,
          style: TextStyle(color: AppColors.textPrimary(context)),
          decoration: InputDecoration(
            hintText: kReprocessNeedsHint,
            hintStyle: TextStyle(color: AppColors.textTertiary(context)),
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (one) ...[
          const SizedBox(height: 16),
          Text(
            reprocessNeedsOneEnabledLine(enabled.first, speaker),
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
        ] else ...[
          const SizedBox(height: 16),
          Text(
            'Limit to these needs',
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _selected.isEmpty
                ? kReprocessNeedsEmptyHelper
                : kReprocessNeedsSomeHelper,
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final need in enabled)
                FilterChip(
                  label: Text(
                    needTitle(need),
                    style: TextStyle(
                      fontSize: 12,
                      color: _selected.contains(need)
                          ? AppColors.onChaosAccent
                          : AppColors.textSecondary(context),
                    ),
                  ),
                  selected: _selected.contains(need),
                  showCheckmark: false,
                  backgroundColor: AppColors.surfaceContainerOf(context),
                  selectedColor: AppColors.porchAmberOf(context),
                  side: BorderSide(color: AppColors.borderOf(context)),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _selected.add(need);
                    } else {
                      _selected.remove(need);
                    }
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
