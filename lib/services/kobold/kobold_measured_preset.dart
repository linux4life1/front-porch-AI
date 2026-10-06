// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The preset the speed test saves (the maintainer's ruling, 2026-10-06): a
// real, named preset, "<model> (measured on <card>)", that model's preset in
// the model-to-preset link, and the settings auto mode takes from it. Not
// the old hidden batch file: the user asked for it, and it shows wherever
// presets do.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/storage_service.dart';

import 'kcpps_codec.dart';
import 'kcpps_library.dart';
import 'kcpps_summary.dart';
import 'kobold_context_verdict.dart';
import 'kobold_launch_config.dart';
import 'kobold_speed_plan.dart';

/// The name the speed test saves [model]'s settings under on [card] (the
/// machine's name for it, '' without one): "Qwen3 14B (measured on GeForce
/// RTX 4080)". Characters a file name cannot have become dashes.
String koboldMeasuredPresetName(String model, String card) {
  final short = koboldCardShortName(card);
  final name =
      '${koboldModelName(model)} (measured on '
      '${short.isEmpty ? 'this computer' : short})';
  return name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '-');
}

/// The five settings the speed test tries, as [c] has them. MMQ left to
/// KoboldCpp is on, its default.
KoboldKnobs koboldKnobsOf(KoboldLaunchConfig c) => KoboldKnobs(
  batch: c.batchSize,
  mmq: c.mmq ?? true,
  mmap: c.useMmap,
  mlock: c.useMlock,
  flashAttention: c.flashAttention,
);

/// The settings the speed test measured for [model] on this machine ([card]
/// through [backend], see [KoboldMeasured.isHere]), from the preset it
/// saved: [model]'s linked preset, else the one under the test's own name.
/// Null when there is none, it was measured elsewhere, or it loads another
/// model. Auto mode runs these for [model] instead of its starting values;
/// a preset the editor timed is the user's and is not used this way.
Future<KoboldKnobs?> koboldMeasuredKnobs(
  StorageService storage, {
  required String model,
  required String card,
  required String backend,
}) async {
  if (model.isEmpty) return null;
  final library = KcppsLibrary(storage.binDir.path);
  final linked = storage.presetSettings.modelPresetMap[model] ?? '';
  for (final path in {
    if (linked.isNotEmpty) linked,
    library.pathFor(koboldMeasuredPresetName(model, card)),
  }) {
    final read = await _readIfThere(path);
    if (read == null) continue;
    final stamp = read.config.measured;
    if (stamp == null ||
        !stamp.auto ||
        !stamp.isHere(card: card, backend: backend)) {
      continue;
    }
    final named = kcppsModelOf(read.raw, engineDir: storage.binDir.path);
    if (!p.equals(p.normalize(named), p.normalize(model))) continue;
    return koboldKnobsOf(read.config);
  }
  return null;
}

/// Whether the preset at [path] is one the Local model card's speed test
/// saved: picking its model in auto mode keeps auto mode, which runs the
/// measured settings by itself.
Future<bool> koboldIsAutoMeasured(String path) async =>
    (await _readIfThere(path))?.config.measured?.auto ?? false;

/// The preset at [path], when there is one that can be read.
Future<KcppsOk?> _readIfThere(String path) async {
  if (path.isEmpty || !await File(path).exists()) return null;
  final read = (await KcppsLibrary.open(path)).read;
  return read is KcppsOk ? read : null;
}

/// The editor's line about a preset's batch: "Batch 1,024, measured on this
/// card." when a speed test measured it here, "Not measured on this card
/// yet." otherwise.
String koboldMeasuredWords(
  KoboldLaunchConfig c, {
  required String card,
  required String backend,
}) => (c.measured?.isHere(card: card, backend: backend) ?? false)
    ? 'Batch ${koboldTokens(c.batchSize)}, measured on this card.'
    : 'Not measured on this card yet.';
