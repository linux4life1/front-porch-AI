// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The engine's version record is trusted only for the binary it was written
// for (its size says which). A record left from an older engine, kept when
// an update could not look its version up, used to refuse a current
// KoboldCpp as "too old" and break Start.
//
// No engine is started: the refusal comes before anything is spawned, and a
// start that goes ahead is refused at the spawn, in other words, on an engine
// file that is not a program. The download is real, from a server on
// loopback.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/kobold_admin_swap.dart';
import 'package:front_porch_ai/services/kobold_binary_version.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:path/path.dart' as p;

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

/// The service without its start-up probe of port 5001, which would act on
/// a KoboldCpp the developer has running.
class _Kobold extends KoboldService {
  _Kobold(super.storage);

  @override
  Future<void> reconnectIfAlive() async {}
}

/// The engine download, from [url], with the version lookup failing.
class _Manager extends BackendManager {
  _Manager(super.storage, this.url);
  final String url;

  @override
  String get engineDownloadUrl => url;

  @override
  Future<void> checkForUpdates() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late KoboldService kobold;
  late Directory dir;
  late String engine;
  late String model;

  setUp(() async {
    HttpOverrides.global = null;
    storage = await createStorageService();
    kobold = _Kobold(storage);
    dir = Directory.systemTemp.createTempSync('fpai_stale_engine_');
    engine = p.join(dir.path, 'koboldcpp');
    File(engine).writeAsBytesSync(List.filled(2048, 0));
    model = p.join(dir.path, 'model.gguf');
    File(model).writeAsBytesSync([...'GGUF'.codeUnits, 3, 0, 0, 0]);
  });

  tearDown(() {
    kobold.dispose();
    final admin = koboldAdminDirFor(storage);
    if (FileSystemEntity.isFileSync(admin)) File(admin).deleteSync();
    dir.deleteSync(recursive: true);
  });

  test('a 1.110 record written for another binary does not refuse this '
      'one', () async {
    await KoboldBinaryVersion.write(
      dir.path,
      version: '1.110',
      size: 419430400,
    );

    final result = await kobold.launch(engine, pickedModel: model, port: 5998);

    // Refused at the spawn (the file is not a program), not as too old.
    expect(result.started, isFalse);
    expect(result.message, contains('could not be started'));
    expect(kobold.logs.join('\n'), isNot(contains('too old')));
  });

  test('a 1.110 record written for this binary still refuses it', () async {
    await KoboldBinaryVersion.write(dir.path, version: '1.110', size: 2048);

    final result = await kobold.launch(engine, pickedModel: model, port: 5998);

    expect(result.started, isFalse);
    expect(result.message, contains('too old'));
  });

  test(
    'a download whose version lookup failed leaves no version record',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final body = List.filled(2 * 1024 * 1024, 7);
      server.listen((r) async {
        r.response
          ..contentLength = body.length
          ..add(body);
        await r.response.close();
      });
      final bin = storage.binDir;
      await bin.create(recursive: true);
      await KoboldBinaryVersion.write(bin.path, version: '1.110', size: 1);
      final manager = _Manager(
        storage,
        'http://127.0.0.1:${server.port}/koboldcpp',
      );
      addTearDown(manager.dispose);
      // The Mac's processor is read in the background after start; until
      // then it counts as an Intel Mac, where no engine is downloaded.
      for (var i = 0; i < 100 && manager.isIntelMac; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (manager.isIntelMac) {
        markTestSkipped('KoboldCpp is not downloaded on Intel Macs');
        return;
      }

      await manager.downloadBackend();

      expect(manager.error, isNull);
      final engines = bin.listSync().whereType<File>().where(
        (f) => f.lengthSync() == body.length,
      );
      expect(engines, hasLength(1), reason: 'the new engine is in place');
      expect(
        File(p.join(bin.path, KoboldBinaryVersion.fileName)).existsSync(),
        isFalse,
      );
    },
  );
}
