// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';

void main() {
  test(
    'an installed stamp is not a download prompt until GitHub is newer',
    () async {
      final root = await Directory.systemTemp.createTemp('fpai_oc_probe_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final closet = OpenCodeCloset(root.path);
      await Directory(closet.binDir).create(recursive: true);
      await File(closet.binaryPath).writeAsString('BIN');
      await OpenCodeBinaryVersion.write(
        closet.binDir,
        version: '1.18.30',
        size: 3,
      );
      final mgr = OpenCodeManager(
        rootPath: root.path,
        remoteLookup: () async => null,
      );
      await mgr.refreshInstalled();
      expect(mgr.installedVersion, '1.18.30');
      expect(mgr.isUpdateAvailable, isFalse);
      await mgr.checkRemoteVersion();
      expect(mgr.isUpdateAvailable, isFalse);
    },
  );
}
