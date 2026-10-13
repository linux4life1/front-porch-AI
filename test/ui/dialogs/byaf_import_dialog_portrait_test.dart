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

// The import preview must not read the portrait's temp extract. On Windows a
// file an image provider still holds cannot be deleted, so a preview drawn
// from the extract left it behind on Cancel (porch_byaf_import_dialog_test,
// Windows E2E). Deleting the extracts before the dialog paints proves the
// portrait comes from memory.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/byaf_import_ops.dart';
import 'package:front_porch_ai/services/byaf_service.dart';
import 'package:front_porch_ai/ui/dialogs/byaf_import_dialog.dart';

// A 1×1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==',
);

Future<String> _writeByaf(Directory dir) async {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'characters': ['characters/char1/character.json'],
          'scenarios': <String>[],
        }),
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'characters/char1/character.json',
        jsonEncode({
          'displayName': 'Aria',
          'persona': 'A lighthouse keeper.',
          'images': [
            {'path': 'portrait.png'},
            {'path': 'look.png'},
          ],
        }),
      ),
    )
    ..addFile(ArchiveFile('characters/char1/portrait.png', _png.length, _png))
    ..addFile(ArchiveFile('characters/char1/look.png', _png.length, _png));
  final path = '${dir.path}/portrait.byaf';
  await File(path).writeAsBytes(ZipEncoder().encode(archive));
  return path;
}

void main() {
  testWidgets('the preview portrait survives its temp extract being deleted', (
    tester,
  ) async {
    final preview = (await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('byaf_portrait_');
      addTearDown(() => dir.delete(recursive: true));
      final service = ByafService(getTemporaryDirectory: () async => dir);
      return service.parseByaf(await _writeByaf(dir));
    }))!;
    expect(preview.portraitBytes, equals(_png));

    deleteByafTempImages(preview.galleryImagePaths);
    expect(
      preview.galleryImagePaths.where((p) => File(p).existsSync()),
      isEmpty,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ByafImportDialog(preview: preview)),
      ),
    );
    // Let any image provider finish (or fail) its load for real.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    expect(find.text('Aria'), findsOneWidget);
    expect(
      find.byIcon(Icons.person),
      findsNothing,
      reason: 'the portrait must draw from memory, not the deleted extract',
    );
  });
}
