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

import 'package:path/path.dart' as p;

/// Directory holding the sherpa-onnx C API library, or null to let dlopen
/// search default paths (the Flutter bundle case, where the plugin's
/// native library is already on the loader path). `FP_SHERPA_LIB`
/// overrides for tests/dev. Shared by the in-process Whisper STT and
/// Kokoro TTS engines (docs/design/sidecar-retirement.md phases 3–4).
String? sherpaNativeLibDir() {
  final env = Platform.environment['FP_SHERPA_LIB'];
  if (env != null && env.isNotEmpty) return env;
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final candidates = [
    if (Platform.isMacOS) p.join(File(exeDir).parent.path, 'Frameworks'),
    if (Platform.isLinux) p.join(exeDir, 'lib'),
    if (Platform.isWindows) exeDir,
  ];
  const lib = {
    'macos': 'libsherpa-onnx-c-api.dylib',
    'linux': 'libsherpa-onnx-c-api.so',
    'windows': 'sherpa-onnx-c-api.dll',
  };
  final name = lib[Platform.operatingSystem];
  for (final c in candidates) {
    if (name != null && File(p.join(c, name)).existsSync()) return c;
  }
  return null;
}
