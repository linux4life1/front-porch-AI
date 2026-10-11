// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Files dropped on the real HomePage go through the same importers as the
// pickers: a card dropped on the empty library lands in the library, a
// .byaf dropped on the grid reaches the Backyard importer, and anything
// else is turned away with a reason. The drop enters at
// HomeDropZone.debugDrop, the step after the OS hands over paths (an OS
// drag cannot run here). Proven red by unwrapping either drop zone in
// home_page.dart and by cutting the PNG / .byaf hand-offs and the
// rejection snack in home_page_drop.dart. The mixed drop was proven red by
// starting the bulk import inside the progress dialog's build again (the
// repository's notify then throws during build).

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/home_drop_zone.dart';

import 'home_page_harness.dart';

void main() {
  late HomeRig rig;
  late Directory downloads;

  Future<HomeRig> library(
    WidgetTester tester, [
    Future<void> Function(AppDatabase db)? seed,
  ]) async {
    rig = await HomeRig.build(tester, seed: seed);
    await tester.runAsync(() async {
      downloads = await Directory(p.join(rig.root.path, 'Downloads')).create();
    });
    await rig.pump(tester);
    return rig;
  }

  /// A real character card PNG in the downloads folder.
  Future<String> cardFile(WidgetTester tester, String name) async {
    final path = p.join(downloads.path, '$name.png');
    await tester.runAsync(
      () => V2CardService().saveCardAsPng(
        CharacterCard(name: name, description: 'Dropped in.'),
        path,
        null,
      ),
    );
    return path;
  }

  Future<String> junkFile(WidgetTester tester, String name) async {
    final path = p.join(downloads.path, name);
    await tester.runAsync(() => File(path).writeAsString('not a card'));
    return path;
  }

  void drop(WidgetTester tester, List<String> paths) {
    final zone = tester.state<HomeDropZoneState>(find.byType(HomeDropZone));
    unawaited(
      zone.debugDrop([
        for (final path in paths)
          HomeDropSource(label: p.basename(path), path: path),
      ]),
    );
  }

  /// Lets real file and database work run until [finder] shows.
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(finder, findsWidgets);
  }

  bool inLibrary(String name) =>
      rig.characters.characters.any((c) => c.name == name);

  testWidgets('a card dropped on the empty library is imported', (
    tester,
  ) async {
    await library(tester);
    expect(find.text('Get started by creating a new character!'), findsOne);

    drop(tester, [await cardFile(tester, 'Dot')]);
    await waitFor(tester, find.text('Save Tags'));
    await tester.tap(find.text('Save Tags'));
    await waitFor(tester, find.text('Character imported successfully!'));

    expect(inLibrary('Dot'), isTrue);
    expect(find.text('Dot'), findsWidgets, reason: 'the grid shows the card');
  });

  testWidgets('a .byaf dropped on the grid goes to the Backyard importer', (
    tester,
  ) async {
    await library(tester, (db) => seedCharacter(db, 'Ada', 'Ada.png'));
    expect(find.text('Ada'), findsWidgets);

    drop(tester, [await junkFile(tester, 'broken.byaf')]);
    await waitFor(tester, find.textContaining('Failed to import .byaf'));

    expect(rig.characters.characters.map((c) => c.name), ['Ada']);
  });

  testWidgets('a file that is not a card is turned away with a reason', (
    tester,
  ) async {
    await library(tester, (db) => seedCharacter(db, 'Ada', 'Ada.png'));

    drop(tester, [await junkFile(tester, 'notes.txt')]);
    await waitFor(tester, find.textContaining("Can't import \"notes.txt\""));

    expect(rig.characters.characters.map((c) => c.name), ['Ada']);
  });

  testWidgets('a card and a .byaf dropped together run as one batch', (
    tester,
  ) async {
    await library(tester, (db) => seedCharacter(db, 'Ada', 'Ada.png'));

    drop(tester, [
      await cardFile(tester, 'Dot'),
      await junkFile(tester, 'broken.byaf'),
    ]);
    await waitFor(tester, find.text('Import dropped files'));
    await waitFor(tester, find.text('Imported 1 character (1 failed)'));

    expect(inLibrary('Dot'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
