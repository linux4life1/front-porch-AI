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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_wizard_sit_down_step.dart';

void main() {
  testWidgets('AppBar always shows mode, scope badge, basename, and path', (
    tester,
  ) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
      mode: WaifuMode.plan,
      pathMode: WaifuPathMode.folderJail,
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));

    expect(find.byKey(const Key('waifu-session-chrome')), findsOneWidget);
    expect(find.byKey(const Key('waifu-appbar-mode')), findsOneWidget);
    expect(find.byKey(const Key('waifu-appbar-scope')), findsOneWidget);
    expect(find.byKey(const Key('waifu-appbar-path')), findsOneWidget);
    expect(find.text('Plan'), findsWidgets);
    expect(find.text('throwaway-waifu'), findsOneWidget);
    expect(find.text('/tmp/throwaway-waifu'), findsOneWidget);
    // AppBar receipt is Jail. Sidebar chips show both labels on purpose.
    expect(
      find.descendant(
        of: find.byKey(const Key('waifu-appbar-scope')),
        matching: find.text('Jail'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('waifu-appbar-scope')),
        matching: find.text('Disk'),
      ),
      findsNothing,
    );
  });

  testWidgets('whole-disk AppBar shows Disk, not Jail', (tester) async {
    final session = WaifuSession(
      folderRoot: '/tmp/roam-porch',
      coworker: CharacterCard(name: 'Iris'),
      pathMode: WaifuPathMode.wholeDisk,
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    expect(
      find.descendant(
        of: find.byKey(const Key('waifu-appbar-scope')),
        matching: find.text('Disk'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('waifu-appbar-scope')),
        matching: find.text('Jail'),
      ),
      findsNothing,
    );
    expect(find.text('Build'), findsWidgets);
  });

  testWidgets('honesty body renders ** as weight, not sludge', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WaifuHonestyText(
            text: '**Folder jail is the safer default.** Keep a backup.',
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('waifu-honesty-body')), findsOneWidget);
    expect(
      find.textContaining('Folder jail is the safer default.'),
      findsOneWidget,
    );
    expect(find.textContaining('**'), findsNothing);
    final rich = tester.widget<Text>(
      find.byKey(const Key('waifu-honesty-body')),
    );
    final span = rich.textSpan;
    expect(span, isA<TextSpan>());
    final root = span! as TextSpan;
    expect(root.children, isNotNull);
    expect(root.children, isNotEmpty);
    final first = root.children!.first;
    expect(first, isA<TextSpan>());
    final bold = first as TextSpan;
    expect(bold.style?.fontWeight, FontWeight.w800);
    expect(bold.text, 'Folder jail is the safer default.');
  });

  testWidgets('multi-file turn receipt lists every touched path plus verify', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaifuWorkStrip(
            record: const WaifuWriteRecord(
              relativePath: 'lib/b.dart',
              before: 'old b',
              after: 'new b',
            ),
            writes: const [
              WaifuWriteRecord(
                relativePath: 'lib/a.dart',
                before: 'old a',
                after: 'new a',
              ),
              WaifuWriteRecord(
                relativePath: 'lib/b.dart',
                before: 'old b',
                after: 'new b',
              ),
            ],
            verifiedPaths: const ['lib/a.dart', 'lib/b.dart'],
          ),
        ),
      ),
    );
    expect(find.text('2 files this turn'), findsOneWidget);
    expect(find.byKey(const Key('waifu-work-strip-files')), findsOneWidget);
    expect(find.text('lib/a.dart'), findsOneWidget);
    expect(find.text('lib/b.dart'), findsWidgets);
    expect(find.text('Verified: lib/a.dart, lib/b.dart'), findsOneWidget);
  });

  testWidgets('toolsSupported false shows the fail-closed banner', (
    tester,
  ) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Mira'),
      toolsSupported: false,
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    expect(
      find.byKey(const Key('waifu-tools-unsupported-banner')),
      findsOneWidget,
    );
    expect(find.textContaining('cannot do Waifu Coder'), findsOneWidget);
  });

  testWidgets('sit-down recap shows Jail and Disk badges for the scope', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaifuWizardSitDownStep(
            folderPath: '/tmp/porch',
            coworker: CharacterCard(name: 'Mira'),
            backendLabel: 'remote',
            isLocalBackend: false,
            toolsSupported: true,
            mode: WaifuMode.build,
            pathMode: WaifuPathMode.folderJail,
            honestyAccepted: false,
            onModeChanged: (_) {},
            onPathModeChanged: (_) {},
            onHonestyChanged: (_) {},
            onConfirm: () {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('waifu-sit-down-mode')), findsOneWidget);
    expect(find.byKey(const Key('waifu-sit-down-scope')), findsOneWidget);
    expect(find.text('Jail'), findsOneWidget);
    // Sit-down is a lazy ListView; honesty lives below the fold (same as
    // waifu_wizard_test scrolling to the checkbox / confirm).
    final honesty = find.byKey(const Key('waifu-honesty-body'));
    await tester.scrollUntilVisible(honesty, 300);
    expect(honesty, findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
  });
}
