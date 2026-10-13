// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import '../settings_base.dart';

/// Porch Life "Time-skip bridge": when a message skips a day or more, a
/// narrator card fills in the gap before the character replies.
///
/// Defaults ON. It costs one short model call, and only on a turn that
/// skips at least a day, which a story does a handful of times. It needs
/// Passage of Time, because a frozen clock never skips. Read live from the
/// preferences, so there is no load step to keep in step.
mixin TimeSkipBridgeSetting on SettingsBase {
  static const _key = 'time_skip_bridge_enabled';

  bool get timeSkipBridgeEnabled => prefs?.getBool(k(_key)) ?? true;

  Future<void> setTimeSkipBridgeEnabled(bool value) async {
    await prefs?.setBool(k(_key), value);
    notify();
  }
}
