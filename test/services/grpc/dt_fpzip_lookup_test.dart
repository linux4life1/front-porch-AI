// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/grpc/dt_native/dt_fpzip.dart';

void main() {
  test('a flutter run executable still finds tools/fpzip', () async {
    final root = await Directory.systemTemp.createTemp('fpzip_walk_');
    try {
      final exe = Directory(
        p.join(
          root.path,
          'build',
          'macos',
          'Build',
          'Products',
          'Debug',
          'FrontPorchAI.app',
          'Contents',
          'MacOS',
        ),
      );
      await exe.create(recursive: true);
      final lib = File(p.join(root.path, 'tools', 'fpzip', 'libfpzip.dylib'));
      await lib.parent.create(recursive: true);
      await lib.writeAsBytes(const [0]);

      expect(fpzipDevCandidates(exe, 'libfpzip.dylib'), contains(lib.path));
    } finally {
      await root.delete(recursive: true);
    }
  });
}
