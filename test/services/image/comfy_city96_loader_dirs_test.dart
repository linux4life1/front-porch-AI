// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/comfy_gguf_city96_target.dart';
import 'package:front_porch_ai/services/image/comfy_model_paths.dart';
import 'package:path/path.dart' as p;

Future<bool> Function(String) _files(Set<String> files) =>
    (path) async => files.contains(p.windows.normalize(path).toLowerCase());

ComfyProcessSnapshot _process(String executable, {String? command}) =>
    ComfyProcessSnapshot(
      command: command ?? r'python ComfyUI\main.py --port 8188',
      executable: executable,
    );

void main() {
  test(
    'Windows Desktop standalone environment uses its sibling source',
    () async {
      expect(
        await city96LoaderDirs(
          _process(r'C:\Comfy\Standalone-Env\python.exe'),
          isWindows: true,
          exists: _files({r'c:\comfy\comfyui\main.py'}),
        ),
        [r'C:\Comfy\ComfyUI'],
      );
    },
  );

  test('Windows Desktop venv accepts forward slashes and case', () async {
    expect(
      (await city96LoaderDirs(
        _process(
          'C:/Comfy/.VENV/Scripts/python.exe',
          command: 'python ./ComfyUI/main.py --port 8188',
        ),
        isWindows: true,
        exists: _files({r'c:\comfy\comfyui\main.py'}),
      )).map((path) => path == null ? null : p.windows.normalize(path)),
      [r'C:\Comfy\ComfyUI'],
    );
  });

  test(
    'Desktop refuses two source candidates without legacy fallback',
    () async {
      expect(
        await city96LoaderDirs(
          _process(r'C:\Comfy\standalone-env\python.exe'),
          isWindows: true,
          exists: _files({
            r'c:\comfy\comfyui\main.py',
            r'c:\comfy\standalone-env\comfyui\main.py',
          }),
        ),
        [null],
      );
    },
  );

  test(
    'portable Python retains the legacy folders without a Desktop search',
    () async {
      expect(
        await city96LoaderDirs(
          _process(r'C:\Comfy\python_embeded\python.exe'),
          isWindows: true,
          exists: (_) async => throw StateError('portable must not search'),
        ),
        [r'C:\Comfy\ComfyUI', null],
      );
    },
  );

  test(
    'Desktop inference requires exactly one relative main argument',
    () async {
      expect(
        await city96LoaderDirs(
          _process(
            r'C:\Comfy\standalone-env\python.exe',
            command: r'python ComfyUI\main.py ComfyUI/main.py --port 8188',
          ),
          isWindows: true,
          exists: (_) async =>
              throw StateError('ambiguous launch must not search'),
        ),
        [r'C:\Comfy\standalone-env\ComfyUI', null],
      );
    },
  );

  test(
    'non-Windows keeps the old lookup even with Desktop-looking paths',
    () async {
      expect(
        await city96LoaderDirs(
          _process(r'C:\Comfy\standalone-env\python.exe'),
          isWindows: false,
          exists: (_) async => throw StateError('non-Windows must not search'),
        ),
        [r'C:\Comfy\standalone-env\ComfyUI', null],
      );
    },
  );
}
