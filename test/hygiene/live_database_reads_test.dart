// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// Widgets reach the database through liveDatabase(context), never through
// the provider. `Provider<AppDatabase>.value(value: db)` in main.providers.dart
// is the database open at startup and can never be updated. A backup restore,
// a storage-root move and a stable-DB import all close that database and open
// a new one, so a widget that reads the provider gets a closed handle and its
// next query throws "connection was closed" until the app is restarted. That
// is how creating or editing a group failed after Backups > Restore.
//
// Every way of reading a provided AppDatabase counts, with or without an
// import prefix (`db.AppDatabase`): Provider.of, context.read / watch /
// select, Consumer and Selector, a ProxyProvider that takes it as an input,
// and a variable typed AppDatabase filled by an untyped Provider.of / read /
// watch. liveDatabase itself falls back to the provider when nothing is open
// (widget tests), so its file is the one place allowed to read it.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ratchet.dart';

const _liveDatabase = 'lib/services/database_rebind.dart';

final _providedDatabase = RegExp(
  r'\b(?:Provider\s*\.\s*of|(?:Consumer|Selector|\w*ProxyProvider)\d*)'
  r'\s*<[^;{}()]*?\bAppDatabase\b'
  r'|\.\s*(?:read|watch|select)\s*<[^;{}()]*?\bAppDatabase\b'
  r'|\bAppDatabase\s*\??\s+\w+\s*=\s*(?:Provider\s*\.\s*of'
  r'|\w+\s*\.\s*(?:read|watch))\s*\(',
);

void main() {
  test('no widget reads the startup database snapshot from the provider', () {
    final offenders = [
      for (final path in dartFiles('lib'))
        if (path != _liveDatabase && !path.endsWith('.g.dart'))
          ...DartSource.read(path).hits(_providedDatabase),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Use liveDatabase(context) from $_liveDatabase. The provided '
          'AppDatabase is the one open at startup; a backup restore closes '
          'it, and every query through it then throws.',
    );
  });

  test('the pattern matches the read liveDatabase itself makes', () {
    // A pattern that matches nothing would pass the test above forever.
    final own = DartSource.read(_liveDatabase).hits(_providedDatabase);
    expect(own.map((h) => h.match), ['Provider.of<AppDatabase']);
  });

  test('every read form counts; the provider itself, comments and strings '
      'do not', () {
    final source = DartSource('forms.dart', _forms);
    expect(source.hits(_providedDatabase).map((h) => h.line), [
      3,
      4,
      5,
      6,
      7,
      8,
      11,
      12,
      13,
      14,
      15,
      16,
    ]);
  });
}

const _forms = r'''
void reads(BuildContext context) {
  // Counted, one per line (lines 3-8, then 11-16).
  final a = Provider.of<AppDatabase>(context, listen: false);
  final b = Provider.of<db.AppDatabase>(context, listen: false);
  final c = context.read<AppDatabase>();
  final d = context.watch<db.AppDatabase>();
  final e = context.select<AppDatabase, int>((x) => x.schemaVersion);
  final f = Provider.of<
    AppDatabase
  >(context);
  final g = Consumer<AppDatabase>(builder: build);
  final h = Selector<AppDatabase, int>(selector: pick, builder: build);
  final i = Consumer2<StorageService, AppDatabase>(builder: build);
  final ChangeNotifierProxyProvider2<StorageService, AppDatabase, Foo> j;
  final AppDatabase k = Provider.of(context, listen: false);
  final db.AppDatabase? l = context.read();
  // Not counted: Provider.of<AppDatabase>(context) in a comment.
  final m = 'context.read<AppDatabase>()';
  final n = liveDatabase(context);
  final o = Provider.of<StorageService>(context, listen: false);
  final p = context.read<GroupChatRepository>();
  final AppDatabase q = await AppDatabase.instance();
  final r = Provider<AppDatabase>.value(value: db);
}
''';
