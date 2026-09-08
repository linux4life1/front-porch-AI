// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

void main() {
  testWidgets('pending tool row shows a spinner, not a fail dot', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WaifuToolLog(
            chips: [
              WaifuToolChip(
                name: 'read',
                detail: 'notes.txt',
                ok: false,
                pending: true,
              ),
              WaifuToolChip(name: 'bash', detail: 'ls -la', ok: true),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('waifu-tool-log')), findsOneWidget);
    expect(find.byKey(const Key('waifu-tool-pending-0')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('read'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('bash'), findsOneWidget);
  });
}
