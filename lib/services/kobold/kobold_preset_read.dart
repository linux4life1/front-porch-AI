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

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'kcpps_codec.dart';
import 'kcpps_old_names.dart';
import 'kcpps_risky_keys.dart';

/// A preset that cannot be launched from, with the reason in plain words.
class KoboldPresetProblem implements Exception {
  const KoboldPresetProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads the preset at [kcppsPath], or throws [KoboldPresetProblem] and
/// nothing else: a file that cannot be opened, is not text, is not a
/// config, or holds a number too large to use.
Future<KcppsOk> readKoboldPreset(String kcppsPath) async {
  final name = path.basename(kcppsPath);
  final String text;
  try {
    text = await File(kcppsPath).readAsString();
  } on Object catch (e) {
    debugPrint('[Kobold] could not open the preset $kcppsPath: $e');
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

/// Why a launch from [preset] must not go ahead, in plain words, or null:
/// it asks KoboldCpp to run a program or open itself to the internet (see
/// [kcppsRiskyPresetProblem]), or it was saved by an older KoboldCpp and
/// names settings the old way (see [kcppsOldNamesProblem]). The one gate a
/// preset passes wherever it reaches the engine: the check before a start,
/// the config every start, swap and trial is built from, and a trial loaded
/// by name all ask it, so what the user is told and what is refused cannot
/// disagree.
String? kcppsPresetProblem(Map<String, dynamic> preset) =>
    kcppsRiskyPresetProblem(preset) ?? kcppsOldNamesProblem(preset);

/// Why a launch from [kcppsPath] cannot go ahead, in plain words, or null
/// when it can (or there is no preset): the file cannot be read, or it is
/// refused by [kcppsPresetProblem]. For the screens that start the engine:
/// the launch itself only logs this, so without the check a broken preset
/// makes Start look like it did nothing.
Future<String?> koboldPresetProblem(String? kcppsPath) async {
  if (kcppsPath == null || kcppsPath.isEmpty) return null;
  try {
    return kcppsPresetProblem((await readKoboldPreset(kcppsPath)).raw);
  } on KoboldPresetProblem catch (e) {
    return e.message;
  } on Object catch (e) {
    // Nothing above should get here. If it does, it is still an answer
    // for the screen, never an error thrown at it.
    debugPrint('[Kobold] could not check the preset $kcppsPath: $e');
    return 'The preset "${path.basename(kcppsPath)}" can\'t be read. Pick '
        'another preset, or none, in Settings.';
  }
}
