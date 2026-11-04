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

  test('a file that loads is stored under a content-hash name', () async {
    UserAudioStore.testLoadOverride = (path) async {};
    final result = await UserAudioStore.storeUserAudioBytes(
      validMp3(),
      'my sound.mp3',
      storage,
    );
    expect(result.error, isNull);
    expect(result.name, startsWith('my_sound-'));
    expect(result.name, endsWith('.mp3'));
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

  test('two different files with the same original name each keep their own '
      'sound', () async {
    // The collision bug: Place A uses your rain.mp3; Place B is later
    // given a different rain.mp3 from elsewhere. Before, the second copy
    // overwrote the first and Place A silently played Place B's sound.
    // Content-addressed names must keep both, and re-offering the very
    // same file must add nothing.
    UserAudioStore.testLoadOverride = (path) async {};
    final audio = Directory(p.join(root.path, 'audio'))..createSync();
    final firstSrc = File(p.join(audio.path, 'one.mp3'))
      ..writeAsBytesSync([
        ...validMp3(),
        ...List<int>.generate(90, (i) => 100 + i),
      ]);
    final first = await UserAudioStore.storeUserAudioPath(
      firstSrc.path,
      storage,
    );
    expect(first.error, isNull);

    final secondSrc = File(p.join(audio.path, 'two.mp3'))
      ..writeAsBytesSync([
        ...validMp3(),
        ...List<int>.generate(110, (i) => 200 - i),
      ]);
    final second = await UserAudioStore.storeUserAudioPath(
      secondSrc.path,
      storage,
    );
    expect(second.error, isNull);
    expect(second.name, isNot(first.name));

    // The first world's bytes are untouched under its own name.
    final kept = File(p.join(audio.path, first.name!));
    expect(kept.readAsBytesSync(), [
      ...validMp3(),
      ...List<int>.generate(90, (i) => 100 + i),
    ]);
    // Both land in the shared listing, each once.
    final names = [
      for (final f in await UserAudioStore.listUserAudio(storage)) f.name,
    ];
    expect(names.where((n) => n.startsWith('one-')), hasLength(1));
    expect(names.where((n) => n.startsWith('two-')), hasLength(1));

    // Same original name, same bytes offered from a fresh path: one
    // stored file, no duplicate.
    final sameSrc = File(p.join(audio.path, 'copy-of-one.mp3'))
      ..writeAsBytesSync([
        ...validMp3(),
        ...List<int>.generate(90, (i) => 100 + i),
      ]);
    final same = await UserAudioStore.storeUserAudioPath(sameSrc.path, storage);
    expect(same.error, isNull);
    final names2 = [
      for (final f in await UserAudioStore.listUserAudio(storage)) f.name,
    ];
    expect(
      names2.where((n) => n.startsWith('one-')),
      hasLength(1),
      reason: 'the bytes were already stored; nothing duplicated',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a failed load test erases only the file it just wrote', () async {
    UserAudioStore.testLoadOverride = (path) async {};
    final audio = Directory(p.join(root.path, 'audio'))..createSync();
    final goodSrc = File(p.join(audio.path, 'good.mp3'))
      ..writeAsBytesSync([
        ...validMp3(),
        ...List<int>.generate(90, (i) => 10 + i),
      ]);
    final good = await UserAudioStore.storeUserAudioPath(goodSrc.path, storage);
    expect(good.error, isNull);
    final goodName = good.name!;

    // A DIFFERENT file the player rejects. Its digest names it apart from
    // the good one, so the cleanup can only ever delete this bad copy —
    // the old bug deleted the earlier world's sound here.
    UserAudioStore.testLoadOverride = (path) async {
      throw StateError('simulated failure');
    };
    final badSrc = File(p.join(audio.path, 'good.mp3'))
      ..writeAsBytesSync([
        ...validMp3(),
        ...List<int>.generate(100, (i) => (i * 7) % 256),
      ]);
    final bad = await UserAudioStore.storeUserAudioPath(badSrc.path, storage);
    expect(bad.error, isNotNull);
    expect(
      File(p.join(audio.path, goodName)).existsSync(),
      isTrue,
      reason: 'the earlier world sound survives',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
