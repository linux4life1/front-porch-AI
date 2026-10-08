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

import 'package:front_porch_ai/app_version.dart';

/// What a kept "no" was given under: the app version and, for the local
/// engine, the KoboldCpp version (empty for a remote backend, or while the
/// engine has not been looked at yet).
///
/// A "no" keeps native tool calls off for a model until something asks again,
/// and a wrong one is easy to get from a missing engine feature or a chat
/// template that has since been fixed. So it is asked again, once, when the
/// engine or the app changes. A "yes" is not stamped and stays.
String toolVerdictStamp({String? engineVersion}) =>
    '$appVersion|${engineVersion ?? ''}';

/// Whether a "no" kept under [kept] still stands under [now]: the app is the
/// same, and so is the engine when [now] knows which it is. A "no" kept before
/// stamps existed has an empty one and is asked again once.
bool toolVerdictStampHolds(String kept, String now) {
  final given = _split(kept);
  final current = _split(now);
  if (given.app != current.app) return false;
  return current.engine.isEmpty || current.engine == given.engine;
}

({String app, String engine}) _split(String stamp) {
  final at = stamp.indexOf('|');
  return at < 0
      ? (app: stamp, engine: '')
      : (app: stamp.substring(0, at), engine: stamp.substring(at + 1));
}
