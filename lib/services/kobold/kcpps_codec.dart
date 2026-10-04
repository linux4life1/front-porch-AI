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

import 'package:path/path.dart' as p;

import 'kobold_capabilities.dart';
import 'kobold_launch_config.dart';

/// Every key this app reads or writes. Anything else in a file is kept as
/// it was.
const Set<String> _managedKeys = {
  'model_param',
  'model',
  'contextsize',
  'batchsize',
  'blasbatchsize',
  'threads',
  'gpulayers',
  'autofitpadding',
  'usemmap',
  'usemlock',
  'quantkv',
  'noflashattention',
  'flashattention',
  'usecuda',
  'usecublas',
  'usehipblas',
  'usevulkan',
  'noswa',
  'useswa',
  'swapadding',
  'nofastforward',
  'noshift',
  'smartcache',
  'jinja',
  'mmproj',
  'mmprojcpu',
  'moecpu',
  'autofit',
  'nommq',
  'draftmodel',
};

/// Words in a `usecuda` list the codec reads into fields of its own: the
/// mode the writer always gives, and MMQ.
const Set<String> _cudaWords = {'normal', 'mmq', 'nommq'};

/// What reading a `.kcpps` gave.
sealed class KcppsRead {
  const KcppsRead();
}

class KcppsOk extends KcppsRead {
  const KcppsOk(this.config, {this.notes = const [], this.raw = const {}});

  /// The settings the app can show and edit. It is a summary: a second
  /// graphics card, the CUDA options or a MoE layer count do not fit in it.
  /// A launch therefore runs [raw], not this.
  final KoboldLaunchConfig config;

  /// Plain-words remarks about what [config] changed on the way in, for a
  /// screen that shows or edits it. A launch does not use them: it runs
  /// [raw] and reports what it changes itself.
  final List<String> notes;

  /// The file exactly as it was written.
  final Map<String, dynamic> raw;

  /// Settings in the file that this app does not manage.
  List<String> get unmanagedKeys => config.extras.keys.toList()..sort();
}

/// The file is not a config at all (not JSON, or not a JSON object).
class KcppsBroken extends KcppsRead {
  const KcppsBroken(this.reason);
  final String reason;
}

/// Read any `.kcpps`: this app's own, or one saved from KoboldCpp's
/// launcher. Old key names are understood.
///
/// Never throws. Whatever is wrong with the text comes back as
/// [KcppsBroken]: every caller treats the result as the whole answer, and a
/// start that died in here left the app unable to start KoboldCpp again
/// until it was restarted.
KcppsRead readKcpps(String text) {
  try {
    return _readKcpps(text);
  } on FormatException catch (e) {
    return KcppsBroken('This preset file is not valid: ${e.message}');
  } on Object catch (e) {
    return KcppsBroken('This preset file could not be understood ($e).');
  }
}

