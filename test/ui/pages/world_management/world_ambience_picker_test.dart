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
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/storage/user_audio_store.dart';
import 'package:front_porch_ai/ui/pages/world_management/world_ambience_audio.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late StorageService storage;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fpai_ambience_pick');
    storage = StorageService.sandbox(root.path);
    UserAudioStore.testLoadOverride = null;
    PickerPrefs.testPickFilesOverride = null;
  });

  tearDown(() {
    UserAudioStore.testLoadOverride = null;
    PickerPrefs.testPickFilesOverride = null;
    root.deleteSync(recursive: true);
  });

  Uint8List validMp3() => Uint8List.fromList([
    0xFF,
    0xE0,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
  ]);

  testWidgets('the ambience flow asks for the audio category and MP3 only', (
    tester,
  ) async {
    String? seenCategory;
    List<String>? seenExts;
    PickerPrefs.testPickFilesOverride =
        ({required String category, List<String>? allowedExtensions}) async {
          seenCategory = category;
          seenExts = allowedExtensions;
          return FilePickerResult([
            MemoryPlatformFile(name: 'forest.mp3', bytes: validMp3()),
          ]);
        };
    UserAudioStore.testLoadOverride = (path) async {};
    await tester.pumpWidget(MaterialApp(home: const Text('root')));
    final ctx = tester.element(find.byType(Text));
    // A path-less pick writes through the real temp dir: that I/O needs
    // runAsync or it never completes inside the fake-async zone.
    final result = (await tester.runAsync(
      () => pickCustomAmbience(ctx, storage),
    ))!;
    expect(result.error, isNull);
    expect(result.name, 'forest.mp3');
    expect(seenCategory, PickerPrefs.catAudio);
    expect(seenExts, ['mp3']);
    final file = File(p.join(storage.audioDir.path, result.name!));
    expect(file.existsSync(), isTrue);
  });

  testWidgets('a bad-header pick is surfaced and nothing is stored', (
    tester,
  ) async {
    PickerPrefs.testPickFilesOverride =
        ({required String category, List<String>? allowedExtensions}) async {
          return FilePickerResult([
            MemoryPlatformFile(
              name: 'bad.mp3',
              bytes: Uint8List.fromList([0, 0]),
            ),
          ]);
        };
    await tester.pumpWidget(MaterialApp(home: const Text('root')));
    final ctx = tester.element(find.byType(Text));
    final result = (await tester.runAsync(
      () => pickCustomAmbience(ctx, storage),
    ))!;
    expect(result.name, isNull);
    expect(result.error, isNotNull);
    expect(storage.audioDir.listSync().isEmpty, isTrue);
  });
}
