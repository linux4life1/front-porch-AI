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

// sherpa_onnx 1.13.6 on macOS treats a non-null initBindings path as a
// Dart CLI package root and opens
// $path/sherpa_onnx_macos/sherpa-onnx.xcframework/macos-arm64_x86_64/libsherpa-onnx-c-api.dylib
// CocoaPods flattens the dylib to Contents/Frameworks/. Passing that
// Frameworks folder is the Stable v1.3.2 "Failed to load dynamic library"
// bug (Kokoro / Piper / Whisper all silent). These tests pin the path
// contract and the three engine call sites.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/sherpa_runtime.dart';

void main() {
  const frameworks = '/Applications/FrontPorchAI.app/Contents/Frameworks';

  test(
    'macOS initBindings path is null even when the flattened dylib was found',
    () {
      expect(sherpaInitBindingsDir('macos', frameworks), isNull);
    },
  );

  test(
    'macOS must not pass Frameworks — 1.13.6 would look inside xcframework',
    () {
      final nested = p.join(
        frameworks,
        'sherpa_onnx_macos',
        'sherpa-onnx.xcframework',
        'macos-arm64_x86_64',
        'libsherpa-onnx-c-api.dylib',
      );
      expect(
        nested,
        '/Applications/FrontPorchAI.app/Contents/Frameworks/'
        'sherpa_onnx_macos/sherpa-onnx.xcframework/macos-arm64_x86_64/'
        'libsherpa-onnx-c-api.dylib',
      );
      expect(sherpaInitBindingsDir('macos', frameworks), isNot(frameworks));
      expect(sherpaInitBindingsDir('macos', frameworks), isNot(nested));
    },
  );

  test('Linux and Windows still pass the directory containing the library', () {
    expect(sherpaInitBindingsDir('linux', '/opt/app/lib'), '/opt/app/lib');
    expect(sherpaInitBindingsDir('windows', r'C:\app'), r'C:\app');
    expect(sherpaInitBindingsDir('linux', null), isNull);
  });
}
