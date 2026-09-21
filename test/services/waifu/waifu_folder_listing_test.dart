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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_walk_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('lists child directories and project markers in this folder', () async {
    await Directory(p.join(root.path, 'src')).create();
    await File(p.join(root.path, 'pubspec.yaml')).writeAsString('name: toy');
    await File(p.join(root.path, 'readme.txt')).writeAsString('not a marker');

    final listing = await listWaifuDirectory(root.path);

    expect(listing.path, root.path);
    expect(listing.parentPath, p.dirname(root.path));
    expect(listing.directories.map((e) => e.name), contains('src'));
    expect(listing.directories.single.path, p.join(root.path, 'src'));
    expect(listing.projectHints, contains('pubspec.yaml'));
    expect(listing.projectHints, isNot(contains('readme.txt')));
  });

  test('missing path returns an empty listing rather than throwing', () async {
    final missing = p.join(root.path, 'nope', 'gone');
    final listing = await listWaifuDirectory(missing);
    expect(listing.path, missing);
    expect(listing.directories, isEmpty);
    expect(listing.projectHints, isEmpty);
  });

  test(
    'default start path is HOME, USERPROFILE, or systemTemp — never /Users/',
    () {
      final start = waifuDefaultStartPath();
      expect(start, isNotEmpty);
      expect(start, isNot(equals('/Users/')));
      final home = Platform.environment['HOME'];
      final profile = Platform.environment['USERPROFILE'];
      if (home != null && home.isNotEmpty) {
        expect(start, home);
      } else if (profile != null && profile.isNotEmpty) {
        expect(start, profile);
      } else {
        expect(start, Directory.systemTemp.path);
      }
    },
  );
}
