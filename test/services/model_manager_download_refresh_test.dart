// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// flutter_test stubs HttpClient to 400. An un-overridden HttpOverrides
/// restores the real client so this suite downloads a real fixture file.
class _RealHttpOverrides extends HttpOverrides {}

/// A finished in-app download must rescan the models folder so Settings →
/// Model Selection sees the new GGUF without leaving the page.
///
/// Serves a real on-disk fixture over loopback HTTP (not a stub client,
/// not canned 400/200). Red-proved: restoring `_onDownloadChanged` to
/// `notifyListeners()` only leaves [ModelManager.models] empty after the
/// file lands (the bug in #265).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final savedOverrides = HttpOverrides.current;
  setUp(() => HttpOverrides.global = _RealHttpOverrides());
  tearDown(() => HttpOverrides.global = savedOverrides);

  late Directory root;
  late File fixture;
  late List<int> fixtureBytes;
  late HttpServer server;
  late StorageService storage;
  late DownloadManager downloads;
  late ModelManager models;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai_model_refresh_');
    fixtureBytes = List<int>.generate(96, (i) => (i * 17) & 0xff);
    fixture = File(p.join(root.path, 'source-fresh-download.gguf'));
    await fixture.writeAsBytes(fixtureBytes, flush: true);

    storage = StorageService.sandbox(root.path);
    downloads = DownloadManager(targetDir: storage.modelsDir.path);
    models = ModelManager(storage, downloads);
    await models.refreshModels();
    expect(models.models, isEmpty);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final bytes = await fixture.readAsBytes();
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.binary
        ..contentLength = bytes.length
        ..add(bytes);
      await request.response.close();
    });
  });

  tearDown(() async {
    models.dispose();
    downloads.dispose();
    await server.close(force: true);
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('a successful download appears in the model selection list', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      const filename = 'fresh-download.gguf';
      final task = models.queueDownload(
        HFModelFile(
          filename: filename,
          sizeBytes: fixtureBytes.length,
          downloadUrl: 'http://127.0.0.1:${server.port}/$filename',
          repoId: 'test/repo',
        ),
      );

      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (DateTime.now().isBefore(deadline)) {
        if (task.state == DownloadTaskState.completed &&
            models.models.any((e) => p.basename(e.path) == filename)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(task.state, DownloadTaskState.completed);
      expect(
        models.models.map((e) => p.basename(e.path)),
        contains(filename),
        reason: 'Settings reads ModelManager.models after download completion',
      );
      expect(
        await File(p.join(storage.modelsDir.path, filename)).readAsBytes(),
        fixtureBytes,
        reason: 'the listed file must be the fixture that was downloaded',
      );
    }, _RealHttpOverrides());
  });
}
