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

// Pins the crash-safe settings store: it reads and writes the stock
// plugin's shared_preferences.json shape, a save never leaves the file empty
// or half-written, and a parse failure is not cached so startup recovery can
// repair the file and read it again.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/atomic_prefs_store.dart';

void main() {
  late Directory tmp;
  late File file;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('atomic_prefs_test');
    file = File(p.join(tmp.path, 'shared_preferences.json'));
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  AtomicPrefsStore store() => AtomicPrefsStore(() async => file);

  test('reads what the stock store wrote and saves the same shape', () async {
    await file.writeAsString(
      jsonEncode({'flutter.saved_prompts': '[]', 'flutter.n': 3}),
    );
    final s = store();

    expect(await s.getAll(), {'flutter.saved_prompts': '[]', 'flutter.n': 3});
    expect(await s.setValue('String', 'flutter.theme', 'plum'), isTrue);

    final onDisk = jsonDecode(await file.readAsString()) as Map;
    expect(onDisk['flutter.theme'], 'plum');
    expect(onDisk['flutter.n'], 3);
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test(
    'a save replaces the file by rename, never by rewriting it in place',
    () async {
      await file.writeAsString(jsonEncode({'flutter.a': 1}));
      // An open handle on the old file keeps reading the old, whole store
      // after a rename; an in-place truncate-and-write would change it.
      final before = await file.open();
      final s = store();

      await s.setValue('Int', 'flutter.a', 2);

      final oldBytes = await before.read(64);
      await before.close();
      if (!Platform.isWindows) {
        expect(jsonDecode(utf8.decode(oldBytes)), {'flutter.a': 1});
      }
      expect(jsonDecode(await file.readAsString()), {'flutter.a': 2});
    },
  );

  test('many quick saves all land and every caller hears success', () async {
    final s = store();
    final results = await Future.wait([
      for (var i = 0; i < 40; i++) s.setValue('Int', 'flutter.k$i', i),
    ]);

    expect(results, everyElement(isTrue));
    final onDisk = jsonDecode(await file.readAsString()) as Map;
    for (var i = 0; i < 40; i++) {
      expect(onDisk['flutter.k$i'], i);
    }
  });

  test('a torn file throws and is read again once repaired', () async {
    await file.writeAsBytes(List.filled(32, 0));
    final s = store();

    await expectLater(s.getAll(), throwsA(isA<FormatException>()));
    await file.writeAsString(jsonEncode({'flutter.ok': true}));
    expect(await s.getAll(), {'flutter.ok': true});
  });

  test('clear and remove keep keys outside the prefix', () async {
    await file.writeAsString(
      jsonEncode({'flutter.a': 1, 'flutter.b': 2, 'other.c': 3}),
    );
    final s = store();

    await s.remove('flutter.a');
    await s.clear();

    expect(jsonDecode(await file.readAsString()), {'other.c': 3});
  });
}
