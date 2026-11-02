// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The desktop toast for a chat-model switch (issue 686): the switch loads
// the new model's linked preset, the toast names it once, and Undo puts the
// previous values back.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/widgets/gen_presets/gen_presets.dart';

import '../gen_preset_storage.dart';

void main() {
  testWidgets('a model switch toasts once and Undo restores the values', (
    tester,
  ) async {
    final storage = await GenPresetStorage.create();
    final g = storage.generationSettings;
    await g.setTemperature(0.7);
    await storage.genPresets.savePreset(
      'Precise',
      const SamplerValues(temperature: 0.2, minP: 0.3),
    );
    const next = '/models/Mistral-Small.gguf';
    await storage.genPresets.link(ChatModelId.local(next).key, 'Precise');
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: const MaterialApp(home: Scaffold(body: GenPresetNoticeToast())),
      ),
    );

    await storage.backendSettings.setLastUsedModelPath(next);
    await tester.pump(const Duration(milliseconds: 1)); // the model settles
    await tester.pump();
    await tester.pump();
    expect(g.temperature, 0.2);
    expect(find.text('Mistral-Small writes with “Precise”.'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump();
    expect(g.temperature, 0.7);
    expect(g.minP, 0.1);
    expect(storage.follower.notice.value, isNull);
  });
}
