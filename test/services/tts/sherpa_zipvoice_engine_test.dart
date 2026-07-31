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
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/tts/sherpa_zipvoice_engine.dart';

void main() {
  group('SherpaZipVoiceEngine', () {
    test('modelDir resolves under the app root', () {
      expect(
        SherpaZipVoiceEngine.modelDir(r'C:\data'),
        p.join(r'C:\data', 'system', 'zipvoice_models', 'sherpa-v1_0'),
      );
    });

    test('numSteps defaults to the ear-test value', () {
      expect(SherpaZipVoiceEngine.numSteps, 4);
    });

    test('isModelPresent false when bundle missing', () {
      final root = Directory.systemTemp.createTempSync('zipvoice_test_');
      addTearDown(() => root.deleteSync(recursive: true));
      expect(SherpaZipVoiceEngine.isModelPresent(root.path), isFalse);
    });

    test('isModelPresent true with full bundle', () {
      final root = Directory.systemTemp.createTempSync('zipvoice_test_');
      addTearDown(() => root.deleteSync(recursive: true));
      final dir = Directory(SherpaZipVoiceEngine.modelDir(root.path))
        ..createSync(recursive: true);
      for (final f in [
        'tokens.txt',
        'encoder.int8.onnx',
        'decoder.int8.onnx',
        'vocos_24khz.onnx',
        'lexicon.txt',
      ]) {
        File(p.join(dir.path, f)).writeAsStringSync('x');
      }
      Directory(p.join(dir.path, 'espeak-ng-data')).createSync(recursive: true);
      expect(SherpaZipVoiceEngine.isModelPresent(root.path), isTrue);
    });

    test('isModelPresent false when a required file is missing', () {
      final root = Directory.systemTemp.createTempSync('zipvoice_test_');
      addTearDown(() => root.deleteSync(recursive: true));
      final dir = Directory(SherpaZipVoiceEngine.modelDir(root.path))
        ..createSync(recursive: true);
      for (final f in [
        'tokens.txt',
        'encoder.int8.onnx',
        'decoder.int8.onnx',
      ]) {
        File(p.join(dir.path, f)).writeAsStringSync('x');
      }
      Directory(p.join(dir.path, 'espeak-ng-data')).createSync(recursive: true);
      expect(SherpaZipVoiceEngine.isModelPresent(root.path), isFalse);
    });

    test('transcriptPathFor resolves sibling .txt', () {
      final dir = Directory.systemTemp.createTempSync('zipvoice_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final wav = File(p.join(dir.path, 'reference.wav'))
        ..writeAsStringSync('x');
      final txt = File(p.join(dir.path, 'reference.txt'))
        ..writeAsStringSync('the transcript');
      expect(
        SherpaZipVoiceEngine.transcriptPathFor(wav.path),
        txt.path,
      );
    });

    test('transcriptPathFor returns null when sibling .txt missing', () {
      final dir = Directory.systemTemp.createTempSync('zipvoice_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final wav = File(p.join(dir.path, 'reference.wav'))
        ..writeAsStringSync('x');
      expect(SherpaZipVoiceEngine.transcriptPathFor(wav.path), isNull);
    });
  });
}
