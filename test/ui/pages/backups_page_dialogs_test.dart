// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Backups & Restore asks before deleting or restoring a backup. Those two
// questions moved to the warm porch dialog; this pins that each answer does
// what it says: Cancel closes only the dialog (the Backups page stays and the
// files are untouched), Delete removes the backup, Restore puts the backup in
// place of the live database.
//
// The page is hosted inside a nested navigator, as a page opened from a
// screen with its own navigator would be. A dialog lives on the root
// navigator, so a button that pops with the PAGE's context closes the page
// instead of the dialog. The dialog's buttons must pop with its own context.
//
// Real database file, real backup files in a temp folder: no fakes.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/backup/pending_restore.dart';
import 'package:front_porch_ai/services/backup_service.dart';
import 'package:front_porch_ai/ui/pages/backups_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File backup;
  late String dbPath;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('fpai_backups_dialogs_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => tmp.path);
  });

  tearDown(() async {
    await AppDatabase.closeAndReset();
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException catch (e) {
      debugPrint('temp cleanup: $e');
    }
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({
        'root_path': p.join(tmp.path, 'root'),
        'root_path_beta': p.join(tmp.path, 'root'),
      });
      await AppDatabase.instance();
      dbPath = AppDatabase.dbFilePath!;
      final dir = Directory(p.join(p.dirname(dbPath), 'backups'))
        ..createSync(recursive: true);
      backup = File(p.join(dir.path, 'front_porch_20261010_172800.db'))
        ..writeAsBytesSync(List.filled(4096, 7));
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Navigator(
            onGenerateRoute: (_) =>
                MaterialPageRoute<void>(builder: (_) => const Text('Home')),
          ),
        ),
      ),
    );
    final nested = tester.state<NavigatorState>(find.byType(Navigator).last);
    nested.push(MaterialPageRoute<void>(builder: (_) => const BackupsPage()));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.widgetWithText(TextButton, 'Restore'), findsOneWidget);
  }

  Finder dialogButton(String label) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Delete: Cancel closes only the dialog, Delete removes it', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.byTooltip('Delete backup'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Backup?'), findsOneWidget);
    await tester.tap(dialogButton('Cancel'));
    await settle(tester);
    expect(find.text('Delete Backup?'), findsNothing);
    expect(
      find.byType(BackupsPage),
      findsOneWidget,
      reason: 'Cancel must close the dialog, not the Backups page',
    );
    expect(backup.existsSync(), isTrue);

    await tester.tap(find.byTooltip('Delete backup'));
    await tester.pumpAndSettle();
    await tester.tap(dialogButton('Delete'));
    await settle(tester);
    expect(find.text('Delete Backup?'), findsNothing);
    expect(find.byType(BackupsPage), findsOneWidget);
    expect(backup.existsSync(), isFalse, reason: 'Delete removes the backup');
  });

  testWidgets('Restore: Cancel closes only the dialog, Restore restores', (
    tester,
  ) async {
    await pumpPage(tester);
    final liveBefore = File(dbPath).lengthSync();
    expect(liveBefore, isNot(4096));

    await tester.tap(find.widgetWithText(TextButton, 'Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Restore Backup?'), findsOneWidget);
    await tester.tap(dialogButton('Cancel'));
    await settle(tester);
    expect(find.text('Restore Backup?'), findsNothing);
    expect(
      find.byType(BackupsPage),
      findsOneWidget,
      reason: 'Cancel must close the dialog, not the Backups page',
    );
    expect(
      File(dbPath).lengthSync(),
      liveBefore,
      reason: 'Cancel leaves the live database alone',
    );

    await tester.tap(find.widgetWithText(TextButton, 'Restore'));
    await tester.pumpAndSettle();
    await tester.tap(dialogButton('Restore'));
    await settle(tester);
    expect(find.text('Restore Backup?'), findsNothing);
    expect(find.byType(BackupsPage), findsOneWidget);
    expect(
      File(dbPath).readAsBytesSync().take(16).toList(),
      List.filled(16, 7),
      reason: 'Restore puts the backup in place of the live database',
    );
  });

  // A snapshot taken with its settings offers to restore them too. The
  // library comes back at once; the settings wait for the next launch,
  // because every running service already holds the current values.
  Future<String> pumpWithSettings(WidgetTester tester) async {
    await pumpPage(tester);
    final root = BackupService.storageRoot!;
    await tester.runAsync(
      () => File(
        BackupService.settingsPathFor(backup.path),
      ).writeAsString('{"format":1,"nightly":false,"values":{}}'),
    );
    final nested = tester.state<NavigatorState>(find.byType(Navigator).last);
    nested.pop();
    await settle(tester);
    nested.push(MaterialPageRoute<void>(builder: (_) => const BackupsPage()));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Restore'));
    await tester.pumpAndSettle();
    return root;
  }

  Future<PendingRestore?> stagedAfterRestore(
    WidgetTester tester,
    String root,
  ) async {
    await tester.tap(dialogButton('Restore'));
    await settle(tester);
    PendingRestore? staged;
    for (var i = 0; i < 20 && staged == null; i++) {
      staged = await tester.runAsync<PendingRestore?>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return PendingRestore.read(root);
      });
      await tester.pump();
    }
    return staged;
  }

  testWidgets('Restore with "Also restore settings" stages the settings for '
      'the next launch', (tester) async {
    final root = await pumpWithSettings(tester);
    expect(
      find.widgetWithText(CheckboxListTile, 'Also restore settings'),
      findsOneWidget,
    );
    final staged = await stagedAfterRestore(tester, root);
    expect(staged?.kind, PendingRestoreKind.settings);
    await tester.runAsync(AppDatabase.closeAndReset);
  });

  testWidgets('Restore with "Also restore settings" unticked keeps the '
      'current settings', (tester) async {
    final root = await pumpWithSettings(tester);
    await tester.tap(
      find.widgetWithText(CheckboxListTile, 'Also restore settings'),
    );
    await tester.pump();
    expect(await stagedAfterRestore(tester, root), isNull);
    await tester.runAsync(AppDatabase.closeAndReset);
  });
}
