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

import 'package:flutter/foundation.dart';

import 'settings_base.dart';

/// Which models can answer with native tool calls, kept across restarts so a
/// model that was already tried is not tested again every time the app opens.
///
/// Keys are the eval identity of the model (`evalBackendIdentityFor`): the
/// engine and host, and the model by name (a local file by its name and size,
/// see `localModelKey`, read once per load by `LocalModelKeys`). Only settled
/// answers are kept, true when the model called a tool and false when it chose
/// words; an answer that settled nothing never reaches here. A "no" is kept
/// with the stamp (app and engine versions) it was given under, so it can be
/// asked again when those change; a "yes" has none. Stored as one JSON map
/// under `tool_verdicts` (the beta-prefixed key on pre-release builds): `true`
/// for a yes, the stamp as a string for a no (a bare `false`, from before
/// stamps, is a no of unknown stamp).
///
/// No [notify]: a verdict is not a setting anything repaints for, and the
/// probe that writes it notifies its own listeners.
class ToolVerdictSettings with SettingsBase {
  final Map<String, bool> _verdicts = {};
  final Map<String, String> _stamps = {};

  bool? verdictFor(String key) => _verdicts[key];

  /// What a kept "no" was given under; null for a yes, or an unknown key.
  String? stampFor(String key) => _stamps[key];

  void load() {
    _verdicts.clear();
    _stamps.clear();
    final raw = prefs?.getString(k('tool_verdicts'));
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        if (key is! String) return;
        if (value == true) {
          _verdicts[key] = true;
        } else if (value == false) {
          _verdicts[key] = false;
          _stamps[key] = '';
        } else if (value is String) {
          _verdicts[key] = false;
          _stamps[key] = value;
        }
      });
    } on FormatException catch (e) {
      debugPrint('[ToolVerdicts] ignoring a damaged saved value: $e');
    }
  }

  /// Keeps [supported] for [key]; a retest's answer replaces the old one. A
  /// "no" is kept with the [stamp] it was given under.
  void remember(String key, bool supported, {String stamp = ''}) {
    final same =
        _verdicts[key] == supported && (supported || _stamps[key] == stamp);
    if (same) return;
    _verdicts[key] = supported;
    if (supported) {
      _stamps.remove(key);
    } else {
      _stamps[key] = stamp;
    }
    _save();
  }

  /// Drops what is kept for [key]. True when something was.
  bool forget(String key) {
    if (_verdicts.remove(key) == null) return false;
    _stamps.remove(key);
    _save();
    return true;
  }

  void _save() {
    final saved = prefs;
    if (saved == null) return;
    final entries = {
      for (final e in _verdicts.entries)
        e.key: e.value ? true : (_stamps[e.key] ?? ''),
    };
    unawaited(saved.setString(k('tool_verdicts'), jsonEncode(entries)));
  }
}