KcppsRead _readKcpps(String text) {
  final decoded = jsonDecode(text);
  if (decoded is! Map) {
    return const KcppsBroken('This preset file is not a KoboldCpp config.');
  }
  final map = decoded.cast<String, dynamic>();
  // A number too large to hold reads as infinity. It cannot be written back
  // out, and KoboldCpp could do nothing sensible with it either.
  try {
    jsonEncode(map);
  } on JsonUnsupportedObjectError {
    return const KcppsBroken(
      'This preset file has a number in it that is too large to use.',
    );
  }
  final notes = <String>[];

  var backend = KoboldGpuBackend.none;
  int? gpuId;
  final cuda = map['usecuda'] ?? map['usecublas'] ?? map['usehipblas'];
  var cudaOptions = const <String>[];
  if (cuda is List) {
    backend = KoboldGpuBackend.cuda;
    gpuId = cuda.map(_asInt).whereType<int>().firstOrNull;
    cudaOptions = [
      for (final o in cuda)
        if (o is String && _asInt(o) == null && !_cudaWords.contains(o)) o,
    ];
  } else if (map['usevulkan'] is List) {
    backend = KoboldGpuBackend.vulkan;
    gpuId = (map['usevulkan'] as List).map(_asInt).whereType<int>().firstOrNull;
  }

  final noSwa = map.containsKey('noswa')
      ? map['noswa'] == true
      : map.containsKey('useswa')
      ? map['useswa'] != true
      : null;
  final noFastForward = map['nofastforward'] == true;
  final ContextManagementMode mode;
  if (noSwa == false && noFastForward) {
    mode = ContextManagementMode.slidingWindowAttention;
  } else {
    mode = ContextManagementMode.fastForwardSmartCache;
    if (noSwa == false) {
      notes.add(kSwaWithFastForwardNote);
    } else if (noSwa == null) {
      notes.add(
        'This preset does not say how to handle sliding window. On a model '
        'that has it, current KoboldCpp switches it on together with fast '
        'forward, a pairing that degrades output. Add "noswa": true to the '
        'preset to switch it off.',
      );
    }
  }

  final flashOff = map.containsKey('noflashattention')
      ? map['noflashattention'] == true
      : map.containsKey('flashattention')
      ? map['flashattention'] != true
      : false;
  final moe = _asInt(map['moecpu']) ?? 0;
  final layers = _asInt(map['gpulayers']);
  final forcedFit = kcppsForcedFitNote(map);
  final bool? mmq = map['nommq'] is bool
      ? !(map['nommq'] as bool)
      : cuda is List && cuda.contains('nommq')
      ? false
      : cuda is List && cuda.contains('mmq')
      ? true
      : null;
  if (forcedFit != null) notes.add(forcedFit);

  return KcppsOk(
    KoboldLaunchConfig(
      modelPath: kcppsModelOf(map),
      contextSize: _asInt(map['contextsize']) ?? 16384,
      batchSize: _asInt(map['batchsize'] ?? map['blasbatchsize']) ?? 512,
      threads: _asInt(map['threads']),
      gpuLayers: layers ?? KoboldLaunchConfig.autoLayers,
      autofitPaddingMb: _asInt(map['autofitpadding']),
      useMmap: map['usemmap'] == true,
      useMlock: map['usemlock'] == true,
      kvQuant: KvQuant.parse(map['quantkv']),
      flashAttention: !flashOff,
      backend: backend,
      gpuId: gpuId,
      contextMode: mode,
      smartCacheSlots: _asInt(map['smartcache']) ?? 0,
      jinja: map['jinja'] == true,
      mmprojPath: map['mmproj']?.toString() ?? '',
      mmprojOnCpu: map['mmprojcpu'] == true,
      moeExpertsOnCpu: moe > 0,
      moeCpuLayers: moe > 0 ? moe : null,
      forceFit: map['autofit'] is bool ? map['autofit'] as bool : null,
      mmq: mmq,
      draftModelPath: map['draftmodel'] is String
          ? map['draftmodel'] as String
          : '',
      contextShift: map['noshift'] != true,
      cudaOptions: cudaOptions,
      extras: {
        for (final e in map.entries)
          if (!_managedKeys.contains(e.key)) e.key: e.value,
      },
    ),
    notes: notes,
    raw: map,
  );
}

/// Said when a preset has sliding window on together with fast forward.
const String kSwaWithFastForwardNote =
    'Sliding window was left on together with fast forward. That '
    'pairing degrades output, so sliding window is switched off here.';

/// Said when a preset forces automatic fit over a layer count or a MoE
/// setting of its own; null when it does not.
String? kcppsForcedFitNote(Map<String, dynamic> map) {
  final moe = _asInt(map['moecpu']) ?? 0;
  final layers = _asInt(map['gpulayers']);
  final overridden =
      moe > 0 || (layers != null && layers != KoboldLaunchConfig.autoLayers);
  return map['autofit'] == true && overridden
      ? 'This preset forces automatic fit, so KoboldCpp ignores its layer '
            'count and its MoE setting.'
      : null;
}

/// The model a config names, found the way KoboldCpp finds it: `model_param`
/// when it is a non-empty string, else `model` when it is one, else the
/// first entry of `model` when it is a list. Empty when it names none.
///
/// A relative path is relative to the folder KoboldCpp runs in. Given that
/// folder as [engineDir], the model comes back as a full path; without it,
/// as the file has it.
///
/// The one place this is worked out. Settings shows what it returns and a
/// launch loads what it returns, so the two cannot disagree.
String kcppsModelOf(Map<String, dynamic> map, {String? engineDir}) {
  String text(Object? v) => v is String ? v.trim() : '';
  var named = text(map['model_param']);
  if (named.isEmpty) {
    final model = map['model'];
    named = model is List
        ? (model.isEmpty ? '' : text(model.first))
        : text(model);
  }
  return kcppsPathIn(named, engineDir);
}

/// [path] from a config as a full path: a relative one is relative to
/// [engineDir], the folder KoboldCpp runs in. Unchanged when it is already
/// full, empty, or no folder is given.
String kcppsPathIn(String path, String? engineDir) =>
    path.isEmpty || p.isAbsolute(path) || engineDir == null || engineDir.isEmpty
    ? path
    : p.normalize(p.join(engineDir, path));

