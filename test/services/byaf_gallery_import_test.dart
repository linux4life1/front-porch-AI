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

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/byaf_import_ops.dart';
import 'package:front_porch_ai/services/byaf_service.dart';

Future<String> _writeByaf(
  Directory dir, {
  List<Map<String, String>> images = const [],
  Set<int> skipByteIndexes = const {},
}) async {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'characters': ['characters/char1/character.json'],
          'scenarios': ['scenarios/scenario1.json'],
        }),
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'characters/char1/character.json',
        jsonEncode({
          'displayName': 'Aria',
          'persona': '{character} is a lighthouse keeper.',
          'images': images,
        }),
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'scenarios/scenario1.json',
        jsonEncode({
          'schemaVersion': 1,
          'narrative': '{character} greets {user}.',
          'firstMessages': [
            {'text': 'Hello {user}!'},
          ],
        }),
      ),
    );
  for (var i = 0; i < images.length; i++) {
    if (skipByteIndexes.contains(i)) continue;
    final relPath = images[i]['path'];
    if (relPath == null || relPath.isEmpty) continue;
    archive.addFile(ArchiveFile('characters/char1/$relPath', 1, [i]));
  }
  final path = '${dir.path}/gallery.byaf';
  await File(path).writeAsBytes(ZipEncoder().encode(archive));
  return path;
}

void main() {
  late Directory tempDir;
  late ByafService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('byaf_gallery_');
    service = ByafService(getTemporaryDirectory: () async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('parseByaf keeps every image in listed order for the gallery', () async {
    final path = await _writeByaf(
      tempDir,
      images: [
        {'path': 'portrait.png'},
        {'path': 'scene_1.png'},
        {'path': 'scene_2.png'},
      ],
    );

    final preview = await service.parseByaf(path);

    expect(preview.galleryImagePaths, hasLength(3));
    expect(preview.extractedImagePath, preview.galleryImagePaths.first);
    expect(
      preview.galleryImagePaths.every((p) => File(p).existsSync()),
      isTrue,
    );
    for (var i = 0; i < 3; i++) {
      expect(
        await File(preview.galleryImagePaths[i]).readAsBytes(),
        equals([i]),
        reason: 'gallery index $i should carry byte $i',
      );
    }

    final card = service.toCharacterCard(preview);
    expect(card.imagePath, preview.galleryImagePaths.first);
  });

  test('parseByaf skips missing and empty image entries', () async {
    final path = await _writeByaf(
      tempDir,
      images: [
        {'path': 'portrait.png'},
        {'path': ''},
        {'path': 'missing.png'},
        {'path': 'look.png'},
      ],
      skipByteIndexes: {2},
    );

    final preview = await service.parseByaf(path);
    expect(preview.galleryImagePaths, hasLength(2));
    expect(await File(preview.galleryImagePaths[0]).readAsBytes(), [0]);
    expect(await File(preview.galleryImagePaths[1]).readAsBytes(), [3]);
  });

  test('deleteByafTempImages removes every extract', () async {
    final path = await _writeByaf(
      tempDir,
      images: [
        {'path': 'portrait.png'},
        {'path': 'look.png'},
      ],
    );
    final preview = await service.parseByaf(path);
    expect(preview.galleryImagePaths, hasLength(2));
    deleteByafTempImages(preview.galleryImagePaths);
    for (final p in preview.galleryImagePaths) {
      expect(File(p).existsSync(), isFalse);
    }
  });
}
