// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Advanced → Advanced Launch Options only reach the app's own
// KoboldCpp. With chat on a Custom server that was chosen and ready, the box
// said "No model loaded yet. Select a model on the Backend tab first." It now
// says the options are for the built-in engine and do not apply, and offers
// no Start button for an engine nobody uses.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import '../../helpers/settings_page_harness.dart';

const _noModel =
    'No model loaded yet. Select a model on the Backend tab first.';

Future<void> _openLaunchOptions(WidgetTester tester) async {
  await openTab(tester, 'Advanced');
  await tapVisible(tester, find.text('Advanced Launch Options'));
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}

void main() {
  testWidgets('chat on a Custom server: the options say they do not apply', (
    tester,
  ) async {
    await mountSettings(
      tester,
      lastUsedIsB: false,
      before: (rig) async {
        final b = rig.store.backendSettings;
        await b.setBackendType('openRouter');
        await b.setRemoteApiUrl('http://192.168.1.20:5001/v1');
        await b.setRemoteModelName('koboldcpp/Qwen3-30B-A3B');
      },
    );
    await _openLaunchOptions(tester);

    expect(
      find.text(
        'These options are for the built-in KoboldCpp engine. You\'re '
        'using your own AI server, so they don\'t apply.',
      ),
      findsOneWidget,
    );
    expect(find.text(_noModel), findsNothing);
    expect(find.text('Start Backend'), findsNothing);
  });

  testWidgets('chat on OpenRouter names it', (tester) async {
    await mountSettings(
      tester,
      lastUsedIsB: false,
      before: (rig) async {
        final b = rig.store.backendSettings;
        await b.setBackendType('openRouter');
        await b.setRemoteApiUrl('https://openrouter.ai/api/v1');
      },
    );
    await _openLaunchOptions(tester);
    expect(find.textContaining('You\'re using OpenRouter'), findsOneWidget);
  });

  testWidgets('a helper model on the built-in engine keeps the options live', (
    tester,
  ) async {
    await mountSettings(
      tester,
      lastUsedIsB: false,
      before: (rig) async {
        await rig.store.backendSettings.setBackendType('openRouter');
        await rig.store.setWorkerBackendType('kobold');
      },
    );
    await _openLaunchOptions(tester);
    expect(find.textContaining('don\'t apply'), findsNothing);
  });

  testWidgets('chat on the built-in engine is unchanged', (tester) async {
    await mountSettings(tester, lastUsedIsB: false);
    await _openLaunchOptions(tester);
    expect(find.textContaining('don\'t apply'), findsNothing);
    expect(find.text('Start Backend'), findsWidgets);
  });
}
