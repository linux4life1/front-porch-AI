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
import 'package:path/path.dart' as p;

/// Prefix of every config the app stages for KoboldCpp to launch or
/// live-load. Files with it are the app's own and are never listed as
/// presets.
const String kStagedConfigPrefix = 'fpai-';

/// The staged config for the chat model.
const String kStagedChatConfig = '${kStagedConfigPrefix}chat.kcpps';

/// The one address the app's KoboldCpp listens on and the app talks to: this
/// computer only. KoboldCpp's own default is every network the computer is
/// on. The command line stays as it is, so the address rides in the config
/// the app stages for a launch or a swap: KoboldCpp applies `host` from
/// `--config` at launch and never changes it on a live reload.
const String kKoboldHost = '127.0.0.1';

/// KoboldCpp's own idle unload, off. The app runs the unload itself, and
/// loads chat's setup back before the next request; KoboldCpp's timer has no
/// way to do that, so a preset's own value would leave an engine with no
/// model behind the app's back. Like [kKoboldHost] it rides in the staged
/// config, over whatever a preset said: KoboldCpp reads it from `--config` at
/// launch and ignores it on a live reload.
const int kKoboldAdminUnloadTimeout = 0;

/// A role's config as staged for the engine: the file name to reload by,
/// a key for its content (two roles with the same content are the same
/// thing to the engine), and what it loads.
class KoboldStagedRole {
  const KoboldStagedRole({
    required this.filename,
    required this.path,
    required this.key,
    required this.modelPath,
    required this.kcppsPath,
    required this.expectedModel,
    required this.contextSize,
  });

  final String filename;
  final String path;
  final String key;
  final String modelPath;
  final String kcppsPath;

  /// The model name KoboldCpp reports once this config is loaded.
  final String expectedModel;

  /// The context KoboldCpp runs once this config is loaded. Null when the
  /// config sets none: KoboldCpp's own default differs by version (1.117.1
  /// runs 12,288, 1.122.1 runs 16,384).
  final int? contextSize;
}

/// Write [json] as `[dir]/[name]`, whole or not at all: a temp file is
/// written first and renamed over the target, so KoboldCpp can never read a
/// half-written config.
Future<File> stageKoboldConfig(String dir, String name, String json) async {
  await Directory(dir).create(recursive: true);
  final target = File(p.join(dir, name));
  // A swap asks for its config before every call. When nothing changed,
  // the file is already right and is left alone.
  try {
    if (await target.exists() && await target.readAsString() == json) {
      return target;
    }
  } on FileSystemException {
    // Unreadable: write it again below.
  }
  final temp = File('${target.path}.tmp');
  await temp.writeAsString(json, flush: true);
  try {
    return await temp.rename(target.path);
  } on FileSystemException {
    // Windows will not rename over a file another process has open.
    if (await target.exists()) await target.delete();
    return temp.rename(target.path);
  }
}

/// The config staged as [name] in [dir], or null when there is none or it
/// cannot be read.
Future<String?> readStagedKoboldConfig(String dir, String name) async {
  final file = File(p.join(dir, name));
  try {
    return await file.readAsString();
  } on FileSystemException catch (e) {
    debugPrint('[Kobold] ${file.path} could not be read: $e');
    return null;
  }
}

/// True for a file the app wrote for its own use: a staged config, or the
/// one-setting batch file older versions left in the engine folder.
bool isAppOwnedKcpps(String path) {
  final name = p.basename(path);
  return name.startsWith(kStagedConfigPrefix) ||
      name == 'fpai_batch_override.kcpps';
}

/// Remove the batch file older versions wrote into the engine folder. It
/// showed up in the preset list as if the user had made it.
Future<void> removeLegacyBatchOverride(String binDir) async {
  final file = File(p.join(binDir, 'fpai_batch_override.kcpps'));
  try {
    if (await file.exists()) await file.delete();
  } on FileSystemException catch (e) {
    debugPrint('[Kobold] could not remove ${file.path}: $e');
  }
}
