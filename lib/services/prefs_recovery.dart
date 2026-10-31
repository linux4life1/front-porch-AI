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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:front_porch_ai/services/atomic_prefs_store.dart';

/// Detects and self-heals a corrupt settings store at startup.
///
/// On Windows and Linux, shared_preferences keeps everything in a single
/// `shared_preferences.json` with no atomic-write or fsync protection, so a
/// crash or power loss mid-write can leave the file full of NUL bytes. The
/// next `SharedPreferences.getInstance()` then throws
/// `FormatException: Unexpected character (at character 1)` — and because
/// startup's very first prefs read happens inside the database-open guard,
/// the app died on the "couldn't open its database" screen with advice that
/// could never fix it (the field-reported failure this class exists for).
///
/// [healIfCorrupt] probes the store before anything else reads it; on the
/// corruption signature it moves the broken file aside (kept as
/// `shared_preferences.json.corrupt` for diagnosis). It then restores the
/// last known-good copy (`shared_preferences.json.good`, refreshed by
/// [snapshotGood]) and only falls back to defaults when there is none, so a
/// torn write costs the changes since the last snapshot, not every setting
/// and saved prompt the user has. macOS uses
/// NSUserDefaults rather than this JSON file, so there is nothing to heal
/// there and the probe simply passes the error through to the startup guard.
class PrefsRecovery {
  PrefsRecovery._();

  /// True when this launch recovered from a corrupt settings file. main.dart
  /// shows a one-time notice so the recovery (and a possibly forgotten
  /// custom storage folder) is never silent.
  static bool recovered = false;

  /// When [recovered] is true, the time of the known-good copy the settings
  /// came back from, or null when no copy existed and defaults are in use.
  static DateTime? restoredFrom;

  static File? _file;
  static bool _locateFailed = false;

  static Future<File?> _settingsFile() async {
    // Only the file our own store owns. A test's in-memory store has none,
    // and repairing the real settings file under it would touch a file the
    // running app never reads.
    if (SharedPreferencesStorePlatform.instance is! AtomicPrefsStore) {
      return null;
    }
    if (_file != null) return _file;
    if (_locateFailed || (!Platform.isWindows && !Platform.isLinux)) {
      return null;
    }
    try {
      final dir = await getApplicationSupportDirectory();
      return _file = File(p.join(dir.path, 'shared_preferences.json'));
    } catch (e) {
      // Logged once: every prompt save asks again.
      _locateFailed = true;
      debugPrint('[Prefs] could not locate settings file: $e');
      return null;
    }
  }

