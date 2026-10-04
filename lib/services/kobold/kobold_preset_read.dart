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

import 'package:path/path.dart' as path;

import 'kcpps_codec.dart';

/// A preset that cannot be launched from, with the reason in plain words.
class KoboldPresetProblem implements Exception {
  const KoboldPresetProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads the preset at [kcppsPath], or throws [KoboldPresetProblem].
Future<KcppsOk> readKoboldPreset(String kcppsPath) async {
  final name = path.basename(kcppsPath);
  final String text;
  try {
    text = await File(kcppsPath).readAsString();
  } on FileSystemException {
    throw KoboldPresetProblem(
      'The preset "$name" could not be opened. Pick another preset, or '
      'none, in Settings.',
    );
  }
  final read = readKcpps(text);
  if (read is! KcppsOk) {
    throw KoboldPresetProblem(
      'The preset "$name" can\'t be read. ${(read as KcppsBroken).reason} '
      'Pick another preset, or none, in Settings.',
    );
  }
  return read;
}

/// Why a launch from [kcppsPath] cannot go ahead, in plain words, or null
/// when it can (or there is no preset). For the screens that start the
/// engine: the launch itself only logs this, so without the check a broken
/// preset makes Start look like it did nothing.
Future<String?> koboldPresetProblem(String? kcppsPath) async {
  if (kcppsPath == null || kcppsPath.isEmpty) return null;
  try {
    await readKoboldPreset(kcppsPath);
    return null;
  } on KoboldPresetProblem catch (e) {
    return e.message;
  }
}
