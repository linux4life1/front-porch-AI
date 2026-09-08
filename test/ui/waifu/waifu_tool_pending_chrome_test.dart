// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

void main() {
  testWidgets('running chip shows a pending spinner, not a pass/fail dot', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaifuToolLog(
            chips: const [
              WaifuToolChip(
                name: 'todowrite',
                detail: '1 items',
                ok: false,
                running: true,
              ),
              WaifuToolChip(name: 'bash', detail: 'ls', ok: true),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('waifu-tool-pending-0')), findsOneWidget);
    expect(find.byKey(const Key('waifu-tool-pending-1')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('todowrite'), findsOneWidget);
    expect(find.text('bash'), findsOneWidget);
  });
}
