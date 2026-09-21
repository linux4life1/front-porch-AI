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

import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const _sherpaCApiLib = {
  'macos': 'libsherpa-onnx-c-api.dylib',
  'linux': 'libsherpa-onnx-c-api.so',
  'windows': 'sherpa-onnx-c-api.dll',
};

/// Directory holding the sherpa-onnx C API library, or null if it is not
/// next to the executable. `FP_SHERPA_LIB` overrides for tests/dev.
///
/// Do not pass this to `sherpa.initBindings` on macOS — use
/// [initSherpaBindings] in every isolate instead. Shared by the in-process
/// Whisper STT and Kokoro/Piper TTS engines
/// (docs/design/sidecar-retirement.md phases 3–4).
String? sherpaNativeLibDir() {
  final env = Platform.environment['FP_SHERPA_LIB'];
  if (env != null && env.isNotEmpty) return env;
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final candidates = [
    if (Platform.isMacOS) p.join(File(exeDir).parent.path, 'Frameworks'),
    if (Platform.isLinux) p.join(exeDir, 'lib'),
    if (Platform.isWindows) exeDir,
  ];
  final name = _sherpaCApiLib[Platform.operatingSystem];
  for (final c in candidates) {
    if (name != null && File(p.join(c, name)).existsSync()) return c;
  }
  return null;
}

/// Directory to pass to `sherpa.initBindings`, or null for process()/default.
///
/// macOS sherpa_onnx 1.13.6+ treats a non-null path as a Dart CLI package
/// root and opens
/// `$path/sherpa_onnx_macos/sherpa-onnx.xcframework/macos-arm64_x86_64/libsherpa-onnx-c-api.dylib`.
/// CocoaPods flattens the dylib to `Contents/Frameworks/`, so passing that
/// folder is the Stable v1.3.2 "Failed to load dynamic library" miss.
/// Always null on macOS. Linux/Windows still pass the folder that contains
/// the `.so` / `.dll`.
String? sherpaInitBindingsDir(String operatingSystem, String? foundDir) {
  if (operatingSystem == 'macos') return null;
  return foundDir;
}

/// Load the native sherpa-onnx C API in **this** isolate.
///
/// Each isolate has its own FFI binding state, so Kokoro/Piper/Whisper
/// workers must call this themselves. On macOS, preloads the flattened
/// CocoaPods dylib (needed for `flutter run` debug, which copies the
/// library into Frameworks but does not link it) then calls
/// [sherpa.initBindings] with no path so 1.13.6 uses
/// `DynamicLibrary.process()`.
void initSherpaBindings() {
  final found = sherpaNativeLibDir();
  if (Platform.isMacOS && found != null) {
    final dylib = p.join(found, _sherpaCApiLib['macos']!);
    if (File(dylib).existsSync()) {
      DynamicLibrary.open(dylib);
    }
  }
  sherpa.initBindings(sherpaInitBindingsDir(Platform.operatingSystem, found));
}
