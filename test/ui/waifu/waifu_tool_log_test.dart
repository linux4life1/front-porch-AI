// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

void main() {
  testWidgets('tool log stacks rows instead of wrapping chips', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaifuToolLog(
            chips: const [
              WaifuToolChip(name: 'bash', detail: 'ls -la', ok: true),
              WaifuToolChip(name: 'bash', detail: 'pwd', ok: true),
              WaifuToolChip(name: 'write', detail: 'lib/main.dart', ok: true),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('waifu-tool-log')), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
    expect(find.byKey(const Key('waifu-tool-row-0')), findsOneWidget);
    expect(find.byKey(const Key('waifu-tool-row-2')), findsOneWidget);
    expect(find.text('bash'), findsNWidgets(2));
    expect(find.text('ls -la'), findsOneWidget);
  });
}
