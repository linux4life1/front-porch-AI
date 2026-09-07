// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desk_hidden_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('visible() hides dot folders until includeHidden', () async {
    await Directory(p.join(root.path, 'Documents')).create();
    await Directory(p.join(root.path, '.cache')).create();
    await Directory(p.join(root.path, '.git')).create();
    final listing = await listDeskDirectory(root.path);
    expect(
      listing.directories.map((e) => e.name),
      containsAll(['Documents', '.cache', '.git']),
    );
    expect(listing.visible().map((e) => e.name).toList(), ['Documents']);
    expect(
      listing.visible(includeHidden: true).map((e) => e.name),
      containsAll(['Documents', '.cache', '.git']),
    );
  });
}
