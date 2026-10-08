// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// A desktop route out of a phone-owned pack without taking its ownership.
class OtherExpressionPack extends StatelessWidget {
  const OtherExpressionPack({super.key, required this.owned});

  final bool Function(PackRun) owned;

  Future<void> _discard(BuildContext context, PackRun run) async {
    final discard = await showWarmDialog<bool>(
      context,
      title: 'Discard phone expression pack?',
      icon: Icons.delete_outline,
      content: WarmDialogText(
        'Discard the unimported results for ${run.characterName}? Imported expressions remain in the library.',
      ),
      actions: [
        warmDialogCancel(context, label: 'Keep pack'),
        warmDialogConfirm(
          context,
          label: 'Discard',
          destructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (discard != true || !context.mounted) return;
    if (!identical(expressionPackBoard.run, run) ||
        run.importing ||
        run.session.isRunning ||
        context.read<ImageGenService>().isGenerating) {
      return;
    }
    expressionPackBoard.clear();
  }

  @override
  Widget build(BuildContext context) {
    final imageBusy = context.watch<ImageGenService>().isGenerating;
    return ListenableBuilder(
      listenable: expressionPackBoard,
      builder: (context, _) {
        final run = expressionPackBoard.run;
        if (run == null || owned(run)) return const SizedBox.shrink();
        final running = run.session.isRunning;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${run.characterName}: another ${run.origin == PackOrigin.phone ? 'phone' : 'desktop'} screen has an expression pack.',
              ),
              Text(
                run.importing
                    ? 'Importing…'
                    : running
                    ? 'Generating…'
                    : 'Pack stopped.',
              ),
              if (run.origin == PackOrigin.phone) ...[
                TextButton(
                  onPressed: run.importing
                      ? null
                      : running
                      ? run.session.cancel
                      : imageBusy
                      ? null
                      : () => _discard(context, run),
                  child: Text(
                    running ? 'Stop phone pack' : 'Discard phone pack',
                  ),
                ),
                const Text(
                  'Import or continue its results on the phone, or discard them here to start a new pack.',
                ),
              ] else
                const Text(
                  'Import or discard it in the desktop screen that started it.',
                ),
            ],
          ),
        );
      },
    );
  }
}
