// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Drop routing lives in a private part. These source reads fail if the
// library wrap or the picker-import handoff is deleted while unit tests stay
// green.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String home;
  late String drop;

  setUpAll(() {
    home = File('lib/ui/pages/home_page.dart').readAsStringSync();
    drop = File('lib/ui/pages/home/home_page_drop.dart').readAsStringSync();
  });

  test('empty library and the card grid both wrap with the drop zone', () {
    expect(
      home.split('_wrapChatsWithDrop').length - 1,
      greaterThanOrEqualTo(2),
    );
    expect(drop, contains('HomeDropZone('));
  });

  test('a drop reuses picker import, not a second pipeline', () {
    expect(drop, contains('planHomeDropSources'));
    expect(drop, contains('_importCharacterFromFiles'));
    expect(drop, contains('_importByafFromPaths'));
    expect(drop, contains('_importPngAndByafBatch'));
    expect(drop, contains('plan.isMixed'));
  });
}
