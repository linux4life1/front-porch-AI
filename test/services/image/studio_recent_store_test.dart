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

// Image Studio's Recent shelf (issue #667): every Create and Edit result is
// kept on disk, trimmed to the user's limit, starred pictures never trimmed.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

void main() {
  late Directory dir;
  late int limit;
  late int ms;
  late StudioRecentStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fpai_recent_');
    limit = 3;
    ms = 1700000000000;
    store = StudioRecentStore(
      folder: () => dir,
      limit: () => limit,
      clock: () => DateTime.fromMillisecondsSinceEpoch(ms += 1000),
    );
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Uint8List png(int n) => Uint8List.fromList([137, 80, 78, 71, n]);

  Future<StudioRecentEntry> add(int n, {bool edit = false}) async =>
      (await store.add(
        png(n),
        prompt: 'prompt $n',
        mode: edit ? 'edit' : 'create',
        style: 'cinematic',
        model: 'juggernaut',
      ))!;

  test('a kept picture comes back newest first with its prompt', () async {
    final first = await add(1);
    final second = await add(2, edit: true);
    final listed = await store.list();
    expect(listed.map((e) => e.name), [second.name, first.name]);
    expect(listed.first.prompt, 'prompt 2');
    expect(listed.first.mode, 'edit');
    expect(listed.first.style, 'cinematic');
    expect(listed.last.model, 'juggernaut');
    expect(File(listed.last.path).readAsBytesSync(), png(1));
  });

  test('a fresh store on the same folder still lists the pictures', () async {
    await add(1);
    final reopened = StudioRecentStore(folder: () => dir, limit: () => limit);
    expect((await reopened.list()).single.prompt, 'prompt 1');
  });

  test('the oldest unstarred pictures go past the limit', () async {
    final oldest = await add(1);
    await store.setKept(oldest.name, true);
    for (var n = 2; n <= 6; n++) {
      await add(n);
    }
    final listed = await store.list();
    expect(listed.map((e) => e.prompt), [
      'prompt 6',
      'prompt 5',
      'prompt 4',
      'prompt 1',
    ]);
    expect(listed.last.kept, isTrue);
    // The trimmed pictures' notes go with them.
    expect(
      dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')),
      hasLength(4),
    );
  });

  test('keep all never trims; off holds only the newest', () async {
    limit = kStudioRecentKeepAll;
    for (var n = 1; n <= 5; n++) {
      await add(n);
    }
    expect(await store.list(), hasLength(5));
    limit = kStudioRecentOff;
    await store.applyLimit();
    expect((await store.list()).single.prompt, 'prompt 5');
  });

  test('unstarring over the limit trims at once', () async {
    final starred = await add(1);
    await store.setKept(starred.name, true);
    for (var n = 2; n <= 4; n++) {
      await add(n);
    }
    expect(await store.list(), hasLength(4));
    expect(await store.setKept(starred.name, false), isNull);
    expect((await store.list()).map((e) => e.prompt), [
      'prompt 4',
      'prompt 3',
      'prompt 2',
    ]);
  });

  test('clear removes only unstarred pictures', () async {
    final starred = await add(1);
    await store.setKept(starred.name, true);
    await add(2);
    await add(3);
    expect(await store.clearUnkept(), 2);
    expect((await store.list()).single.name, starred.name);
  });

  test('delete and fileFor only ever touch rec_ files', () async {
    final entry = await add(1);
    final other = File(p.join(dir.path, 'holiday.png'))..writeAsBytesSync([1]);
    expect(store.fileFor(entry.name), isNotNull);
    expect(store.fileFor('holiday.png'), isNull);
    expect(store.fileFor('../${entry.name}'), isNull);
    expect(await store.delete('holiday.png'), isFalse);
    await store.clearUnkept();
    expect(other.existsSync(), isTrue);
    expect(await store.delete(entry.name), isFalse);
  });

  test('a picture whose notes are lost still lists', () async {
    final entry = await add(1);
    File(p.setExtension(entry.path, '.json')).deleteSync();
    final listed = (await store.list()).single;
    expect(listed.name, entry.name);
    expect(listed.prompt, isEmpty);
    expect(listed.kept, isFalse);
  });

  test('the limit only takes the choices the shelf offers', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = ImageGenSettings()
      ..initializeBase(await SharedPreferences.getInstance(), () {});
    settings.load();
    expect(settings.studioRecentLimit, kStudioRecentDefault);
    expect(await settings.setStudioRecentLimit(7), isFalse);
    expect(await settings.setStudioRecentLimit(200), isTrue);
    settings.load();
    expect(settings.studioRecentLimit, 200);
  });

  test('trimming past the limit leaves other files in the folder', () async {
    final other = File(p.join(dir.path, 'holiday.png'))..writeAsBytesSync([1]);
    limit = kStudioRecentOff;
    await add(1);
    await add(2);
    expect((await store.list()).single.prompt, 'prompt 2');
    expect(other.existsSync(), isTrue);
  });
}
