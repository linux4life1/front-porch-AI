// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

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

    final teal = AppColors.resolve(
      context,
      Colors.tealAccent,
      const Color(0xFF0D7377),
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerOf(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.auto_fix_high, color: teal, size: 22),
            const SizedBox(width: 8),
            Text(
              'Generated Description',
              style: TextStyle(color: AppColors.textPrimary(ctx), fontSize: 18),
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
                    color: AppColors.textTertiary(ctx),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerOf(ctx),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: teal.withValues(alpha: 0.3)),
                  ),
                  child: SelectableText(
                    result,
                    style: TextStyle(
                      color: AppColors.textSecondary(ctx),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This will replace the current vision text. You can edit it after.',
                  style: TextStyle(
                    color: AppColors.textTertiary(ctx),
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
              style: TextStyle(color: AppColors.textTertiary(ctx)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: teal),
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
    final teal = AppColors.resolve(
      context,
      Colors.tealAccent,
      const Color(0xFF0D7377),
    );
    final placeholderIdx =
        state.nameController.text.hashCode.abs() %
        CreatorOptions.guidedVisionPlaceholders.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.resolve(
          context,
          Colors.tealAccent.withValues(alpha: 0.08),
          Colors.teal.shade100.withValues(alpha: 0.6),
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.resolve(
            context,
            Colors.tealAccent.withValues(alpha: 0.3),
            Colors.teal.shade200.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, color: teal, size: 20),
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
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Write your idea, or let AI generate a description from the details above.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary(context),
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
              color: AppColors.textPrimary(context),
              fontSize: 14,
              height: 1.5,
            ),
            onChanged: (_) => _saveSoon(),
            decoration: InputDecoration(
              hintText: CreatorOptions.guidedVisionPlaceholders[placeholderIdx],
              hintStyle: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 13,
              ),
              hintMaxLines: 3,
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: teal),
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
                    color: AppColors.surfaceContainerOf(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderOf(context)),
                  ),
                  child: Text(
                    seed,
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
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
                          color: teal,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Generating description...',
                        style: TextStyle(color: teal, fontSize: 12),
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
                    // Filled buttons need the DARK accent as the background (so
                    // white text reads) — the opposite of borders/icons, which
                    // use the bright accent. A bright-mint fill + white text is
                    // unreadable in dark mode.
                    backgroundColor: AppColors.resolve(
                      context,
                      const Color(0xFF0D7377),
                      Colors.tealAccent,
                    ),
                    foregroundColor: AppColors.resolve(
                      context,
                      Colors.white,
                      Colors.black87,
                    ),
                    disabledBackgroundColor: AppColors.surfaceContainerOf(
                      context,
                    ),
                    disabledForegroundColor: AppColors.textTertiary(context),
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
