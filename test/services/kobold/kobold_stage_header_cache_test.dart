// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A swap stages its role's config before every call: on a shared engine
// that is every Realism check and every spoken reply. For a model the app
// tunes itself, staging reads the model's header (up to 16 MB, parsed). The
// header only changes when the file does, so it is read once per file as it
// stands (its size and time), and again when the file changes.
//
// The model is a real header grown to its real size (a sparse file, so
// nothing is written).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/hardware_info.dart';
import 'package:front_porch_ai/services/kobold_launch_args.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late Directory dir;

  setUp(() async {
    storage = await createStorageService();
    dir = Directory.systemTemp.createTempSync('fpai header cache');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// A sparse file of [size] bytes holding [header] at its start.
  void write(File file, int size, List<int> header) {
    final raf = file.openSync(mode: FileMode.write);
    raf.writeFromSync(header);
    raf.setPositionSync(size - 1);
    raf.writeByteSync(0);
    raf.closeSync();
  }

  Future<Map<String, dynamic>> stage(String model) async {
    final staged = await stageKoboldRole(
      storage: storage,
      executablePath: p.join(dir.path, 'koboldcpp'),
      name: 'fpai-worker.kcpps',
      modelPath: model,
      kcppsPath: null,
      mmprojPath: null,
      gpuLayers: 0,
      contextSize: 16384,
      useVulkan: false,
      useCublas: true,
      useMetal: false,
      useRocm: false,
      hardware: HardwareInfo(
        gpuName: 'NVIDIA GeForce RTX 4080',
        vramMb: 16384,
        ramMb: 32768,
        vendor: 'Nvidia',
        hasCuda: true,
      ),
      free: (graphics: 16000, system: 28000),
    );
    return jsonDecode(staged.key) as Map<String, dynamic>;
  }

  test('the same file is not read again; a file that changed is', () async {
    const fx = 'test/fixtures/gguf_headers/Qwen3-14B';
    final size =
        (jsonDecode(File('$fx.json').readAsStringSync())
                as Map)['fixture_file_bytes']
            as int;
    final file = File(p.join(dir.path, 'Qwen3-14B.gguf'));
    write(file, size, File('$fx.gguf').readAsBytesSync());
    final long = DateTime.utc(2026, 1, 1);
    file.setLastModifiedSync(long);

    // What the header says: this machine has room for the largest batch.
    expect((await stage(file.path))['batchsize'], 2048);

    // The same size and time, with a header that cannot be read. Read
    // again, the model would be taken for an ordinary one and the tuning
    // would be gone.
    file.deleteSync();
    write(file, size, const []);
    file.setLastModifiedSync(long);
    expect((await stage(file.path))['batchsize'], 2048);

    // A file that changed is read afresh.
    file.setLastModifiedSync(DateTime.utc(2026, 1, 2));
    expect((await stage(file.path))['batchsize'], 512);
  });
}
