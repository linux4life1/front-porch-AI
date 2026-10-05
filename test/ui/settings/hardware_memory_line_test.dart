// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Settings → Advanced → Hardware & GPU had a memory bar of its own: the whole
// model file plus a rough cost for each token of chat. It left out sliding
// window, flash attention, the working memory and the engine's own share, so
// it disagreed with the Local model card, which works the same model out
// exactly (as the preset editor does). One model, two numbers. The bar is
// retired: the section keeps the graphics card's name and its memory, and
// says where the estimate is.
//
// The real Settings page (see settings_page_harness.dart), with a model
// chosen on a 6 GB card.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';

import '../../golden/support/fakes.dart';
import '../../helpers/settings_page_harness.dart';

class _IntelMac extends ReadyBackendManager {
  _IntelMac(super.exe);

  @override
  bool get isIntelMac => true;
}

void main() {
  const pointer =
      'The Local model card, on the Backend tab, shows how your model and '
      'its chat fit in this memory.';

  /// What the old bar printed under itself: "Model ~4520 MB", "Context ~800
  /// MB", "Free ~824 MB", "5320 / 6144 MB used", and for a remote service
  /// "Total 6144 MB".
  final oldFigures = find.textContaining(
    RegExp(r'MB used|^(Model|Context|Free) ~\d|^Total \d+ MB'),
  );

  /// The Settings page over the harness's two models, with [llm] or
  /// [backend] in place of the rig's own when given.
  Future<void> mount(
    WidgetTester tester, {
    LLMProvider? llm,
    BackendManager? backend,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rig = await buildRig(tester, lastUsedIsB: true);
    Widget page = const MaterialApp(home: SettingsPage());
    if (llm != null) {
      page = ChangeNotifierProvider<LLMProvider>.value(value: llm, child: page);
    }
    if (backend != null) {
      page = ChangeNotifierProvider<BackendManager>.value(
        value: backend,
        child: page,
      );
    }
    await tester.pumpWidget(withRigProviders(rig, child: page));
    await settle(tester);
    await openTab(tester, 'Advanced');
  }

  testWidgets('with KoboldCpp the section names the card and its memory, '
      'and points to the Local model card for the estimate', (tester) async {
    await mount(tester);

    expect(find.text('NVIDIA GeForce GTX 1060 6GB'), findsOneWidget);
    expect(find.text('6 GB of graphics memory.'), findsOneWidget);
    expect(find.text(pointer), findsOneWidget);
  });

  testWidgets('the old bar is gone, and every figure it printed with it', (
    tester,
  ) async {
    await mount(tester);

    expect(find.text('Hardware & GPU'), findsOneWidget);
    expect(oldFigures, findsNothing);
  });

  testWidgets('with a remote service the card is not in use, and there is '
      'no estimate to point to', (tester) async {
    await mount(
      tester,
      llm: FakeLLMProvider(activeBackend: BackendType.openRouter),
    );

    expect(find.text('NVIDIA GeForce GTX 1060 6GB'), findsOneWidget);
    expect(find.text('6 GB of graphics memory.'), findsOneWidget);
    expect(find.text('Remote API — GPU not in use'), findsOneWidget);
    expect(find.text(pointer), findsNothing);
    expect(oldFigures, findsNothing);
  });

  testWidgets('on an Intel Mac, which has no Local model card, nothing points '
      'to one', (tester) async {
    await mount(tester, backend: _IntelMac('koboldcpp'));

    expect(find.text('6 GB of graphics memory.'), findsOneWidget);
    expect(find.text(pointer), findsNothing);
  });
}
