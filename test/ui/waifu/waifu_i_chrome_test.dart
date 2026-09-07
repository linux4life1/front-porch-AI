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
import 'package:front_porch_ai/ui/waifu/waifu_language_help.dart';
import 'package:front_porch_ai/ui/waifu/waifu_page.dart';

void main() {
  testWidgets('Language help lists doors off; none pre-ticked', (tester) async {
    final langs = WaifuLangRuntime(directory: '/tmp/waifu-lang-test');
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuLanguageHelp(langs: langs, suggested: const {'gdscript'}),
      ),
    );
    expect(find.textContaining('GDScript'), findsOneWidget);
    expect(find.textContaining('Rust'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('waifu-lang-holy_c')),
      400,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.textContaining('Holy C'), findsOneWidget);
    final switches = tester.widgetList<Switch>(find.byType(Switch));
    expect(switches, isNotEmpty);
    expect(switches.every((s) => s.value == false), isTrue);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('session chrome has Language help; no Continue or Regen', (
    tester,
  ) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    expect(find.byKey(const Key('waifu-language-help')), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Regenerate'), findsNothing);
  });
}
