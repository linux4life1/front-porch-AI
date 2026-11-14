// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Settings → Generation's per-value reset (issue 686): a ↺ shows beside a
// value only while it differs from the chat model's recommended value (or
// the app default where the model has none), names where that value comes
// from, and puts it back.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/tabs/tabs.dart';

import '../../golden/support/fakes.dart';
import '../gen_preset_storage.dart';

const _fromFile = 'Reset to 0.60, recommended by the model file';

Future<GenPresetStorage> _mount(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 4000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final storage = await GenPresetStorage.create(
    rec: (_) => const RecommendedSamplers(
      SamplerValues(temperature: 0.6),
      RecommendedSource.modelFile,
    ),
  );
  final phrases = TextEditingController();
  addTearDown(phrases.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: storage),
        ChangeNotifierProvider<LLMProvider>.value(value: FakeLLMProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(body: GenerationTab(bannedPhrasesController: phrases)),
      ),
    ),
  );
  await tester.pump();
  return storage;
}

void main() {
  testWidgets('↺ shows only while the value differs, and resets to the '
      'model\'s recommended value', (tester) async {
    final storage = await _mount(tester);
    final g = storage.generationSettings;
    expect(g.temperature, isNot(0.6));
    expect(find.byTooltip(_fromFile), findsOneWidget);
    // Min-P sits at the app default and the model has no value for it.
    expect(find.byTooltip('Reset to 0.10, app default'), findsNothing);

    await tester.tap(find.byTooltip(_fromFile));
    await tester.pump();
    expect(g.temperature, closeTo(0.6, 1e-9));
    expect(find.byTooltip(_fromFile), findsNothing);
  });

  testWidgets('a value the model has none for resets to the app default', (
    tester,
  ) async {
    final storage = await _mount(tester);
    final g = storage.generationSettings;
    await g.setMinP(0.3);
    await tester.pump();

    expect(find.byTooltip('Reset to 0.10, app default'), findsOneWidget);
    await tester.tap(find.byTooltip('Reset to 0.10, app default'));
    await tester.pump();
    expect(g.minP, closeTo(SamplerValues.appDefaults.minP!, 1e-9));
  });

  testWidgets('Reset all to defaults puts every sampler back', (tester) async {
    final storage = await _mount(tester);
    final g = storage.generationSettings;
    await g.setMinP(0.3);
    await g.setMaxLength(900);
    await tester.pump();

    await tester.ensureVisible(find.text('Reset all to defaults'));
    await tester.tap(find.text('Reset all to defaults'));
    await tester.pumpAndSettle();
    expect(g.temperature, closeTo(0.6, 1e-9));
    expect(g.minP, closeTo(0.1, 1e-9));
    expect(g.maxLength, SamplerValues.appDefaults.maxLength);
    expect(find.byTooltip(_fromFile), findsNothing);
  });
}
