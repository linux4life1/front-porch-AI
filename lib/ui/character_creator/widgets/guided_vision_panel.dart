// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// AI "Character Vision" panel for the guided creator. Lets the user write
/// their vision freeform, drop in scenario seeds, or have the AI generate a
/// description from the structured details above. Extracted verbatim from
/// `GuidedConfigStep` to keep that step under the file-size cap.
class GuidedVisionPanel extends StatelessWidget {
  final CreatorState state;

  const GuidedVisionPanel({super.key, required this.state});

  void _save() {
    state.saveState();
    state.notify();
  }

  /// Typing: redraw at once (the length tip reads the text), save on pause.
  void _saveSoon() {
    state.scheduleSave();
    state.notify();
  }

  Future<void> _expandNarrative(BuildContext context) async {
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    final result = await state.expandNarrative(
      llmProvider: llmProvider,
      storage: storage,
    );
    if (result == null || !context.mounted) return;

    final amber = StudioColors.amberOf(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.raiseOf(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.auto_fix_high, color: amber, size: 22),
            const SizedBox(width: 8),
            Text(
              'Generated Description',
              style: TextStyle(color: StudioColors.inkOf(ctx), fontSize: 18),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AI generated this description from your details:',
                  style: TextStyle(
                    color: StudioColors.mutedOf(ctx),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: StudioColors.raiseOf(ctx),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: amber.withValues(alpha: 0.3)),
                  ),
                  child: SelectableText(
                    result,
                    style: TextStyle(
                      color: StudioColors.proseOf(ctx),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This will replace the current vision text. You can edit it after.',
                  style: TextStyle(
                    color: StudioColors.mutedOf(ctx),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Discard',
              style: TextStyle(color: StudioColors.mutedOf(ctx)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: amber),
            child: const Text('Use This'),
          ),
        ],
      ),
    );

    if (accepted == true) {
      state.guidedVisionController.text = result;
      _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    final placeholderIdx =
        state.nameController.text.hashCode.abs() %
        CreatorOptions.guidedVisionPlaceholders.length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: StudioColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StudioColors.lineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, color: amber, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Character Vision',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: StudioColors.inkOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Write your idea, or let AI generate a description from the details above.',
                      style: TextStyle(
                        fontSize: 11,
                        color: StudioColors.mutedOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: state.guidedVisionController,
            maxLines: null,
            minLines: 6,
            style: TextStyle(
              color: StudioColors.inkOf(context),
              fontSize: 14,
              height: 1.5,
            ),
            onChanged: (_) => _saveSoon(),
            decoration: InputDecoration(
              hintText: CreatorOptions.guidedVisionPlaceholders[placeholderIdx],
              hintStyle: TextStyle(
                color: StudioColors.faintOf(context),
                fontSize: 13,
              ),
              hintMaxLines: 3,
              filled: true,
              fillColor: StudioColors.bgOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: StudioColors.lineOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: StudioColors.lineOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: amber),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: CreatorOptions.scenarioSeeds.map((seed) {
              return InkWell(
                onTap: () {
                  final current = state.guidedVisionController.text.trim();
                  state.guidedVisionController.text = current.isEmpty
                      ? seed
                      : '$current. $seed';
                  state.guidedVisionController.selection =
                      TextSelection.fromPosition(
                        TextPosition(
                          offset: state.guidedVisionController.text.length,
                        ),
                      );
                  _save();
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: StudioColors.raiseOf(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: StudioColors.lineOf(context)),
                  ),
                  child: Text(
                    seed,
                    style: TextStyle(
                      color: StudioColors.mutedOf(context),
                      fontSize: 11,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Spacer(),
              if (state.isExpandingNarrative)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: amber,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Generating description...',
                        style: TextStyle(color: amber, fontSize: 12),
                      ),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: state.nameController.text.trim().isEmpty
                      ? null
                      : () => _expandNarrative(context),
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: const Text(
                    'Generate Character Description',
                    style: TextStyle(fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    // A primary button: amber fill, amber-ink label.
                    backgroundColor: StudioColors.amberOf(context),
                    foregroundColor: StudioColors.amberInkOf(context),
                    disabledBackgroundColor: StudioColors.raiseOf(context),
                    disabledForegroundColor: StudioColors.mutedOf(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
