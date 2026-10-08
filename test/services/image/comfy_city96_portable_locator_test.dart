// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/comfy_gguf_city96_target.dart';
import 'package:front_porch_ai/services/image/comfy_model_paths.dart';
import 'package:path/path.dart' as p;

import 'city96_test_probe.dart';

void main() {
  test('portable Python retains the serving loader lookup', () async {
    final root = await Directory.systemTemp.createTemp('fpai-comfy-portable-');
    addTearDown(() => root.delete(recursive: true));
    final main = File(p.join(root.path, 'ComfyUI', 'main.py'));
    final loader = File(
      p.join(root.path, 'ComfyUI', 'custom_nodes', 'ComfyUI-GGUF', 'loader.py'),
    );
    await main.create(recursive: true);
    await loader.create(recursive: true);
    await loader.writeAsString('portable loader');
    final exe = File(p.join(root.path, 'python_embeded', 'python.exe'));
    await exe.create(recursive: true);
    final result = await city96TargetForUrl(
      'http://127.0.0.1:8188',
      processes: [
        ComfyProcessSnapshot(
          command: r'python ComfyUI\main.py --port 8188',
          executable: exe.path,
          pid: 42,
          uid: 1000,
        ),
      ],
      probe: const FakeProbe(byPort: {8188: 42}),
    );
    expect(result.loader?.path, loader.path);
    expect(result.pid, 42);
    expect(await loader.readAsString(), 'portable loader');
  }, skip: !Platform.isWindows);
}
