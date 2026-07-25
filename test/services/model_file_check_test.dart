// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the KoboldCpp model-file pre-flight (issue #137).
//
// The regression these lock down: a model file that Dart's `existsSync()`
// happily reports as present, but that KoboldCpp cannot actually open, used to
// produce nothing but "Process exited with code 2" in the backend log.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/model_file_check.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fpai_model_check_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// Writes [bytes] to a file in the temp dir and returns its path.
  Future<String> writeFile(String name, List<int> bytes) async {
    final file = File(p.join(tempDir.path, name));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  group('ModelFileCheck.validate', () {
    test('accepts a real GGUF file', () async {
      // "GGUF" magic followed by arbitrary payload.
      final path = await writeFile('good.gguf', [
        0x47, 0x47, 0x55, 0x46,
        ...List<int>.filled(64, 0),
      ]);

      expect(await ModelFileCheck.validate(path), isNull);
    });

    test('reports a missing file with an actionable message', () async {
      final path = p.join(tempDir.path, 'nope.gguf');

      final result = await ModelFileCheck.validate(path);

      expect(result, isNotNull);
      expect(result, contains('not found'));
      expect(result, contains(path));
    });

    test('rejects a file that is not a GGUF and blames the download', () async {
      // A dehydrated placeholder that the sync client replaced with a stub,
      // or simply a truncated download, both land here.
      final path = await writeFile('bogus.gguf', 'not a model'.codeUnits);

      final result = await ModelFileCheck.validate(path);

      expect(result, isNotNull);
      expect(result, contains('Not a valid GGUF'));
      expect(result, contains('partial or corrupted download'));
    });

    test('rejects a file too short to carry the magic', () async {
      final path = await writeFile('tiny.gguf', [0x47, 0x47]);

      expect(await ModelFileCheck.validate(path), contains('Not a valid GGUF'));
    });

    test('rejects a zero-byte file', () async {
      final path = await writeFile('empty.gguf', const []);

      expect(await ModelFileCheck.validate(path), contains('Not a valid GGUF'));
    });

    test('treats an empty path as preset mode and stays out of the way', () async {
      // Preset (.kcpps) launches pass an empty model path on purpose — the
      // preset owns the model and KoboldCpp resolves it itself.
      expect(await ModelFileCheck.validate(''), isNull);
    });

    test('a rejection never leaks a raw exit code to the user', () async {
      final path = await writeFile('bogus.gguf', 'nope'.codeUnits);

      final result = await ModelFileCheck.validate(path);

      expect(result, isNot(contains('exit')));
      expect(result, isNot(contains('code 2')));
    });
  });

  group('ModelFileCheck.explainExitCode2', () {
    test('names the offending file and gives the cloud-storage hint', () {
      final result = ModelFileCheck.explainExitCode2(r'C:\models\thing.gguf');

      expect(result, contains(r'C:\models\thing.gguf'));
      expect(result, contains('OneDrive'));
      expect(result, contains('Always keep on this device'));
    });

    test('degrades gracefully when the path is unknown', () {
      final result = ModelFileCheck.explainExitCode2('');

      expect(result, contains('the model file'));
      expect(result, contains(ModelFileCheck.cloudStorageHint));
    });
  });
}
