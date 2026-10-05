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

/// Settings that make KoboldCpp run a program or open itself to the internet
/// when it applies a config: at start from `--config`, and for most of them
/// on a live reload too.
const List<String> _kRiskyKeys = [
  // Downloads a list of programs and starts them.
  'mcpfile',
  // Runs a command (a live reload runs it on engines before 1.114).
  'onready',
  // Opens a public tunnel to the engine.
  'remotetunnel',
  // Lends the graphics card to strangers (the AI Horde).
  'hordekey',
  // Serves any file it is pointed at to whoever asks.
  'preloadstory',
  // Loads another config, from anywhere.
  'baseconfig',
];

/// Why a launch from [preset] must not go ahead, in plain words, or null:
/// the preset asks KoboldCpp to run a program or open itself to the
/// internet. The one place this is decided: the check before a start and the
/// config every start, swap and trial is built from both ask it, so what the
/// user is told and what is refused cannot disagree.
///
/// KoboldCpp reads each setting as Python reads a value: anything but null,
/// false, 0, empty text, an empty list or an empty map is on, so the text
/// "false" is on. `rpcmode` is risky only as `host`, which makes the engine
/// a network service; `connect` only sends work out. A KoboldCpp export
/// carries all of these, switched off, and passes.
String? kcppsRiskyPresetProblem(Map<String, dynamic> preset) {
  final keys = [
    for (final key in _kRiskyKeys)
      if (_isOn(preset[key])) key,
    if (preset['rpcmode'] == 'host') 'rpcmode',
  ];
  if (keys.isEmpty) return null;
  return 'This preset asks KoboldCpp to run a program or open itself to the '
      'internet (${keys.join(', ')}). The app does not start presets like '
      'that: remove those settings from the file, or pick another preset.';
}

/// [value] as Python reads it: on unless null, false, zero, empty text, an
/// empty list or an empty map.
bool _isOn(Object? value) => switch (value) {
  null => false,
  final bool flag => flag,
  final num n => n != 0,
  final String text => text.isNotEmpty,
  final List<dynamic> list => list.isNotEmpty,
  final Map<dynamic, dynamic> map => map.isNotEmpty,
  _ => true,
};
