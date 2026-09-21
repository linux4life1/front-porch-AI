// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';
import 'package:front_porch_ai/ui/settings/widgets/remote_provider_bar.dart';

void main() {
  testWidgets('one row of hosts; oMLX omitted unless showOmlx', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RemoteProviderBar(
            selected: RemoteProviderKind.openRouter,
            onSelected: _noop,
          ),
        ),
      ),
    );

    expect(find.text('KoboldCpp'), findsOneWidget);
    expect(find.text('OpenRouter'), findsOneWidget);
    expect(find.text('Nano-GPT'), findsOneWidget);
    expect(find.text('LM Studio'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('oMLX'), findsNothing);
    expect(find.text('Local'), findsNothing);
    expect(find.text('Remote API'), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RemoteProviderBar(
            selected: RemoteProviderKind.omlx,
            showOmlx: true,
            onSelected: _noop,
          ),
        ),
      ),
    );
    expect(find.text('oMLX'), findsOneWidget);
  });
}

void _noop(RemoteProviderKind _) {}
