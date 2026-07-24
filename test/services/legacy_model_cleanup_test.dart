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

// The reclaim sweep deletes ONLY what the retired Python engines used and
// must never touch the sherpa replacements or the piper .onnx.json voice
// registry — getting this wrong silently destroys the new engines' models.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/legacy_model_cleanup.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  File put(String relative, [int size = 4]) {
    final f = File(p.join(root.path, relative));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(List.filled(size, 0x7));
    return f;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('fp_reclaim');
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('empty root scans to no groups (cleanup UI stays hidden)', () async {
    expect(await LegacyModelCleanup.scan(root.path), isEmpty);
  });

  test('scan finds legacy files, spares sherpa + configs; reclaim deletes '
      'exactly those', () async {
    // Legacy leftovers.
    final ct2 = put('system/whisper_models/base.en-ct2/model.bin', 100);
    final kokoroOnnx = put('system/kokoro_models/kokoro-v1.0.onnx', 50);
    final kokoroVoices = put('system/kokoro_models/voices-v1.0.bin', 10);
    final piperOnnx = put('system/piper_voices/en_US-amy-medium.onnx', 30);
    // Survivors: the new engines' models + the voice registry + catalog.
    final sherpaWhisper = put(
      'system/whisper_models/sherpa/tiny.en/tiny.en-encoder.int8.onnx',
      40,
    );
    final sherpaKokoro = put(
      'system/kokoro_models/sherpa-v1_0/model.onnx',
      40,
    );
    final piperJson = put('system/piper_voices/en_US-amy-medium.onnx.json');
    final catalog = put('system/piper_voices/catalog.json');
    final sherpaPiper = put(
      'system/piper_models/sherpa/en_US-amy-medium/en_US-amy-medium.onnx',
      40,
    );

    final groups = await LegacyModelCleanup.scan(root.path);
    expect(groups, hasLength(3));
    final total = groups.fold(0, (s, g) => s + g.bytes);
    expect(total, 100 + 50 + 10 + 30);

    final freed = await LegacyModelCleanup.reclaim(root.path);
    expect(freed, total);

    for (final gone in [ct2, kokoroOnnx, kokoroVoices, piperOnnx]) {
      expect(gone.existsSync(), isFalse, reason: '${gone.path} must go');
    }
    for (final kept in [
      sherpaWhisper,
      sherpaKokoro,
      piperJson,
      catalog,
      sherpaPiper,
    ]) {
      expect(kept.existsSync(), isTrue, reason: '${kept.path} must stay');
    }

    // After the sweep there is nothing left to offer.
    expect(await LegacyModelCleanup.scan(root.path), isEmpty);
  });
}
