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

import 'dart:async';
import 'dart:io';

/// Pre-flight validation for the .gguf we are about to hand to KoboldCpp.
///
/// Why this exists (issue #137): `File.existsSync()` is not a strong enough
/// check. A cloud-storage placeholder — OneDrive "Files On-Demand", iCloud
/// Drive, Dropbox Smart Sync — still answers the Win32 attribute query that
/// Dart's `existsSync` uses, and still shows up in a directory listing. So the
/// app lists the model, passes its own existence check, and launches happily.
/// KoboldCpp is frozen Python and resolves the same path through `os.stat`,
/// which can fail outright on a cloud reparse point; it then prints
/// "Cannot find text model file" and exits 2. The user is left staring at
/// "Process exited with code 2" for a file they can plainly see in Explorer.
///
/// Actually opening the file and reading its GGUF magic is the only check that
/// tells "really here" apart from "placeholder", and it doubles as a guard
/// against partial or corrupted downloads.
class ModelFileCheck {
  /// GGUF magic — the first four bytes of every .gguf file ("GGUF").
  static const List<int> _ggufMagic = [0x47, 0x47, 0x55, 0x46];

  /// How long to wait for the first four bytes before assuming the file is not
  /// actually on this machine. A local read returns in microseconds; a
  /// dehydrated cloud file blocks while the sync client fetches gigabytes.
  static const Duration _readTimeout = Duration(seconds: 10);

  /// Shared advice appended wherever a model file turns out to be unreadable.
  /// Also used for the exit-code-2 explanation, so the wording stays identical
  /// whether we caught the problem or KoboldCpp did.
  static const String cloudStorageHint =
      'If your models live in OneDrive, iCloud Drive, or Dropbox, the file may '
      'be "online-only" — it looks present in the file browser, but its '
      'contents are not on this device and KoboldCpp cannot open it. '
      'Right-click the models folder and choose "Always keep on this device", '
      'or move your models somewhere outside the synced folder.';

  /// Returns a human-readable problem description, or null when [modelPath] is
  /// present, readable, and really is a GGUF file.
  ///
  /// Deliberately async: a dehydrated cloud file can block for a long time on
  /// the first read, and doing that synchronously would freeze the UI isolate.
  static Future<String?> validate(String modelPath) async {
    if (modelPath.isEmpty) return null;

    final file = File(modelPath);

    if (!await file.exists()) {
      return 'Model file not found:\n  $modelPath\n'
          'It may have been moved, renamed, or deleted. '
          'Pick the model again in Settings → Backend.';
    }

    RandomAccessFile? handle;
    List<int> header;
    try {
      handle = await file.open(mode: FileMode.read);
      header = await handle.read(_ggufMagic.length).timeout(_readTimeout);
    } on TimeoutException {
      return 'Model file could not be read (timed out):\n  $modelPath\n'
          '$cloudStorageHint';
    } catch (e) {
      return 'Model file could not be read:\n  $modelPath\n  ($e)\n'
          '$cloudStorageHint';
    } finally {
      // close() on a handle whose read already failed can throw again; the
      // validation result is what matters, so never let cleanup mask it.
      try {
        await handle?.close();
      } catch (_) {}
    }

    if (header.length < _ggufMagic.length ||
        !_startsWithMagic(header, _ggufMagic)) {
      return 'Not a valid GGUF model file:\n  $modelPath\n'
          'The file is probably a partial or corrupted download. '
          'Try downloading it again.';
    }

    return null;
  }

  /// Explanation appended when KoboldCpp itself exits with code 2 — its
  /// "Cannot find text model file" path. Our pre-flight catches most of these
  /// first, but KoboldCpp resolves paths through Python and can still reject a
  /// file we were able to read, so the fallback message has to exist.
  static String explainExitCode2(String modelPath) {
    final target = modelPath.isEmpty ? 'the model file' : modelPath;
    return 'KoboldCpp could not open $target.\n$cloudStorageHint';
  }

  static bool _startsWithMagic(List<int> bytes, List<int> magic) {
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }
}
