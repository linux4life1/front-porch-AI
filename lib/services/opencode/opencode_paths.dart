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

import 'package:front_porch_ai/services/opencode/opencode_pin.dart';
import 'package:path/path.dart' as p;

/// App-support closet for the managed OpenCode copy. Sibling of
/// `koboldcpp_bin` under the existing storage root — not a second Documents
/// tree, not Homebrew, not `~/.config/opencode`.
class OpenCodeCloset {
  OpenCodeCloset(this.rootPath);

  final String rootPath;

  String get binDir => p.join(rootPath, 'opencode-bin');

  String get binaryName => Platform.isWindows ? 'opencode.exe' : 'opencode';

  String get binaryPath => p.join(binDir, binaryName);

  String get versionFilePath => p.join(binDir, kOpenCodeVersionFileName);

  String get configDir => p.join(binDir, 'config');

  String get configFilePath => p.join(configDir, 'opencode.json');

  String get dataDir => p.join(binDir, 'data');

  String get cacheDir => p.join(binDir, 'cache');

  String get logDir => p.join(binDir, 'log');

  String get stateDir => p.join(binDir, 'state');

  String get unpackDir => p.join(binDir, 'unpack');

  Future<void> ensureLayout() async {
    for (final dir in [
      binDir,
      configDir,
      dataDir,
      cacheDir,
      logDir,
      stateDir,
    ]) {
      await Directory(dir).create(recursive: true);
    }
  }
}

Map<String, String> openCodeIsolatedEnvironment(OpenCodeCloset closet) {
  return {
    'OPENCODE_CONFIG': closet.configFilePath,
    'OPENCODE_CONFIG_DIR': closet.configDir,
    'OPENCODE_DATA_DIR': closet.dataDir,
    'OPENCODE_CACHE_DIR': closet.cacheDir,
    'OPENCODE_LOG_DIR': closet.logDir,
    'OPENCODE_STATE_DIR': closet.stateDir,
    'OPENCODE_DISABLE_GLOBAL_CONFIG': 'true',
    'OPENCODE_DISABLE_PROJECT_CONFIG': 'true',
    'OPENCODE_APPNAME': 'frontporch-waifu',
  };
}

List<String> openCodeServeArgs(int port) => [
  'serve',
  '--hostname',
  '127.0.0.1',
  '--port',
  '$port',
  '--print-logs',
  '--pure',
];
