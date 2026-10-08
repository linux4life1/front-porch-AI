// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';

const String _title = 'Find the fastest settings';

/// The speed test in one warm dialog: it asks first, with how long it takes,
/// then shows the test running (a progress bar, the step, the time left and
/// what it does, with Cancel), then the one line it ended with. A test
/// already running is shown at once. Nothing on it names a setting.
Future<void> showKoboldSpeedTest(
  BuildContext context,
  KoboldSpeedTest test,
) async {
  if (!test.running) {
    final asked = await test.ask();
    if (!context.mounted) return;
    final refusal = asked.refusal;
    if (refusal != null) return _say(context, refusal);
    final run = await showWarmDialog<bool>(
      context,
      title: _title,
      accent: AppColors.porchAmberOf(context),
      width: 440,
      content: Text(
        asked.ask!,
        key: const ValueKey('speed-test-ask'),
        style: keText(context, size: 14, height: 1.45),
      ),
      actions: [
        KeButton(
          'Not now',
          key: const ValueKey('speed-test-not-now'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        KeButton(
          'Run it',
          key: const ValueKey('speed-test-run'),
          kind: KeButtonKind.amber,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (run != true || !context.mounted) return;
    final refused = await test.start();
    if (!context.mounted) return;
    if (refused != null) return _say(context, refused);
  }
  await showWarmDialog<void>(
    context,
    title: _title,
    accent: AppColors.porchAmberOf(context),
    width: 440,
    barrierDismissible: false,
    content: KoboldSpeedTestProgress(test: test),
  );
}

/// Why it cannot run, with Close.
Future<void> _say(BuildContext context, String words) => showWarmDialog<void>(
  context,
  title: _title,
  accent: AppColors.porchAmberOf(context),
  width: 440,
  content: Text(
    words,
    key: const ValueKey('speed-test-refused'),
    style: keText(context, size: 14, height: 1.45),
  ),
  actions: [KeButton('Close', onPressed: () => Navigator.of(context).pop())],
);

/// The running test, then how it ended, following [test] as it changes.
class KoboldSpeedTestProgress extends StatelessWidget {
  const KoboldSpeedTestProgress({super.key, required this.test});

  final KoboldSpeedTest test;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: test,
    builder: (context, _) => test.running
        ? _running(context)
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                test.line ?? '',
                key: const ValueKey('speed-test-line'),
                style: keText(context, size: 15, height: 1.45),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: KeButton(
                  'Done',
                  key: const ValueKey('speed-test-done'),
                  kind: KeButtonKind.amber,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
  );

  Widget _running(BuildContext context) {
    final steps = test.steps;
    final muted = AppColors.slateMutedOf(context);
    final left = koboldAboutWords(test.left);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            key: const ValueKey('speed-test-progress'),
            value: steps == 0 ? null : (test.step - 1).clamp(0, steps) / steps,
            minHeight: 8,
            color: AppColors.porchAmberOf(context),
            backgroundColor: AppColors.insetPanelOf(context),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              steps == 0 ? 'Getting ready' : 'Step ${test.step} of $steps',
              key: const ValueKey('speed-test-step'),
              style: keText(context, size: 14, weight: FontWeight.w600),
            ),
            const Spacer(),
            if (steps > 0)
              Text(
                '${left[0].toUpperCase()}${left.substring(1)} left',
                key: const ValueKey('speed-test-left'),
                style: keText(context, size: 14, color: muted),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          test.doing,
          key: const ValueKey('speed-test-doing'),
          style: keText(context, size: 14, height: 1.45),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerRight,
          child: KeButton(
            'Cancel',
            key: const ValueKey('speed-test-cancel'),
            onPressed: test.phase == KoboldSpeedPhase.stopping
                ? null
                : test.cancel,
          ),
        ),
      ],
    );
  }
}
