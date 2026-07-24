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

/// Finds and deletes the model files only the retired Python engines could
/// read (sidecar-retirement playbook rule 4: never silently delete user
/// downloads — offer them in a cleanup UI with sizes, in the release where
/// the sidecars are actually removed). One scanner and ONE applier, shared
/// by the desktop Settings card and the web Settings page.
///
/// What is (and isn't) offered:
/// - Whisper: everything under `system/whisper_models/` EXCEPT `sherpa/`
///   (the CTranslate2 downloads; the sherpa engine can't read them).
/// - Kokoro: the legacy `kokoro-v1.0.onnx` + `voices-v1.0.bin` pair (the
///   sherpa bundle lives in its own `sherpa-v1_0/` subdir).
/// - Piper: legacy rhasspy `.onnx` voice models under
///   `system/piper_voices/` — the `.onnx.json` configs are KEPT (they are
///   the installed-voice registry the voice manager lists from).
/// - The expression classifier's HuggingFace hub cache is NOT offered:
///   the native engine still reads it as-is.
class LegacyModelGroup {
  final String label;
  final List<String> paths;
  final int bytes;
  const LegacyModelGroup(this.label, this.paths, this.bytes);
}

class LegacyModelCleanup {
  LegacyModelCleanup._();

  /// Scans [root] (the app's storage root) for reclaimable legacy model
  /// files. Groups with nothing on disk are omitted; an empty list means
  /// the cleanup UI should not appear at all.
  static Future<List<LegacyModelGroup>> scan(String root) async {
    final groups = <LegacyModelGroup>[];

    // Whisper: CT2 downloads — anything in whisper_models but sherpa/.
    final whisperDir = Directory(p.join(root, 'system', 'whisper_models'));
    if (whisperDir.existsSync()) {
      final paths = <String>[];
      var bytes = 0;
      await for (final e in whisperDir.list(followLinks: false)) {
        if (p.basename(e.path) == 'sherpa') continue;
        paths.add(e.path);
        bytes += await _sizeOf(e);
      }
      if (paths.isNotEmpty && bytes > 0) {
        groups.add(
          LegacyModelGroup('Old voice-input (Whisper) models', paths, bytes),
        );
      }
    }

    // Kokoro: the two legacy files next to the sherpa-v1_0/ bundle dir.
    final kokoroDir = p.join(root, 'system', 'kokoro_models');
    final kokoroPaths = <String>[];
    var kokoroBytes = 0;
    for (final name in ['kokoro-v1.0.onnx', 'voices-v1.0.bin']) {
      final f = File(p.join(kokoroDir, name));
      if (f.existsSync()) {
        kokoroPaths.add(f.path);
        kokoroBytes += await f.length();
      }
    }
    if (kokoroPaths.isNotEmpty) {
      groups.add(
        LegacyModelGroup(
          'Old Kokoro speech model',
          kokoroPaths,
          kokoroBytes,
        ),
      );
    }

    // Piper: legacy rhasspy .onnx voices (keep the .onnx.json registry).
    final piperDir = Directory(p.join(root, 'system', 'piper_voices'));
    if (piperDir.existsSync()) {
      final paths = <String>[];
      var bytes = 0;
      await for (final e in piperDir.list(followLinks: false)) {
        if (e is! File || !e.path.endsWith('.onnx')) continue;
        paths.add(e.path);
        bytes += await e.length();
      }
      if (paths.isNotEmpty) {
        groups.add(
          LegacyModelGroup('Old Piper voice files', paths, bytes),
        );
      }
    }

    return groups;
  }

  /// Deletes everything [scan] finds under [root] and returns the bytes
  /// freed. Rescans server-side on purpose — callers never supply paths,
  /// so a stale or malicious client can only ever delete what the scanner
  /// itself classified as legacy.
  static Future<int> reclaim(String root) async {
    var freed = 0;
    for (final group in await scan(root)) {
      for (final path in group.paths) {
        if (!p.isWithin(root, path)) continue;
        try {
          final type = FileSystemEntity.typeSync(path, followLinks: false);
          if (type == FileSystemEntityType.directory) {
            final dir = Directory(path);
            freed += await _sizeOf(dir);
            await dir.delete(recursive: true);
          } else if (type != FileSystemEntityType.notFound) {
            final f = File(path);
            freed += await f.length();
            await f.delete();
          }
        } catch (_) {
          // A locked/vanished file shouldn't abort the rest of the sweep.
        }
      }
    }
    return freed;
  }

  static Future<int> _sizeOf(FileSystemEntity e) async {
    if (e is File) return e.length();
    if (e is Directory) {
      var total = 0;
      try {
        await for (final child in e.list(
          recursive: true,
          followLinks: false,
        )) {
          if (child is File) total += await child.length();
        }
      } catch (_) {}
      return total;
    }
    return 0;
  }

  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}