/// True when a config has sliding window on: `noswa: false`, or, in a file
/// from before that name existed, `useswa: true`.
bool kcppsHasSwaOn(Map<String, dynamic> map) =>
    map.containsKey('noswa') ? map['noswa'] == false : map['useswa'] == true;

/// True when a config says nothing either way about sliding window, so
/// KoboldCpp's own default decides.
bool kcppsLeavesSwaToKobold(Map<String, dynamic> map) =>
    !map.containsKey('noswa') && !map.containsKey('useswa');

/// Said when a preset leaves sliding window to KoboldCpp, with fast forward
/// on, for a model that has it. Nothing is changed; the user is told.
const String kSwaLeftToKoboldNote =
    'This preset does not say how to handle sliding window, and this model '
    'has it. KoboldCpp switches it on together with fast forward, a pairing '
    'that degrades output. Add "noswa": true to the preset to switch it off.';

/// The `.kcpps` map for [config], in the forms [caps] says the installed
/// KoboldCpp accepts.
///
/// A key KoboldCpp renamed is written under BOTH names (`usecuda` and
/// `usecublas`, `batchsize` and `blasbatchsize`). An old engine knows only
/// the old name. A current one converts the old name at launch but not on
/// a live reload, which fills in every missing default first and then
/// finds nothing to convert: measured, a file with only `blasbatchsize`
/// ran at its value after a launch and at the default after a reload.
Map<String, dynamic> kcppsMap(
  KoboldLaunchConfig config, {
  KoboldCapabilities caps = KoboldCapabilities.current,
}) {
  final map = <String, dynamic>{
    ...config.extras,
    if (config.modelPath.isNotEmpty) 'model_param': config.modelPath,
    'contextsize': config.contextSize,
    'batchsize': config.batchSize,
    'blasbatchsize': config.batchSize,
    'gpulayers': config.gpuLayers,
    'autofitpadding': ?config.autofitPaddingMb,
    'usemmap': config.useMmap,
    'usemlock': config.useMlock,
    'quantkv': caps.quantKvAsText
        ? config.kvQuant.wire
        : (config.kvQuant.legacyIndex ?? KvQuant.q4_0.legacyIndex),
    'threads': ?config.threads,
    'noflashattention': !config.flashAttention,
    'jinja': config.jinja,
    if (config.mmprojPath.isNotEmpty) 'mmproj': config.mmprojPath,
    if (config.mmprojOnCpu) 'mmprojcpu': true,
    'autofit': ?config.forceFit,
    if (config.mmq != null) 'nommq': !config.mmq!,
    if (config.draftModelPath.isNotEmpty) 'draftmodel': config.draftModelPath,
  };

  // Automatic fitting and `moecpu` cannot be combined; a manual layer
  // count is the only case where the app places MoE experts itself.
  if (config.moeExpertsOnCpu && !config.layersAreAutomatic && caps.moeCpu) {
    map['moecpu'] = config.moeCpuLayers ?? 999;
  }

  switch (config.backend) {
    case KoboldGpuBackend.cuda:
      // The id is TEXT: KoboldCpp tests `"0" in usecuda`, so a number is
      // ignored and every card is used.
      final cuda = [
        'normal',
        if (config.gpuId != null) '${config.gpuId}',
        ...config.cudaOptions,
      ];
      map['usecuda'] = cuda;
      map['usecublas'] = cuda;
    case KoboldGpuBackend.vulkan:
      map['usevulkan'] = [?config.gpuId];
    case KoboldGpuBackend.none:
      break;
  }

  switch (config.contextMode) {
    case ContextManagementMode.slidingWindowAttention:
      // Fast forward stays OFF with sliding window. The two together
      // degrade the model's output; do not "optimise" this.
      map['noswa'] = false;
      map['swapadding'] = 0;
      map['nofastforward'] = true;
      map['noshift'] = true;
    case ContextManagementMode.fastForwardSmartCache:
      map['noswa'] = true;
      map['nofastforward'] = false;
      map['noshift'] = !config.contextShift;
      if (config.smartCacheSlots > 0 && caps.smartCache) {
        map['smartcache'] = config.smartCacheSlots.clamp(1, 20);
      }
  }
  return map;
}

String writeKcpps(
  KoboldLaunchConfig config, {
  KoboldCapabilities caps = KoboldCapabilities.current,
}) => encodeKcpps(kcppsMap(config, caps: caps));

/// [map] as the text of a `.kcpps` file.
String encodeKcpps(Map<String, dynamic> map) =>
    const JsonEncoder.withIndent('  ').convert(map);

int? _asInt(Object? v) => switch (v) {
  int n => n,
  num n => n.isFinite ? n.toInt() : null,
  String s => int.tryParse(s.trim()),
  _ => null,
};
