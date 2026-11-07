// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Settings → Generation's preset bar (issue 686): Save as new names the live
// values and the badge follows them; an edit marks the preset edited; loading
// one puts its values back; the link switch ties it to the chat model; and a
// model card's picker links a model that is not the chat model without
// touching the live values.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/gen_presets/gen_presets.dart';

import '../../helpers/double_tap.dart';
import '../gen_preset_storage.dart';

Widget _host(StorageService storage, Widget child, {double width = 1440}) =>
    ChangeNotifierProvider<StorageService>.value(
      value: storage,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    );

String _badge(WidgetTester tester) => tester
    .widget<GenPresetBadge>(find.byKey(const ValueKey('gen-preset-badge')))
    .label;

Future<void> _saveAs(WidgetTester tester, String name) async {
  await doubleTapNoFrame(tester, find.text('Save as new…'));
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey('gen-preset-name')),
    findsOneWidget,
    reason: 'a double click opens one name dialog',
  );
  await tester.enterText(find.byKey(const ValueKey('gen-preset-name')), name);
  await doubleTapNoFrame(tester, find.widgetWithText(ElevatedButton, 'Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Save as new writes once, then edits and a load show on the '
      'badge', (tester) async {
    final storage = await GenPresetStorage.create();
    final g = storage.generationSettings;
    await tester.pumpWidget(_host(storage, const GenerationPresetBar()));
    expect(_badge(tester), 'Not saved');

    await g.setTemperature(1.2);
    await _saveAs(tester, 'Warm');

    expect(storage.genPresets.saves, 1, reason: 'one write per double click');
    expect(storage.genPresets.presets['Warm']?.temperature, 1.2);
    expect(storage.genPresets.slot, 'Warm');
    expect(_badge(tester), 'Warm');
    expect(find.text('Save to “Warm”'), findsNothing);

    await g.setTemperature(0.4);
    await tester.pump();
    expect(_badge(tester), 'Warm (edited)');
    expect(find.text('Save to “Warm”'), findsOneWidget);

    // Loading the preset from the picker puts its values back.
    await tester.tap(find.byKey(const ValueKey('gen-preset-picker-Warm')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warm').last);
    await tester.pumpAndSettle();
    expect(g.temperature, 1.2);
    expect(_badge(tester), 'Warm');
  });

  testWidgets('a name already saved is refused, so Save as new never '
      'overwrites', (tester) async {
    final storage = await GenPresetStorage.create();
    await storage.generationSettings.setTemperature(1.2);
    await storage.genPresets.savePreset('Warm', GenPresetActions(storage).live);
    await tester.pumpWidget(_host(storage, const GenerationPresetBar()));

    await storage.generationSettings.setTemperature(0.3);
    await _saveAs(tester, 'Warm');

    expect(find.textContaining('already have a preset'), findsOneWidget);
    expect(storage.genPresets.presets['Warm']?.temperature, 1.2);
  });

  testWidgets('the link switch ties the loaded preset to the chat model', (
    tester,
  ) async {
    final storage = await GenPresetStorage.create();
    final key = storage.follower.model.key;
    await tester.pumpWidget(_host(storage, const GenerationPresetBar()));
    expect(find.byKey(const ValueKey('gen-preset-link')), findsNothing);

    await _saveAs(tester, 'Warm');
    expect(
      find.text('Use this preset whenever Qwen3-8B-Q4_K_M is the chat model'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('gen-preset-link')));
    await tester.pumpAndSettle();
    expect(storage.genPresets.links[key], 'Warm');
    expect(find.text('Linked to Qwen3-8B-Q4_K_M'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gen-preset-link')));
    await tester.pumpAndSettle();
    expect(storage.genPresets.links.containsKey(key), isFalse);
  });

  testWidgets('a model card links its own model and leaves the live values '
      'alone', (tester) async {
    final storage = await GenPresetStorage.create();
    final g = storage.generationSettings;
    await g.setTemperature(1.4);
    await storage.genPresets.savePreset('Warm', GenPresetActions(storage).live);
    await g.setTemperature(0.5);
    final other = ChatModelId.local('/models/Mistral-Small.gguf').key;
    await tester.pumpWidget(
      _host(storage, ModelGenPresetPicker(modelKey: other), width: 400),
    );
    expect(find.text('None (keep current values)'), findsOneWidget);

    await tester.tap(find.text('None (keep current values)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warm').last);
    await tester.pumpAndSettle();

    expect(storage.genPresets.links[other], 'Warm');
    expect(g.temperature, 0.5, reason: 'not the chat model, nothing loads');
  });

  testWidgets('the bar fits a 400 px window', (tester) async {
    const long = 'A rather long preset name for a narrow window';
    final storage = await GenPresetStorage.create(
      rec: (_) => const RecommendedSamplers(
        SamplerValues(temperature: 0.6),
        RecommendedSource.modelFile,
      ),
    );
    await storage.generationSettings.setTemperature(1.3);
    await storage.genPresets.savePreset(long, GenPresetActions(storage).live);
    await storage.genPresets.setSlot(long);
    await storage.generationSettings.setTemperature(1.1);
    await tester.pumpWidget(
      _host(storage, const GenerationPresetBar(), width: 400),
    );
    await tester.pump();
    expect(find.text('Use recommended'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
