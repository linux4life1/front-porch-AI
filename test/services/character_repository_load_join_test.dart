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

// The constructor starts loadCharacters() and does not await it. A caller
// that then awaits loadCharacters() — backup restore, stable-to-beta import,
// startup reunification — used to hit the in-flight guard and return while
// the list was still empty. The portrait sweep after that await could delete
// live PNGs. debugPauseLoad holds the constructor load open so this fails
// the same way every run.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp
              .createTempSync('fpai_load_join_docs_')
              .path;
        }
        return null;
      });
}

Future<({AppDatabase db, StorageService storage, Directory work})>
_openV14Library() async {
  SharedPreferences.setMockInitialValues({'update_auto_check': false});
  _setupPathProviderMock();
  final work = Directory.systemTemp.createTempSync('fpai_load_join_db_');
  final dbFile = File(p.join(work.path, 'library.db'));
  File('test/fixtures/v14_upgrade/library.db').copySync(dbFile.path);
  final db = AppDatabase.forReunification(dbFile);
  await db.ensureSchemaIsRepaired();
  final storage = StorageService();
  await storage.initialized;
  return (db: db, storage: storage, work: work);
}

void _holdConstructorLoad(Completer<void> gate) {
  CharacterRepository.debugPauseLoad = () => gate.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    CharacterRepository.debugPauseLoad = null;
  });

  test(
    'awaiting loadCharacters joins the constructor load of a v1.4 library',
    () async {
      final gate = Completer<void>();
      _holdConstructorLoad(gate);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      final opened = await _openV14Library();
      addTearDown(() async {
        await opened.db.close();
        if (opened.work.existsSync()) opened.work.deleteSync(recursive: true);
      });

      final repo = CharacterRepository(opened.db, opened.storage);
      var joined = false;
      final pending = repo.loadCharacters().whenComplete(() => joined = true);
      await Future<void>.delayed(Duration.zero);

      // An early return finishes on the next microtask, while the constructor
      // load is still parked on the gate and the list is still empty.
      if (joined) {
        expect(repo.characters, hasLength(3));
      }
      if (!gate.isCompleted) gate.complete();
      await pending;
      expect(repo.characters, hasLength(3));
      expect(repo.isLoading, isFalse);
    },
  );

  test('cleanOrphanedPngs deletes nothing while a load is in flight', () async {
    final gate = Completer<void>();
    _holdConstructorLoad(gate);
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });

    final opened = await _openV14Library();
    addTearDown(() async {
      await opened.db.close();
      if (opened.work.existsSync()) opened.work.deleteSync(recursive: true);
    });

    final portraits = ['HostOn.png', 'HostOff.png', 'Clocked.png'];
    final png = img.encodePng(
      img.fill(
        img.Image(width: 8, height: 8),
        color: img.ColorRgb8(20, 40, 60),
      ),
    );
    for (final name in portraits) {
      await File(
        p.join(opened.storage.charactersDir.path, name),
      ).writeAsBytes(png);
    }

    final repo = CharacterRepository(opened.db, opened.storage);
    expect(repo.isLoading, isTrue);

    final deleted = await repo.cleanOrphanedPngs();

    expect(deleted, 0);
    for (final name in portraits) {
      expect(
        File(p.join(opened.storage.charactersDir.path, name)).existsSync(),
        isTrue,
        reason: name,
      );
    }

    if (!gate.isCompleted) gate.complete();
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (repo.isLoading && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
}
