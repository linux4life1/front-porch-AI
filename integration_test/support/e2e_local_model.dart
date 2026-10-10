// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';

/// A local model and a KoboldCpp preset for the "Local model" journey: the
/// real header of Llama 3.2 3B from the test fixtures, grown to the file's
/// real size (a sparse file, so nothing is written), chosen as the local
/// model, and a preset in the engine folder that names it. [repo] is the
/// checkout, where the fixtures are.
///
/// The card's verdicts weigh the context against the free memory read on
/// the machine running the suite, so [hardware] is given a reading with
/// room for the model at 65,536 tokens: a busy graphics card (another
/// program holding most of it) would otherwise call that size too big and
/// ask before keeping it, and a journey would pass on one machine and not
/// on another. Nothing here loads the model, so no reading is taken again.
Future<void> seedLocalModel(
  StorageService storage,
  Directory repo, {
  required HardwareService hardware,
}) async {
  hardware.freeBeforeEngine = (graphics: 12288, system: 32768);
  final fixture = p.join(
    repo.path,
    'test',
    'fixtures',
    'gguf_headers',
    'Llama-3.2-3B',
  );
  final side = jsonDecode(File('$fixture.json').readAsStringSync()) as Map;
  await storage.modelsDir.create(recursive: true);
  final model = p.join(
    storage.modelsDir.path,
    'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
  );
  final raf = await File(model).open(mode: FileMode.write);
  await raf.writeFrom(await File('$fixture.gguf').readAsBytes());
  await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
  await raf.writeByte(0);
  await raf.close();
  await storage.backendSettings.setLastUsedModelPath(model);
  await storage.backendSettings.setContextSize(16384);

  await storage.binDir.create(recursive: true);
  await File(p.join(storage.binDir.path, 'Long chats.kcpps')).writeAsString(
    jsonEncode({
      'model_param': model,
      'contextsize': 32768,
      'gpulayers': -1,
      'autofit': true,
      'noswa': true,
    }),
  );
}