  /// Windows builds before this one named the settings folder
  /// `%APPDATA%\com.antigravity\Front Porch AI` (the old `CompanyName` in
  /// Runner.rc). It is now `%APPDATA%\Front Porch AI`. On the first launch
  /// of each channel this carries the old folder across, so moving it costs
  /// nobody their settings or stored keys. The old folder is left in place.
  ///
  /// Stable and nightly share the one settings file (nightly keys carry
  /// `beta_`), so the move is per channel: whichever channel launches first
  /// must not stop the other from bringing its own settings later.
  static Future<void> moveLegacyWindowsFolder({required bool nightly}) async {
    if (!Platform.isWindows) return;
    if (SharedPreferencesStorePlatform.instance is! AtomicPrefsStore) return;
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.isEmpty) return;
      final legacy = Directory(
        p.join(appData, 'com.antigravity', 'Front Porch AI'),
      );
      final current = await getApplicationSupportDirectory();
      if (p.equals(legacy.path, current.path) || !await legacy.exists()) {
        return;
      }
      final copied = await copyLegacyFiles(legacy, current);
      final merged = await mergeLegacySettingsFile(
        File(p.join(legacy.path, _prefsName)),
        File(p.join(current.path, _prefsName)),
        nightly: nightly,
      );
      debugPrint(
        '[Prefs] old Windows folder: $copied file(s) copied, '
        '${merged ? 'settings brought across' : 'settings already here'}',
      );
    } catch (e) {
      debugPrint('[Prefs] could not move the old settings folder: $e');
    }
  }

  static const String _prefsName = 'shared_preferences.json';

  /// Marks, per channel, that the old folder's settings were brought over.
  static String _movedMarker(bool nightly) =>
      'flutter.${nightly ? 'beta_' : ''}moved_from_legacy_windows_folder';

  /// Copies the files of [from] that [to] does not have (stored keys and
  /// anything else the app keeps there), once: a marker file in [to] records
  /// the copy, so a file removed from the new folder later (a deleted key, a
  /// cleared cache) never comes back from the old one, which stays in place.
  /// The files are shared by both channels, so one copy serves both. The
  /// settings file and its own copies are left to
  /// [mergeLegacySettingsFile]; an existing file is never overwritten.
  /// Returns how many files were copied.
  static Future<int> copyLegacyFiles(Directory from, Directory to) async {
    if (!await from.exists()) return 0;
    final marker = File(p.join(to.path, _filesMovedMarker));
    if (await marker.exists()) return 0;
    var copied = 0;
    await for (final entity in from.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: from.path);
      if (rel.startsWith(_prefsName)) continue;
      final target = File(p.join(to.path, rel));
      if (await target.exists()) continue;
      await target.parent.create(recursive: true);
      await entity.copy(target.path);
      copied++;
    }
    // Written only after every file is across: a copy cut short runs again.
    await to.create(recursive: true);
    await marker.writeAsString(DateTime.now().toUtc().toIso8601String());
    return copied;
  }

  static const String _filesMovedMarker = '.moved_from_com.antigravity';

  /// Brings this channel's settings from the old settings file into the
  /// new one, once per channel. The old values win for this channel's keys:
  /// before this runs, the only ones in the new file are stray writes from
  /// the other channel's build. The other channel's keys are left exactly as
  /// they are. Returns whether anything was written.
  static Future<bool> mergeLegacySettingsFile(
    File legacy,
    File current, {
    required bool nightly,
  }) async {
    if (!await legacy.exists()) return false;
    final old = jsonDecode(await legacy.readAsString());
    if (old is! Map) return false;
    var now = <String, Object?>{};
    if (await current.exists()) {
      final text = await current.readAsString();
      if (text.trim().isNotEmpty) {
        final decoded = jsonDecode(text);
        if (decoded is Map) now = decoded.cast<String, Object?>();
      }
    }
    final marker = _movedMarker(nightly);
    if (now[marker] == true) return false;
    // A blank store next to a good copy that says "moved" is a torn write
    // of an already moved file: the good copy goes back, not the old folder.
    if (await _goodCopyHas(current, marker)) return false;
    for (final e in old.entries) {
      final key = e.key;
      if (key is! String || !key.startsWith('flutter.')) continue;
      final beta = key.startsWith('flutter.beta_');
      if (beta == nightly) now[key] = e.value;
    }
    now[marker] = true;
    await current.parent.create(recursive: true);
    final tmp = File('${current.path}.move.tmp');
    await tmp.writeAsString(jsonEncode(now), flush: true);
    await tmp.rename(current.path);
    return true;
  }

  static Future<bool> _goodCopyHas(File current, String key) async {
    final good = File('${current.path}.good');
    try {
      if (!await good.exists()) return false;
      final decoded = jsonDecode(await good.readAsString());
      return decoded is Map && decoded[key] == true;
    } catch (e) {
      debugPrint('[Prefs] could not read the good settings copy: $e');
      return false;
    }
  }

  /// Probes SharedPreferences and heals the JSON store if it is corrupt.
  /// Never throws: if healing is impossible the original error simply
  /// resurfaces at the next `getInstance()` call, where the startup guard
  /// reports it accurately.
  static Future<void> healIfCorrupt() async {
    await restoreBlankStore();
    final file = await _settingsFile();
    try {
      await SharedPreferences.getInstance();
      await snapshotGood();
      return;
    } on FormatException catch (e) {
      // The corruption signature. getInstance() clears its cached completer
      // on failure, so a retry after repair genuinely re-reads the file.
      debugPrint('[Prefs] settings file is corrupt: $e');
    } catch (e) {
      // Not a parse failure (permissions, platform channel, …) — moving the
      // file aside can't help, and might destroy a readable store.
      debugPrint('[Prefs] settings probe failed (not corruption): $e');
      return;
    }

    if (file == null) return;
    if (!await moveCorruptFileAside(file)) return;
    final copyTime = await restoreGoodCopy(file);

    try {
      await SharedPreferences.getInstance();
      recovered = true;
      restoredFrom = copyTime;
      debugPrint(
        '[Prefs] recovered from corrupt settings; broken file kept at '
        '${file.path}.corrupt, '
        '${copyTime == null ? 'defaults in use' : 'restored copy from $copyTime'}',
      );
    } catch (e) {
      debugPrint('[Prefs] settings still unreadable after recovery: $e');
    }
  }

  /// A crash between the plugin's truncate and its write leaves an empty
  /// file, which the plugin reads as "no settings" without any error. So a
  /// blank or missing store next to a good copy is a torn write too. It must
  /// be put back before the first getInstance() caches the empty map, and
  /// before [moveLegacyWindowsFolder], which would otherwise read the blank
  /// file as "never moved" and roll this channel back to the old folder's
  /// settings. Safe to call more than once.
  static Future<void> restoreBlankStore() async {
    final file = await _settingsFile();
    if (file == null || !await isBlankStore(file)) return;
    final copyTime = await restoreGoodCopy(file);
    if (copyTime == null) return;
    recovered = true;
    restoredFrom = copyTime;
    debugPrint('[Prefs] settings file was blank; restored $copyTime copy');
  }

  /// Refreshes the known-good copy of the settings file. Call it after the
  /// store was read cleanly and after writes worth protecting. Never throws.
  static Future<void> snapshotGood() {
    // One at a time: two copies racing on the same temp file could rename a
    // half-written one into place.
    return _snapshotting = _snapshotting.then((_) async {
      final file = await _settingsFile();
      if (file == null) return;
      await writeGoodCopy(file);
    });
  }

  static Future<void> _snapshotting = Future<void>.value();

  /// Copies [file] to `<name>.good` through a temp file and a rename, and
  /// only when it parses as a JSON object, so a torn store never replaces a
  /// good copy. Returns whether a copy was written. Pure file I/O so tests
  /// can exercise it directly.
  static Future<bool> writeGoodCopy(File file) async {
    try {
      if (!await file.exists()) return false;
      final text = await file.readAsString();
      if (!_isSettingsJson(text)) {
        debugPrint('[Prefs] settings file not parseable; good copy kept');
        return false;
      }
      final tmp = File('${file.path}.good.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename('${file.path}.good');
      return true;
    } catch (e) {
      debugPrint('[Prefs] could not refresh the good settings copy: $e');
      return false;
    }
  }

  /// Puts `<name>.good` back in place of [file] when it parses. Returns the
  /// copy's modified time, or null when there was no usable copy.
  static Future<DateTime?> restoreGoodCopy(File file) async {
    try {
      final good = File('${file.path}.good');
      if (!await good.exists()) return null;
      final text = await good.readAsString();
      if (!_isSettingsJson(text)) {
        debugPrint('[Prefs] good settings copy is unreadable too');
        return null;
      }
      final when = await good.lastModified();
      final tmp = File('${file.path}.restore.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(file.path);
      return when;
    } catch (e) {
      debugPrint('[Prefs] could not restore the good settings copy: $e');
      return null;
    }
  }

  /// True when [file] is missing or holds only whitespace, which the
  /// settings plugin silently reads as an empty store.
  static Future<bool> isBlankStore(File file) async {
    try {
      if (!await file.exists()) return true;
      if (await file.length() > 64) return false;
      return (await file.readAsString()).trim().isEmpty;
    } catch (e) {
      debugPrint('[Prefs] could not inspect the settings file: $e');
      return false;
    }
  }

  static bool _isSettingsJson(String text) {
    try {
      return jsonDecode(text) is Map;
    } on FormatException {
      return false;
    }
  }

  /// Moves [file] to `<name>.corrupt`, replacing any previous backup, so the
  /// broken content is preserved for diagnosis instead of deleted. Returns
  /// false (without throwing) when the file is missing or cannot be moved.
  /// Public and pure file I/O so tests can exercise it directly.
  static Future<bool> moveCorruptFileAside(File file) async {
    try {
      if (!await file.exists()) return false;
      final backup = File('${file.path}.corrupt');
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
      return true;
    } catch (e) {
      debugPrint('[Prefs] could not move corrupt settings file aside: $e');
      return false;
    }
  }
}
