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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/storage/user_audio_store.dart';
import 'package:front_porch_ai/ui/widgets/guarded_picker.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

/// The desktop file-import behind the ambience library's "From a file…":
/// open the audio category through
/// [GuardedPicker.pickFiles] (MP3 only), copy by file path into
/// `$rootPath/audio/`, and run the header + load-test validation. Returns
/// the bare name to store, an error to surface, and a note when the load
/// test was skipped. A cancel is a silent null — the same as any picker.
Future<({String? name, String? error, String? note})> pickCustomAmbience(
  BuildContext context,
  StorageService storage,
) async {
  final picked = await GuardedPicker.pickFiles(
    context,
    category: PickerPrefs.catAudio,
    type: FileType.custom,
    allowedExtensions: const ['mp3'],
    dialogTitle: 'Choose a custom scene sound',
  );
  if (picked == null || picked.files.isEmpty) {
    return (name: null, error: null, note: null);
  }
  final file = picked.files.first;
  final path = await PickerPrefs.localPathOrTemp(file);
  if (path == null || path.isEmpty) {
    return (name: null, error: 'Could not read that file.', note: null);
  }
  return UserAudioStore.storeUserAudioPath(path, storage);
}
