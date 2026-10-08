// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/comfy_gguf_city96_target.dart';
import 'package:front_porch_ai/services/image/comfy_model_paths.dart';
import 'package:front_porch_ai/services/image/comfy_process_probe.dart';
import 'package:path/path.dart' as p;

class _ListeningProbe extends ComfyProcessProbe {
  const _ListeningProbe();

  @override
  Future<String?> currentPrincipal() async => 'same-user';

  @override
  Future<bool?> processIsMine(int pid) async => pid == 42;

  @override
  Future<Set<int>?> listeningPids(int port) async => {42};
}

void main() {
  test('finds a Comfy Desktop loader beside a relative main.py', () async {
    final root = await Directory.systemTemp.createTemp('fpai-comfy-desktop-');
    addTearDown(() => root.delete(recursive: true));
    final main = File(p.join(root.path, 'ComfyUI', 'main.py'));
    final loader = File(
      p.join(root.path, 'ComfyUI', 'custom_nodes', 'ComfyUI-GGUF', 'loader.py'),
    );
    await main.create(recursive: true);
    await loader.create(recursive: true);
    final exe = File(p.join(root.path, 'standalone-env', 'python.exe'));
    await exe.create(recursive: true);
    final process = ComfyProcessSnapshot(
      command: r'python ComfyUI\main.py --port 8188',
      executable: exe.path,
      pid: 42,
    );

    final found = await city96TargetForUrl(
      'http://127.0.0.1:8188',
      processes: [process],
      probe: const _ListeningProbe(),
    );

    expect(found.loader?.path, loader.path);
    expect(found.pid, 42);
  }, skip: !Platform.isWindows);

  test('refuses ambiguous Comfy Desktop source directories', () async {
    final root = await Directory.systemTemp.createTemp('fpai-comfy-ambiguous-');
    addTearDown(() => root.delete(recursive: true));
    for (final parent in [root.path, p.join(root.path, 'standalone-env')]) {
      await File(p.join(parent, 'ComfyUI', 'main.py')).create(recursive: true);
      await File(
        p.join(parent, 'ComfyUI', 'custom_nodes', 'ComfyUI-GGUF', 'loader.py'),
      ).create(recursive: true);
    }
    final exe = File(p.join(root.path, 'standalone-env', 'python.exe'));
    await exe.create(recursive: true);
    final found = await city96TargetForUrl(
      'http://127.0.0.1:8188',
      processes: [
        ComfyProcessSnapshot(
          command: r'python ComfyUI\main.py --port 8188',
          executable: exe.path,
          pid: 42,
        ),
      ],
      probe: const _ListeningProbe(),
    );

    expect(found.loader, isNull);
  }, skip: !Platform.isWindows);

  test(
    'does not infer an install from an unrelated Python executable',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'fpai-comfy-unrelated-',
      );
      addTearDown(() => root.delete(recursive: true));
      await File(
        p.join(root.path, 'ComfyUI', 'main.py'),
      ).create(recursive: true);
      await File(
        p.join(
          root.path,
          'ComfyUI',
          'custom_nodes',
          'ComfyUI-GGUF',
          'loader.py',
        ),
      ).create(recursive: true);
      final exe = File(p.join(root.path, 'unrelated', 'python.exe'));
      await exe.create(recursive: true);

      final found = await city96TargetForUrl(
        'http://127.0.0.1:8188',
        processes: [
          ComfyProcessSnapshot(
            command: r'python ComfyUI\main.py --port 8188',
            executable: exe.path,
            pid: 42,
          ),
        ],
        probe: const _ListeningProbe(),
      );

      expect(found.loader, isNull);
    },
    skip: !Platform.isWindows,
  );
}
