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

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/storage/user_audio_store.dart';

void main() {
  late Directory root;
  late StorageService storage;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fpai_user_audio');
    storage = StorageService.sandbox(root.path);
    UserAudioStore.testLoadOverride = null;
  });

  tearDown(() {
    UserAudioStore.testLoadOverride = null;
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

  test('a bad header is rejected and nothing is written', () async {
    final result = await UserAudioStore.storeUserAudioBytes(
      Uint8List.fromList([0x00, 0x00, 0x00]),
      'bad.mp3',
      storage,
    );
    expect(result.name, isNull);
    expect(result.error, isNotNull);
    expect(storage.audioDir.listSync().isEmpty, isTrue);
  });

  test(
    'a file whose load test throws is rejected and its copy deleted',
    () async {
      UserAudioStore.testLoadOverride = (path) async {
        throw StateError('could not load $path');
      };
      final result = await UserAudioStore.storeUserAudioBytes(
        validMp3(),
        'ok.mp3',
        storage,
      );
      expect(result.name, isNull);
      expect(result.error, isNotNull);
      expect(storage.audioDir.listSync().isEmpty, isTrue);
    },
  );

  test('a file that loads is stored by bare name', () async {
    UserAudioStore.testLoadOverride = (path) async {};
    final result = await UserAudioStore.storeUserAudioBytes(
      validMp3(),
      'my sound.mp3',
      storage,
    );
    expect(result.error, isNull);
    expect(result.name, 'my_sound.mp3');
    final file = File(p.join(storage.audioDir.path, result.name!));
    expect(file.existsSync(), isTrue);
    expect(await file.length(), validMp3().length);
  });

  test('an oversized file is rejected before any write', () async {
    final result = await UserAudioStore.storeUserAudioBytes(
      Uint8List(UserAudioStore.kUserAudioMaxBytes + 1),
      'big.mp3',
      storage,
    );
    expect(result.name, isNull);
    expect(result.error, contains('MiB'));
    expect(storage.audioDir.listSync().isEmpty, isTrue);
  });
}
