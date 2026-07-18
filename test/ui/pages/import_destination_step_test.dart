// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/ui/pages/import_lorebook/import_destination_step.dart';

void main() {
  Widget host({
    LoreImportDestination selected = LoreImportDestination.world,
    required ValueChanged<LoreImportDestination> onSelect,
    List<CharacterCard> characters = const [],
    Set<String> selectedIds = const {},
    void Function(String, bool)? onToggle,
    String? groupName,
    bool chatAvailable = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ImportDestinationStep(
          selected: selected,
          onSelect: onSelect,
          worldNameCtrl: TextEditingController(text: 'World'),
          worldDescCtrl: TextEditingController(),
          allCharacters: characters,
          selectedCharacterIds: selectedIds,
          onToggleCharacter: onToggle ?? (a, b) {},
          activeGroupName: groupName,
          chatAvailable: chatAvailable,
        ),
      ),
    );
  }

  testWidgets('group and chat options only appear when available',
      (tester) async {
    await tester.pumpWidget(host(onSelect: (_) {}));
    expect(find.text('New World'), findsOneWidget);
    expect(find.textContaining('This group'), findsNothing);
    expect(find.text('This chat only'), findsNothing);

    await tester.pumpWidget(host(
      onSelect: (_) {},
      groupName: 'The Vale Crew',
      chatAvailable: true,
    ));
    expect(find.text('This group — The Vale Crew'), findsOneWidget);
    expect(find.text('This chat only'), findsOneWidget);
  });

  testWidgets('selecting an option reports it; config shows when selected',
      (tester) async {
    LoreImportDestination? picked;
    final chars = [CharacterCard(name: 'Aria')..dbId = 'c1'];

    await tester.pumpWidget(host(
      onSelect: (d) => picked = d,
      characters: chars,
    ));
    // World is selected → its name field config is visible (prefilled).
    expect(find.text('World'), findsOneWidget);

    await tester.tap(find.text('Into character(s)'));
    expect(picked, LoreImportDestination.characters);

    // Re-render with characters selected destination → chips visible.
    await tester.pumpWidget(host(
      selected: LoreImportDestination.characters,
      onSelect: (_) {},
      characters: chars,
    ));
    expect(find.text('Aria'), findsOneWidget);
  });

  testWidgets('character chips toggle through the callback', (tester) async {
    final calls = <(String, bool)>[];
    final chars = [CharacterCard(name: 'Aria')..dbId = 'c1'];
    await tester.pumpWidget(host(
      selected: LoreImportDestination.characters,
      onSelect: (_) {},
      characters: chars,
      onToggle: (id, v) => calls.add((id, v)),
    ));
    await tester.tap(find.text('Aria'));
    expect(calls, [('c1', true)]);
  });
}
