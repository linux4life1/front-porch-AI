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
/// see `localModelKey`). Only settled answers are kept, true when the model
/// called a tool and false when it chose words; an answer that settled nothing
/// never reaches here. Stored as one JSON map under `tool_verdicts` (the
/// beta-prefixed key on pre-release builds).
///
/// No [notify]: a verdict is not a setting anything repaints for, and the
/// probe that writes it notifies its own listeners.
class ToolVerdictSettings with SettingsBase {
  final Map<String, bool> _verdicts = {};

  bool? verdictFor(String key) => _verdicts[key];

  void load() {
    _verdicts.clear();
    final raw = prefs?.getString(k('tool_verdicts'));
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        if (key is String && value is bool) _verdicts[key] = value;
      });
    } on FormatException catch (e) {
      debugPrint('[ToolVerdicts] ignoring a damaged saved value: $e');
    }
  }

  /// Keeps [supported] for [key]; a retest's answer replaces the old one.
  void remember(String key, bool supported) {
    if (_verdicts[key] == supported) return;
    _verdicts[key] = supported;
    _save();
  }

  /// Drops what is kept for [key]. True when something was.
  bool forget(String key) {
    if (_verdicts.remove(key) == null) return false;
    _save();
    return true;
  }

  void _save() {
    final saved = prefs;
    if (saved == null) return;
    unawaited(saved.setString(k('tool_verdicts'), jsonEncode(_verdicts)));
  }
}
