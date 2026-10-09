// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The phone's Installed models list (GET /api/backend/models) scans the
// models folder each time it is asked, so a GGUF copied in while the app runs
// shows up there as it does on the desktop's Backend tab. The real
// ModelManager over a real folder; the model is a real GGUF header fixture.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';

import '../../golden/support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a model copied into the folder after startup is listed', () async {
    final root = await Directory.systemTemp.createTemp('fpai phone rescan');
    addTearDown(() => root.delete(recursive: true));
    final storage = StorageService.sandbox(root.path);
    final downloads = DownloadManager(targetDir: storage.modelsDir.path);
    final models = ModelManager(storage, downloads);
    addTearDown(() {
      models.dispose();
      downloads.dispose();
      storage.dispose();
    });
    await models.refreshModels();
    expect(models.models, isEmpty, reason: 'the folder starts empty');

    await File(
      'test/fixtures/gguf_headers/Llama-3.1-8B.gguf',
    ).copy(p.join(storage.modelsDir.path, 'copied-in.gguf'));

    final facade = BackendFacade(FakeLLMProvider(), storage, models);
    final listed = [for (final m in await facade.localModels()) m['name']];
    expect(listed, [
      'copied-in.gguf',
    ], reason: 'the phone list must scan the folder again when asked');
  });
}
