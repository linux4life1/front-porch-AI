// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'kobold_speed_test_dialog.dart';

/// The Local model card's speed test, in auto mode: the button, why it
/// cannot run now, and how the last test of [model] ended. Auto mode shows
/// outcome words only, so nothing here names a setting.
class KoboldSpeedTestButton extends StatefulWidget {
  const KoboldSpeedTestButton({
    super.key,
    required this.test,
    required this.model,
    required this.phase,
  });

  final KoboldSpeedTest test;
  final String model;

  /// The engine's phase: why the test cannot run is asked again when it
  /// changes, as when the model finishes loading.
  final KoboldPhase phase;

  @override
  State<KoboldSpeedTestButton> createState() => _KoboldSpeedTestButtonState();
}

class _KoboldSpeedTestButtonState extends State<KoboldSpeedTestButton> {
  String? _why;
  bool _wasRunning = false;

  /// Which ask is the latest: an older answer that lands late is dropped.
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    _wasRunning = widget.test.running;
    widget.test.addListener(_onTest);
    _askWhy();
  }

  @override
  void didUpdateWidget(KoboldSpeedTestButton old) {
    super.didUpdateWidget(old);
    if (!identical(old.test, widget.test)) {
      old.test.removeListener(_onTest);
      widget.test.addListener(_onTest);
    }
    if (old.phase != widget.phase || old.model != widget.model) _askWhy();
  }

  @override
  void dispose() {
    widget.test.removeListener(_onTest);
    super.dispose();
  }

  void _onTest() {
    final running = widget.test.running;
    if (running != _wasRunning) {
      _wasRunning = running;
      _askWhy();
    }
    if (mounted) setState(() {});
  }

  void _askWhy() {
    final ticket = ++_asked;
    unawaited(
      widget.test.why().then((why) {
        if (mounted && ticket == _asked) setState(() => _why = why);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.test;
    final why = t.running ? null : _why;
    final line = t.running ? null : t.lineFor(widget.model);
    final muted = AppColors.slateMutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        KeButton(
          t.running
              ? 'Testing speed settings…'
              : 'Find the fastest settings for this computer',
          key: const ValueKey('local-model-speed-test'),
          kind: KeButtonKind.amberOutline,
          onPressed: why != null ? null : () => showKoboldSpeedTest(context, t),
        ),
        if (why != null) ...[
          const SizedBox(height: 6),
          Text(
            why,
            key: const ValueKey('local-model-speed-test-why'),
            style: keText(context, size: 13, color: muted),
          ),
        ],
        if (line != null) ...[
          const SizedBox(height: 8),
          Text(
            line,
            key: const ValueKey('local-model-speed-test-line'),
            style: keText(context, size: 14, height: 1.45),
          ),
        ],
      ],
    );
  }
}
