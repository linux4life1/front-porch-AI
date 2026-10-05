// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The desktop "Local model" card, with KoboldCpp stopped on its own. The
// card said "Stopped · not running" and nothing else, so after trying a
// model that was too big the user did not know why unless they opened the
// engine log. Now the reason, which the exit puts on the status line, is a
// line under the header while the engine is stopped. While it runs or
// loads, the status line is the loading words, which the card does not
// repeat.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/backend.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

const _why =
    'KoboldCpp ran out of graphics memory while loading the model. Try a '
    'smaller context size or a stronger cache compression.';

class _Kobold extends FakeKoboldService {
  _Kobold({
    required this.isRunning,
    this.isReady = false,
    required this.modelLoadingStatus,
  });

  @override
  final bool isRunning;
  @override
  final bool isReady;
  @override
  final String modelLoadingStatus;
}

class _Hardware extends FakeHardwareService {
  @override
  FreeMemoryMb? get freeBeforeEngine => (graphics: 23000, system: 60000);

  @override
  set freeBeforeEngine(FreeMemoryMb? value) {}
}

void main() {
  Future<void> mount(WidgetTester tester, KoboldService kobold) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(
            value: FakeStorageService(),
          ),
          ChangeNotifierProvider<KoboldService>.value(value: kobold),
          ChangeNotifierProvider<HardwareService>.value(value: _Hardware()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KoboldStatusCard(unified: false, reloadChat: () async {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder reason() => find.byKey(const ValueKey('local-model-stopped-why'));

  testWidgets('stopped on its own: the card says why, under the header', (
    tester,
  ) async {
    await mount(tester, _Kobold(isRunning: false, modelLoadingStatus: _why));

    expect(find.text('Stopped'), findsOneWidget);
    expect(reason(), findsOneWidget);
    expect(tester.widget<Text>(reason()).data, _why);
  });

  testWidgets('stopped with nothing to say: no line', (tester) async {
    await mount(tester, _Kobold(isRunning: false, modelLoadingStatus: ''));

    expect(find.text('Stopped'), findsOneWidget);
    expect(reason(), findsNothing);
  });

  testWidgets('loading or ready: the status line is not shown as a reason', (
    tester,
  ) async {
    await mount(
      tester,
      _Kobold(isRunning: true, modelLoadingStatus: 'Loading model file...'),
    );
    expect(find.text('Loading…'), findsOneWidget);
    expect(reason(), findsNothing);

    await mount(
      tester,
      _Kobold(
        isRunning: true,
        isReady: true,
        modelLoadingStatus: 'The model was not changed: it could not be read.',
      ),
    );
    expect(find.text('Ready'), findsOneWidget);
    expect(reason(), findsNothing);
  });
}
