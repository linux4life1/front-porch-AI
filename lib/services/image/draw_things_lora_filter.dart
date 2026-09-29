// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/grpc/dt_native/dt_local_loras.dart';

import 'model_family.dart';

final RegExp _klein4 = RegExp(
  r'klein[_-]?4(?!\d)|(^|[^a-z0-9])4b($|[^a-z0-9])',
);
final RegExp _zImage = RegExp(r'z[ _-]?image|zimage');
final RegExp _zit = RegExp(r'(^|[^a-z0-9])zit($|[^a-z0-9])');
final RegExp _sd3 = RegExp(r'(^|[^a-z0-9])sd[ _-]?3($|[^0-9])');
final RegExp _sd15 = RegExp(
  r'sd[ _-]?1[._-]?5|(^|[^a-z0-9])v1[._-]5($|[^0-9])',
);

/// Draw Things version id guessed from a file name. Empty when the name
/// does not say. A catalog `version` wins over this.
String drawThingsVersionFromName(String name) {
  final base = drawThingsLoraBasename(name).toLowerCase();
  if (base.isEmpty) return '';
  if (base.contains('ltx')) return 'ltx2.3';
  if (base.contains('klein')) {
    return _klein4.hasMatch(base) ? 'flux2_4b' : 'flux2_9b';
  }
  if (base.contains('flux2') ||
      base.contains('flux_2') ||
      base.contains('flux-2')) {
    return 'flux2';
  }
  if (base.contains('flux')) return 'flux1';
  if (base.contains('qwen')) {
    return base.contains('2.1') || base.contains('2_1')
        ? 'qwen_image_2.1'
        : 'qwen_image';
  }
  if (_zImage.hasMatch(base) || _zit.hasMatch(base)) return 'z_image';
  if (base.contains('krea')) return 'krea_2';
  if (base.contains('ernie')) return 'ernie_image';
  if (base.contains('ideogram')) return 'ideogram_4';
  if (base.contains('cosmos')) return 'cosmos2.5_2b';
  if (base.contains('minimax')) return 'minimax_h3';
  if (base.contains('pony') ||
      base.contains('illustrious') ||
      base.contains('sdxl') ||
      base.contains('noobai') ||
      base.contains('noob-ai') ||
      base.contains('noob_ai')) {
    return 'sdxl_base_v0.9';
  }
  if (_sd3.hasMatch(base)) return 'sd3';
  if (_sd15.hasMatch(base)) return 'v1';
  return '';
}

String _catalogVersion(String file, Map<String, String> versions) {
  final base = drawThingsLoraBasename(file);
  final direct = versions[file] ?? versions[base];
  if (direct != null && direct.trim().isNotEmpty) return direct.trim();
  for (final entry in versions.entries) {
    if (drawThingsLoraBasename(entry.key) != base) continue;
    final value = entry.value.trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

/// Version of the loaded checkpoint. `custom.json` wins. The file name
/// is the fallback. Empty when neither says.
String drawThingsVersionForModel(
  String modelFile,
  Map<String, String> modelVersions,
) {
  final tagged = _catalogVersion(modelFile, modelVersions);
  if (tagged.isNotEmpty) return tagged;
  return drawThingsVersionFromName(modelFile);
}

/// LoRAs Draw Things would show for [modelVersion].
///
/// An empty model version, or a catalog with no versions at all, keeps
/// the full list. Otherwise only an exact version match stays. An
/// unlabeled file is hidden once any LoRA in the catalog is tagged.
List<String> drawThingsVisibleLoras({
  required List<String> files,
  required Map<String, String> loraVersions,
  required String modelVersion,
}) {
  final wanted = modelVersion.trim();
  if (wanted.isEmpty) return List<String>.from(files);
  final tagged = loraVersions.values.any((value) => value.trim().isNotEmpty);
  if (!tagged) return List<String>.from(files);
  return [
    for (final file in files)
      if (_catalogVersion(file, loraVersions) == wanted) file,
  ];
}

/// Same list for Comfy and the other backends. Draw Things is filtered
/// to the loaded checkpoint's version.
List<String> deskLoraFiles({
  required String backend,
  required List<String> files,
  required Map<String, String> loraVersions,
  required Map<String, String> modelVersions,
  required String modelFile,
}) {
  if (backend != 'drawthings') return files;
  return drawThingsVisibleLoras(
    files: files,
    loraVersions: loraVersions,
    modelVersion: drawThingsVersionForModel(modelFile, modelVersions),
  );
}

/// [loras] limited to [modelVersion]. The caller keeps the full count.
List<LoraOption> drawThingsLorasForModel(
  List<LoraOption> loras, {
  required String modelVersion,
}) {
  final names = drawThingsVisibleLoras(
    files: [for (final row in loras) row.name],
    loraVersions: {for (final row in loras) row.name: row.dtVersion},
    modelVersion: modelVersion,
  );
  final keep = names.toSet();
  return [
    for (final row in loras)
      if (keep.contains(row.name)) row,
  ];
}
