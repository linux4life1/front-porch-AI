// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:isolate';

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

/// The catalog's versions by file base name, built once. The first
/// non-empty version wins, the same as scanning the catalog in order.
Map<String, String> _versionsByBase(Map<String, String> versions) {
  final byBase = <String, String>{};
  for (final entry in versions.entries) {
    final value = entry.value.trim();
    if (value.isEmpty) continue;
    byBase.putIfAbsent(drawThingsLoraBasename(entry.key), () => value);
  }
  return byBase;
}

/// Same answer as [_catalogVersion], for many lookups against one catalog:
/// each is a map read instead of a scan of the whole catalog.
String _indexedVersion(
  String file,
  Map<String, String> versions,
  Map<String, String> byBase,
) {
  final base = drawThingsLoraBasename(file);
  final direct = versions[file] ?? versions[base];
  if (direct != null && direct.trim().isNotEmpty) return direct.trim();
  return byBase[base] ?? '';
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

/// A generic Draw Things version and the sizes it stands for. `flux2` names
/// no size, so it fits both Klein sizes; the sizes do not fit each other.
/// Every version not listed here has to match exactly: Qwen-Image 1.0 and 2.1,
/// for one, are different generations.
const Map<String, Set<String>> kDrawThingsVersionFamilies = {
  'flux2': {'flux2_4b', 'flux2_9b'},
};

/// True when a LoRA tagged [tag] can be used with a checkpoint of [wanted].
/// An empty tag is an unknown version, which is never a reason to hide.
bool drawThingsVersionFits({required String tag, required String wanted}) {
  if (tag.isEmpty || tag == wanted) return true;
  if (kDrawThingsVersionFamilies[tag]?.contains(wanted) ?? false) return true;
  return kDrawThingsVersionFamilies[wanted]?.contains(tag) ?? false;
}

/// LoRAs Draw Things would show for [modelVersion].
///
/// An empty model version keeps the full list. Otherwise a LoRA is hidden only
/// when the catalog tags it with a different, known version (see
/// [drawThingsVersionFits]). Untagged and zoo LoRAs stay visible, and a file
/// name never hides anything: only the catalog's tag counts.
List<String> drawThingsVisibleLoras({
  required List<String> files,
  required Map<String, String> loraVersions,
  required String modelVersion,
}) {
  final wanted = modelVersion.trim();
  if (wanted.isEmpty) return List<String>.from(files);
  final byBase = _versionsByBase(loraVersions);
  return [
    for (final file in files)
      if (drawThingsVersionFits(
        tag: _indexedVersion(file, loraVersions, byBase),
        wanted: wanted,
      ))
        file,
  ];
}

/// Lists longer than this are filtered on a background isolate. A folder of
/// thousands of LoRAs is enough work to stall a frame.
const int kDrawThingsFilterInlineMax = 2000;

/// Runs [work] somewhere other than the calling isolate.
typedef DrawThingsFilterRunner = Future<R> Function<R>(R Function() work);

Future<R> _onAnotherIsolate<R>(R Function() work) => Isolate.run(work);

Future<R> _offThread<R>(
  int size,
  int inlineMax,
  DrawThingsFilterRunner run,
  R Function() work,
) {
  if (size <= inlineMax) return Future<R>.value(work());
  return run<R>(work);
}

/// [drawThingsVisibleLoras] that keeps a big catalog off the UI isolate.
/// [run] and [inlineMax] are for tests.
Future<List<String>> drawThingsVisibleLorasOffThread({
  required List<String> files,
  required Map<String, String> loraVersions,
  required String modelVersion,
  int inlineMax = kDrawThingsFilterInlineMax,
  DrawThingsFilterRunner run = _onAnotherIsolate,
}) {
  return _offThread(
    files.length + loraVersions.length,
    inlineMax,
    run,
    () => drawThingsVisibleLoras(
      files: files,
      loraVersions: loraVersions,
      modelVersion: modelVersion,
    ),
  );
}

/// [deskLoraFiles] that keeps a big catalog off the UI isolate.
Future<List<String>> deskLoraFilesOffThread({
  required String backend,
  required List<String> files,
  required Map<String, String> loraVersions,
  required Map<String, String> modelVersions,
  required String modelFile,
  int inlineMax = kDrawThingsFilterInlineMax,
  DrawThingsFilterRunner run = _onAnotherIsolate,
}) {
  if (backend != 'drawthings') return Future.value(files);
  return drawThingsVisibleLorasOffThread(
    files: files,
    loraVersions: loraVersions,
    modelVersion: drawThingsVersionForModel(modelFile, modelVersions),
    inlineMax: inlineMax,
    run: run,
  );
}

/// [drawThingsLorasForModel] that keeps a big list off the UI isolate.
Future<List<LoraOption>> drawThingsLorasForModelOffThread(
  List<LoraOption> loras, {
  required String modelVersion,
  int inlineMax = kDrawThingsFilterInlineMax,
  DrawThingsFilterRunner run = _onAnotherIsolate,
}) {
  return _offThread(
    loras.length,
    inlineMax,
    run,
    () => drawThingsLorasForModel(loras, modelVersion: modelVersion),
  );
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
