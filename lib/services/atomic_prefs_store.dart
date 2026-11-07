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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// The settings store on Windows and Linux, replacing the plugin's own.
///
/// The stock Windows and Linux stores save by truncating
/// `shared_preferences.json` and writing it again in place. A crash or power
/// cut between the two leaves an empty file, which the stock store then reads
/// as "no settings" without any error, and every setting and saved prompt is
/// gone. This store keeps the same file, name and JSON shape (so it reads
/// what the stock store wrote, and the other way round), but writes a
/// flushed temp file and renames it over the original. A rename either
/// happens or it doesn't, so the file on disk is always a whole old or a
/// whole new store.
///
/// Writes are serialized and coalesced: changes that land while a write is
/// in flight go out together in the next one, and each caller's future
/// completes once a write that includes its change is on disk.
class AtomicPrefsStore extends SharedPreferencesStorePlatform {
  AtomicPrefsStore(
    this._locate, {
    @visibleForTesting Future<void> Function(File tmp, String target)? rename,
    @visibleForTesting this.retryAfter = const Duration(seconds: 2),
  }) : _rename = rename ?? _defaultRename;

  static Future<void> _defaultRename(File tmp, String target) =>
      tmp.rename(target);

  final Future<void> Function(File tmp, String target) _rename;

  /// How long a save that could not land waits before it tries again.
  final Duration retryAfter;
  Timer? _retry;

  /// Makes this the store for `SharedPreferences` on Windows and Linux. It
  /// must run before the first `SharedPreferences.getInstance()`.
  static void install() {
    if (!Platform.isWindows && !Platform.isLinux) return;
    // Only the plugin's own file store is replaced. A test that seeded an
    // in-memory store (setMockInitialValues) keeps it, or the app it boots
    // would read the real settings file instead of what the test set.
    final current = SharedPreferencesStorePlatform.instance;
    if (current is InMemorySharedPreferencesStore ||
        current is AtomicPrefsStore) {
      return;
    }
    SharedPreferencesStorePlatform.instance = AtomicPrefsStore(() async {
      final dir = await getApplicationSupportDirectory();
      return File(p.join(dir.path, 'shared_preferences.json'));
    });
  }

  static const String _defaultPrefix = 'flutter.';

  final Future<File> Function() _locate;
  File? _file;
  Map<String, Object>? _cache;
  Future<Map<String, Object>>? _loading;
  Future<bool> _queue = Future.value(true);
  bool _dirty = false;

  Future<File> _target() async => _file ??= await _locate();

  /// Reads the store once; concurrent first callers share one read. A parse
  /// failure is NOT cached, so startup recovery can repair the file and
  /// read it again.
  Future<Map<String, Object>> _read() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _loading ??= _load().then(
      (values) {
        _loading = null;
        return _cache = values;
      },
      onError: (Object e, StackTrace st) {
        _loading = null;
        return Future<Map<String, Object>>.error(e, st);
      },
    );
  }

  Future<Map<String, Object>> _load() async {
    final file = await _target();
    var values = <String, Object>{};
    if (await file.exists()) {
      final text = await file.readAsString();
      if (text.isNotEmpty) {
        final data = jsonDecode(text);
        // Valid JSON that is not an object is as broken as a torn file: read
        // as empty, the next save would overwrite it. Recovery handles it.
        if (data is! Map) {
          throw const FormatException('settings file is not a JSON object');
        }
        values = data.cast<String, Object>();
      }
    }
    return values;
  }

  Future<bool> _persist() {
    _dirty = true;
    return _queue = _queue.then((_) async {
      if (!_dirty) return true;
      _dirty = false;
      return _writeNow();
    });
  }

  Future<bool> _writeNow() async {
    try {
      final file = await _target();
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_cache ?? {}), flush: true);
      await _renameWithRetry(tmp, file.path);
      return true;
    } catch (e) {
      // The old file is still whole (a failed rename changes nothing) and
      // the new values are still in memory, so nothing is lost yet: mark the
      // store dirty and try again shortly, until it lands.
      debugPrint('[Prefs] could not save settings, retrying soon: $e');
      _dirty = true;
      _retry ??= Timer(retryAfter, () {
        _retry = null;
        if (!_dirty) return;
        _queue = _queue.then((_) {
          if (!_dirty) return true;
          _dirty = false;
          return _writeNow();
        });
      });
      return false;
    }
  }

  /// Windows virus scanners, indexers, OneDrive or another copy of the app
  /// can hold the target open, which fails the rename (dart:io renames with
  /// MoveFileEx and replace-existing) with access denied. A short retry
  /// rides out a brief hold; a longer one goes to the timer in [_writeNow].
  Future<void> _renameWithRetry(File tmp, String target) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await _rename(tmp, target);
        return;
      } on FileSystemException {
        if (attempt >= 4) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 25 << attempt));
      }
    }
  }

  bool _matches(String key, PreferencesFilter filter) =>
      key.startsWith(filter.prefix) &&
      (filter.allowList?.contains(key) ?? true);

  @override
  Future<bool> clear() => clearWithParameters(
    ClearParameters(filter: PreferencesFilter(prefix: _defaultPrefix)),
  );

  @override
  Future<bool> clearWithPrefix(String prefix) => clearWithParameters(
    ClearParameters(filter: PreferencesFilter(prefix: prefix)),
  );

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final values = await _read();
    values.removeWhere((key, _) => _matches(key, parameters.filter));
    return _persist();
  }

  @override
  Future<Map<String, Object>> getAll() => getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: _defaultPrefix)),
  );

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) =>
      getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: prefix)),
      );

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final values = await _read();
    return {
      for (final e in values.entries)
        if (_matches(e.key, parameters.filter)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    final values = await _read();
    values.remove(key);
    return _persist();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final values = await _read();
    values[key] = value;
    return _persist();
  }
}
