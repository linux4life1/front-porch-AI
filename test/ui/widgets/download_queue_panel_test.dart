// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The download queue's status line ("45% — 4.5 MB/s — ETA …") was the dark
// mode sky blue at 70% in light mode too, about 1.4:1 on paper. Light mode
// now takes a deep tone per state; dark mode keeps the soft bright hue.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/download_task.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/download_queue_panel.dart';

DownloadTask _task(DownloadTaskState state) {
  final t = DownloadTask(
    url: 'https://example.invalid/model.gguf',
    filename: 'model-${state.name}.gguf',
    targetDir: '/models',
  );
  t.state = state;
  t.progress = 0.45;
  t.bytesDownloaded = 2_214_592_716;
  t.totalBytes = 4_920_000_000;
  t.speedBytesPerSec = 4_718_592;
  return t;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

const _coloured = [
  DownloadTaskState.downloading,
  DownloadTaskState.paused,
  DownloadTaskState.verifying,
];

Future<Map<DownloadTaskState, Color>> _statusInks(
  WidgetTester tester,
  Brightness brightness,
) async {
  final tasks = [for (final s in _coloured) _task(s)];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(brightness: brightness),
      home: Scaffold(
        body: SingleChildScrollView(
          child: DownloadQueuePanel(
            activeDownloads: tasks,
            pendingDownloads: const [],
            overallProgress: 0.45,
            overallSpeed: 4_718_592,
            onPause: (_) {},
            onResume: (_) {},
            onCancel: (_) {},
            onPauseAll: () {},
            onResumeAll: () {},
          ),
        ),
      ),
    ),
  );
  return {
    for (final t in tasks)
      t.state: tester.widget<Text>(find.text(t.statusString)).style!.color!,
  };
}

void main() {
  testWidgets('light-mode status lines clear 4.5:1 on the surface and card', (
    tester,
  ) async {
    final inks = await _statusInks(tester, Brightness.light);
    final context = tester.element(find.byType(DownloadQueuePanel));
    final grounds = [AppColors.surfaceOf(context), AppColors.cardOf(context)];
    final faint = [
      for (final e in inks.entries)
        for (final g in grounds)
          if (_contrast(e.value, g) < 4.5)
            '${e.key.name} ${_contrast(e.value, g).toStringAsFixed(2)}',
    ];
    expect(faint, isEmpty);
  });

  testWidgets('dark-mode status lines keep the soft bright hue', (
    tester,
  ) async {
    final inks = await _statusInks(tester, Brightness.dark);
    expect(inks, {
      DownloadTaskState.downloading: DownloadStatusColors.downloading
          .withValues(alpha: 0.7),
      DownloadTaskState.paused: DownloadStatusColors.paused.withValues(
        alpha: 0.7,
      ),
      DownloadTaskState.verifying: DownloadStatusColors.verifying.withValues(
        alpha: 0.7,
      ),
    });
  });
}
