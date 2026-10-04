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
};

/// What reading a `.kcpps` gave.
sealed class KcppsRead {
  const KcppsRead();
}

class KcppsOk extends KcppsRead {
  const KcppsOk(this.config, {this.notes = const []});
  final KoboldLaunchConfig config;

  /// Plain-words remarks about what was changed on the way in.
  final List<String> notes;

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
KcppsRead readKcpps(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (e) {
    return KcppsBroken('This preset file is not valid: ${e.message}');
  }
  if (decoded is! Map) {
    return const KcppsBroken('This preset file is not a KoboldCpp config.');
  }
  final map = decoded.cast<String, dynamic>();
  final notes = <String>[];

  var backend = KoboldGpuBackend.none;
  int? gpuId;
  final cuda = map['usecuda'] ?? map['usecublas'] ?? map['usehipblas'];
  if (cuda is List) {
    backend = KoboldGpuBackend.cuda;
    gpuId = cuda.map(_asInt).whereType<int>().firstOrNull;
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
    if (noSwa != true) {
      notes.add(
        'Sliding window was left on together with fast forward. That '
        'pairing degrades output, so sliding window is switched off here.',
      );
    }
  }

  final model = map['model_param'] ?? map['model'];
  final flashOff = map.containsKey('noflashattention')
      ? map['noflashattention'] == true
      : map.containsKey('flashattention')
      ? map['flashattention'] != true
      : false;
  final moe = _asInt(map['moecpu']) ?? 0;

  return KcppsOk(
    KoboldLaunchConfig(
      modelPath: model is List
          ? (model.isEmpty ? '' : model.first.toString())
          : model?.toString() ?? '',
      contextSize: _asInt(map['contextsize']) ?? 16384,
      batchSize: _asInt(map['batchsize'] ?? map['blasbatchsize']) ?? 512,
      threads: _asInt(map['threads']),
      gpuLayers: _asInt(map['gpulayers']) ?? KoboldLaunchConfig.autoLayers,
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
      extras: {
        for (final e in map.entries)
          if (!_managedKeys.contains(e.key)) e.key: e.value,
      },
    ),
    notes: notes,
  );
}

/// The `.kcpps` map for [config], in the forms [caps] says the installed
/// KoboldCpp accepts.
Map<String, dynamic> kcppsMap(
  KoboldLaunchConfig config, {
  KoboldCapabilities caps = KoboldCapabilities.current,
}) {
  final map = <String, dynamic>{
    ...config.extras,
    if (config.modelPath.isNotEmpty) 'model_param': config.modelPath,
    'contextsize': config.contextSize,
    'batchsize': config.batchSize,
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
  };

  // Automatic fitting and `moecpu` cannot be combined; a manual layer
  // count is the only case where the app places MoE experts itself.
  if (config.moeExpertsOnCpu && !config.layersAreAutomatic && caps.moeCpu) {
    map['moecpu'] = 999;
  }

  switch (config.backend) {
    case KoboldGpuBackend.cuda:
      // The id is TEXT: KoboldCpp tests `"0" in usecuda`, so a number is
      // ignored and every card is used. The old key name is written on
      // purpose: old builds know only it, new builds convert it.
      map['usecublas'] = [
        'normal',
        if (config.gpuId != null) '${config.gpuId}',
      ];
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
      map['noshift'] = false;
      if (config.smartCacheSlots > 0 && caps.smartCache) {
        map['smartcache'] = config.smartCacheSlots.clamp(1, 20);
      }
  }
  return map;
}

String writeKcpps(
  KoboldLaunchConfig config, {
  KoboldCapabilities caps = KoboldCapabilities.current,
}) => const JsonEncoder.withIndent('  ').convert(kcppsMap(config, caps: caps));

int? _asInt(Object? v) => switch (v) {
  int n => n,
  num n => n.toInt(),
  String s => int.tryParse(s.trim()),
  _ => null,
};
