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

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every setting the app keeps in SharedPreferences, as one JSON document
/// that a backup carries and a restore puts back.
///
/// Keys are stored without the nightly `beta_` prefix, together with the
/// channel they came from, so a stable backup restores into a nightly (and
/// the other way round) onto that build's own keys and never the other
/// channel's. Values carry their type, because JSON alone cannot tell the
/// double 3.0 from the int 3.
class SettingsSnapshot {
  SettingsSnapshot._(this.values, this.hasSecrets, this.root);

  /// Format of the settings document. Bump only for a change an older
  /// reader would get wrong; new keys never need it.
  static const int formatVersion = 1;

  static const String _betaPrefix = 'beta_';

  /// API keys, tokens and sign-ins (unprefixed names). They go into a
  /// backup only when the user says so, and a restore without them leaves
  /// the ones on this machine alone.
  static const Set<String> secretKeys = {
    'remote_api_key',
    'remote_api_keys',
    'hf_token',
    'elevenlabs_api_key',
    'openai_tts_api_key',
    'web_server_ngrok_authtoken',
    'backporch_access_token',
    'backporch_refresh_token',
    'xai_supergrok_session',
    'search_api_key',
  };

  /// Settings that describe this machine rather than the user's choices.
  /// They are never captured and a restore never touches them: putting
  /// another machine's storage folder or window position here would break
  /// the app rather than restore it.
  static const Set<String> machineKeys = {
    'root_path',
    'root_path_beta',
    'window_width',
    'window_height',
    'window_x',
    'window_y',
    'window_maximized',
    'web_server_starting',
  };

  /// Unprefixed key -> value, with only the types SharedPreferences holds.
  final Map<String, Object> values;

  /// Whether [secretKeys] were captured. A snapshot without them is not
  /// "no keys"; it is "keys not included".
  final bool hasSecrets;

  /// The storage folder the snapshot was taken under, used to repoint
  /// absolute paths when it is restored under a different one.
  final String? root;

  /// Reads this build's settings out of [prefs].
  static SettingsSnapshot capture(
    SharedPreferences prefs, {
    required bool isNightly,
    required bool includeSecrets,
    String? root,
  }) {
    final values = <String, Object>{};
    for (final stored in prefs.getKeys()) {
      final name = _ownName(stored, isNightly: isNightly);
      if (name == null || machineKeys.contains(name)) continue;
      if (!includeSecrets && secretKeys.contains(name)) continue;
      final value = prefs.get(stored);
      if (value == null) continue;
      values[name] = value is List ? List<String>.from(value) : value;
    }
    return SettingsSnapshot._(values, includeSecrets, root);
  }

  /// The unprefixed name of [stored] when it belongs to this build's
  /// channel, or null when it belongs to the other one.
  static String? _ownName(String stored, {required bool isNightly}) {
    final beta = stored.startsWith(_betaPrefix);
    if (isNightly != beta) return null;
    return beta ? stored.substring(_betaPrefix.length) : stored;
  }

  /// Writes this snapshot into [prefs] for this build's channel. Settings
  /// the snapshot does not have are removed, except machine keys and, when
  /// the snapshot left secrets out, the secrets already here. Absolute paths
  /// under the old storage folder are moved to [newRoot].
  Future<void> restoreInto(
    SharedPreferences prefs, {
    required bool isNightly,
    String? newRoot,
  }) async {
    String own(String name) => isNightly ? '$_betaPrefix$name' : name;
    for (final stored in prefs.getKeys().toList()) {
      final name = _ownName(stored, isNightly: isNightly);
      if (name == null || machineKeys.contains(name)) continue;
      if (!hasSecrets && secretKeys.contains(name)) continue;
      if (!values.containsKey(name)) await prefs.remove(stored);
    }
    final from = root;
    for (final e in values.entries) {
      if (machineKeys.contains(e.key)) continue;
      final value = _repoint(e.value, from, newRoot);
      final key = own(e.key);
      final ok = switch (value) {
        final bool v => await prefs.setBool(key, v),
        final int v => await prefs.setInt(key, v),
        final double v => await prefs.setDouble(key, v),
        final String v => await prefs.setString(key, v),
        final List<String> v => await prefs.setStringList(key, v),
        _ => true,
      };
      if (!ok) debugPrint('[Backup] could not restore setting ${e.key}');
    }
  }

  static Object _repoint(Object value, String? from, String? to) {
    if (from == null || to == null || from == to || from.isEmpty) {
      return value;
    }
    String move(String s) =>
        s.startsWith(from) ? to + s.substring(from.length) : s;
    return switch (value) {
      final String s => move(s),
      final List<String> l => [for (final s in l) move(s)],
      _ => value,
    };
  }

  /// The settings document.
  String encode() => jsonEncode({
    'format': formatVersion,
    'secrets': hasSecrets,
    'root': ?root,
    'values': {for (final e in values.entries) e.key: _tag(e.value)},
  });

  static Map<String, Object> _tag(Object v) => switch (v) {
    bool() => {'t': 'b', 'v': v},
    int() => {'t': 'i', 'v': v},
    double() => {'t': 'd', 'v': v},
    String() => {'t': 's', 'v': v},
    _ => {'t': 'l', 'v': v},
  };

  /// Parses a settings document. Throws [FormatException] for one this
  /// build cannot read. Entries of an unknown type are skipped, so a newer
  /// app's extra kinds of value cannot stop the rest from restoring.
  static SettingsSnapshot decode(String text) {
    final doc = jsonDecode(text);
    if (doc is! Map) throw const FormatException('settings is not an object');
    final format = doc['format'];
    if (format is! int || format > formatVersion) {
      throw FormatException('settings format $format is newer than this app');
    }
    final raw = doc['values'];
    if (raw is! Map) throw const FormatException('settings has no values');
    final values = <String, Object>{};
    for (final e in raw.entries) {
      final entry = e.value;
      if (e.key is! String || entry is! Map) continue;
      final v = entry['v'];
      final parsed = switch (entry['t']) {
        'b' when v is bool => v,
        'i' when v is int => v,
        'd' when v is num => v.toDouble(),
        's' when v is String => v,
        'l' when v is List => [
          for (final s in v)
            if (s is String) s,
        ],
        _ => null,
      };
      if (parsed != null) values[e.key as String] = parsed;
    }
    final root = doc['root'];
    return SettingsSnapshot._(
      values,
      doc['secrets'] == true,
      root is String ? root : null,
    );
  }
}
