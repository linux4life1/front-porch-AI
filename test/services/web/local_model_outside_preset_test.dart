// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The phone's preset picker and a preset chat uses that is not in the engine
// folder (picked with Browse on the desktop). The phone only takes presets
// from the folder, but it has to show the one in use: the host's answer
// carries the picker's line for it, as it does for each preset in the folder.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

class _Models extends FakeModelManager {
  @override
  Future<GGUFModelInfo?> getModelArchitectureInfo(String filePath) =>
      GGUFParser.getModelArchitectureInfo(filePath);
}

class _Llm extends FakeLLMProvider {
  @override
  KoboldService get koboldService => FakeKoboldService();
}

void main() {
  late Directory engineFolder;
  late Directory elsewhere;
  late _Storage storage;
  late BackendFacade facade;

  setUp(() async {
    engineFolder = await Directory.systemTemp.createTemp('fpai engine');
    elsewhere = await Directory.systemTemp.createTemp('fpai elsewhere');
    storage = _Storage(engineFolder);
    facade = BackendFacade(_Llm(), storage, _Models());
  });

  tearDown(() async {
    await engineFolder.delete(recursive: true);
    await elsewhere.delete(recursive: true);
  });

  String write(Directory dir, String name) {
    final file = p.join(dir.path, '$name.kcpps');
    File(file).writeAsStringSync(
      jsonEncode({
        'model_param': p.join(dir.path, 'm.gguf'),
        'contextsize': 32768,
        'gpulayers': -1,
        'autofit': true,
        'noswa': true,
      }),
    );
    return file;
  }

  test('a preset from elsewhere is in use but not in the list, and has its '
      'line', () async {
    final inFolder = write(engineFolder, 'Long chats');
    final outside = write(elsewhere, 'Mine');
    await storage.backendSettings.setActiveKcppsPath(outside);

    final card = await facade.localModel();
    final preset = card['preset'] as Map;
    expect(preset['path'], outside);
    expect(preset['name'], 'Mine');
    expect(preset['line'], '32k chat · fitted to the card · smart cache off');
    expect((card['presets'] as List).map((e) => (e as Map)['path']), [
      inFolder,
    ]);
  });
}
