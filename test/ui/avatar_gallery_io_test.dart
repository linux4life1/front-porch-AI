// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unit tests for the pure sprite-pack decoder. Guards the basename-matching fix
// (foldered ZIP entries used to silently match nothing).

import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_io.dart';

Uint8List _zip(Map<String, Uint8List> files) {
  final archive = Archive();
  files.forEach((name, bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  final png = Uint8List.fromList([1, 2, 3, 4]);

  test('recognizes emotion-named files at the root', () {
    final result = decodeSpritePack(_zip({'joy.png': png, 'anger.jpg': png}));
    expect(result.entries.map((e) => e.emotion).toSet(), {'joy', 'anger'});
    expect(result.unrecognized, 0);
  });

  test('matches on BASENAME so foldered packs still resolve', () {
    final result = decodeSpritePack(
      _zip({'sprites/joy.png': png, 'a/b/anger.png': png}),
    );
    expect(result.entries.map((e) => e.emotion).toSet(), {'joy', 'anger'});
    expect(result.unrecognized, 0);
  });

  test('counts non-emotion image files as unrecognized', () {
    final result = decodeSpritePack(_zip({'joy.png': png, 'random.png': png}));
    expect(result.entries.length, 1);
    expect(result.entries.single.emotion, 'joy');
    expect(result.unrecognized, 1);
  });

  test('ignores non-image files entirely', () {
    final result = decodeSpritePack(
      _zip({'joy.png': png, 'readme.txt': png}),
    );
    expect(result.entries.length, 1);
    expect(result.unrecognized, 0);
  });

  test('label prefixes (joy-1, sadness_2) match', () {
    final result = decodeSpritePack(
      _zip({'joy-1.png': png, 'sadness_2.png': png}),
    );
    expect(result.entries.map((e) => e.emotion).toSet(), {'joy', 'sadness'});
  });
}
