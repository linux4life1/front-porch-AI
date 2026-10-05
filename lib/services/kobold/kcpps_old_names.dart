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

import 'kcpps_risky_keys.dart';

/// A setting an older KoboldCpp saved under a name it has since replaced.
/// KoboldCpp turns the old name into the current setting in
/// `convert_invalid_args` when it starts, but only when the file lacks the
/// current name. A live reload fills in every missing setting from the
/// running engine first, so the current name is never missing then and the
/// old one is dropped without a word.
class _Renamed {
  const _Renamed(
    this.old,
    this.current, {
    this.acts = kcppsIsOn,
    this.update,
    this.inverted = false,
    this.nullIsMissing = false,
    this.keepOld = false,
  });

  final String old;
  final String current;

  /// KoboldCpp's own test for acting on the old name's value.
  final bool Function(Object? value) acts;

  /// What KoboldCpp sets for the old value; left out, the current name
  /// takes the value as it is ([inverted]: its opposite).
  final Map<String, Object?> Function(Object? value)? update;
  final bool inverted;

  /// KoboldCpp counts the current name as missing when it is null too.
  final bool nullIsMissing;

  /// The app's own writer writes both spellings of the card and the batch,
  /// so an update leaves the old one beside the current one.
  final bool keepOld;

  bool usedIn(Map<String, dynamic> preset) =>
      preset.containsKey(old) &&
      acts(preset[old]) &&
      (!preset.containsKey(current) ||
          (nullIsMissing && preset[current] == null));

  Map<String, Object?> updateFor(Object? value) =>
      update?.call(value) ?? {current: inverted ? !kcppsIsOn(value) : value};
}

/// KoboldCpp acts on the key whatever it holds: `flashattention: false` is
/// the setting, not nothing.
bool _present(Object? value) => true;

/// KoboldCpp reads `hordeconfig` when it is on and its first entry, the
/// model name, is not empty.
bool _hordeActs(Object? value) =>
    value is List ? value.isNotEmpty && value.first != '' : kcppsIsOn(value);

/// [value] as KoboldCpp indexes it: a list as it is, a text by its letters.
/// Anything else stops KoboldCpp at launch, so the update drops it.
List<Object?> _parts(Object? value) => switch (value) {
  final List<dynamic> list => list,
  final String text => text.split(''),
  _ => const [],
};

/// [value] as Python's `int()` reads it, or null where KoboldCpp would stop.
int? _whole(Object? value) => switch (value) {
  final bool flag => flag ? 1 : 0,
  final int n => n,
  final double d => d.isFinite ? d.truncate() : null,
  final String text => int.tryParse(text.trim()),
  _ => null,
};

Map<String, Object?> _sdConfig(Object? value) {
  final parts = _parts(value);
  return {
    if (parts.isNotEmpty) 'sdmodel': parts[0],
    if (parts.length > 1) 'sdclamped': 512,
    if (parts.length > 2) 'sdthreads': ?_whole(parts[2]),
    if (parts.length > 3) 'sdquant': parts[3] == 'quant' ? 2 : 0,
  };
}

Map<String, Object?> _hordeConfig(Object? value) {
  final parts = _parts(value);
  return {
    if (parts.isNotEmpty) 'hordemodelname': parts[0],
    if (parts.length > 1) 'hordegenlen': ?_whole(parts[1]),
    if (parts.length > 2) 'hordemaxctx': ?_whole(parts[2]),
    if (parts.length > 4) ...{
      'hordekey': parts[3],
      'hordeworkername': parts[4],
    },
  };
}

/// Every old name KoboldCpp 1.122.1's `convert_invalid_args` turns into a
/// current setting, in its order, with its own tests. Not here: `sdt5xxl`,
/// renamed `sdllm` only in 1.122.1, so it is still the setting itself for
/// 1.117.1, which the app also runs and whose own export writes it alone.
const List<_Renamed> _renamed = [
  _Renamed('usecublas', 'usecuda', keepOld: true),
  _Renamed('blasbatchsize', 'batchsize', keepOld: true),
  _Renamed('sdconfig', 'sdmodel', update: _sdConfig),
  _Renamed(
    'hordeconfig',
    'hordemodelname',
    acts: _hordeActs,
    update: _hordeConfig,
  ),
  _Renamed('noblas', 'usecpu', update: _cpuOnly),
  _Renamed('sdnotile', 'sdtiledvae', acts: _present, update: _tiling),
  _Renamed('sdclipl', 'sdclip1', acts: _present),
  _Renamed('sdclipg', 'sdclip2', acts: _present),
  _Renamed('sdgendefaults', 'gendefaults', acts: _present),
  _Renamed(
    'flashattention',
    'noflashattention',
    acts: _present,
    inverted: true,
  ),
  _Renamed('useswa', 'noswa', acts: _present, inverted: true),
  _Renamed(
    'sdclipgpu',
    'sdclipdevice',
    acts: _present,
    update: _clipDevice,
    nullIsMissing: true,
  ),
  _Renamed(
    'sdvaecpu',
    'sdvaedevice',
    acts: _present,
    update: _vaeDevice,
    nullIsMissing: true,
  ),
];

Map<String, Object?> _cpuOnly(Object? value) => {'usecpu': true};

/// `sdnotile: true` is no tiling. `false` is the engine's own default,
/// which differs by version and is what leaving the setting out gives.
Map<String, Object?> _tiling(Object? value) =>
    kcppsIsOn(value) ? {'sdtiledvae': 0} : {};

/// KoboldCpp's device numbers: -1 the main graphics card, -2 the processor.
Map<String, Object?> _clipDevice(Object? value) => {
  'sdclipdevice': kcppsIsOn(value) ? -1 : -2,
};

Map<String, Object?> _vaeDevice(Object? value) => {
  'sdvaedevice': kcppsIsOn(value) ? -2 : -1,
};

/// The old setting names [preset] uses without their current names: the
/// ones KoboldCpp reads at Start and a live reload drops.
List<String> kcppsOldNames(Map<String, dynamic> preset) => [
  for (final r in _renamed)
    if (r.usedIn(preset)) r.old,
];

/// Why [preset] must not be launched from, in plain words, or null: it was
/// saved by an older KoboldCpp and uses an old setting name without its
/// current one, so it would run one way at Start and another after the
/// first swap. The fix is one Save in the preset editor
/// ([kcppsWithCurrentNames]).
String? kcppsOldNamesProblem(Map<String, dynamic> preset) {
  final names = kcppsOldNames(preset);
  if (names.isEmpty) return null;
  return 'This preset was saved by an older KoboldCpp, so it has to be '
      'updated once before it can be used (old settings: ${names.join(', ')}). '
      'Open it from "KoboldCpp presets…" on the Backend tab in Settings, on '
      'the computer, and press Save. Or pick another preset.';
}

/// [preset] with every old setting it uses written under its current name,
/// with what KoboldCpp itself gives it at Start, so the preset runs as it
/// did. The old name goes, except for the card and the batch, which the
/// app's writer keeps under both spellings. Everything else is as written.
Map<String, dynamic> kcppsWithCurrentNames(Map<String, dynamic> preset) {
  final out = Map<String, dynamic>.of(preset);
  for (final r in _renamed) {
    if (!r.usedIn(preset)) continue;
    out.addAll(r.updateFor(preset[r.old]));
    if (!r.keepOld) out.remove(r.old);
  }
  return out;
}
