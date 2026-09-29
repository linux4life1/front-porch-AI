import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/civitai_fetch.dart';

void main() {
  test(
    'the downloader streams to a part file and keeps a failed file',
    () async {
      final saved = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = saved);
      final route = File(
        'lib/services/web/routes/civitai_routes.dart',
      ).readAsStringSync();
      final fetch = File(
        'lib/services/image/civitai_fetch.dart',
      ).readAsStringSync();
      expect(route.contains('fold<List<int>>'), isFalse);
      expect(fetch.contains('openWrite'), isTrue);
      expect(fetch.contains('.part'), isTrue);
      expect(fetch.contains('writeAsBytesSync'), isFalse);

      final dir = Directory.systemTemp.createTempSync('civitai-stream');
      addTearDown(() => dir.deleteSync(recursive: true));
      final payload = File('${dir.path}/payload.bin');
      final bytes = List<int>.generate(64, (i) => i);
      payload.writeAsBytesSync(bytes);
      final dest = File(
        '${dir.path}/models/diffusion_models/model.safetensors',
      );
      dest.parent.createSync(recursive: true);
      dest.writeAsBytesSync(const [9, 9, 9, 9]);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.uri.path == '/fail') {
          request.response.statusCode = 500;
          await request.response.close();
          return;
        }
        request.response.statusCode = 200;
        await request.response.addStream(payload.openRead());
        await request.response.close();
      });
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => raw.close());
      raw.listen((socket) {
        socket.add('HTTP/1.1 200 OK\r\nContent-Length: 100\r\n'.codeUnits);
        socket.add('Connection: close\r\n\r\n'.codeUnits);
        socket.add(const [1, 2, 3, 4]);
        socket.close();
      });
      final base = 'http://${server.address.host}:${server.port}';
      final short = 'http://${raw.address.host}:${raw.port}/short';

      await downloadCivitaiPlan(
        CivitaiDownloadPlan(
          uri: Uri.parse('$base/file'),
          path: dest.path,
          authorization: 'Bearer test-token',
          log: 'civitai download account=local adult=false',
          refused: false,
        ),
      );
      expect(dest.readAsBytesSync(), bytes);
      expect(File('${dest.path}.part').existsSync(), isFalse);

      dest.writeAsBytesSync(const [9, 9, 9, 9]);
      await expectLater(
        downloadCivitaiPlan(
          CivitaiDownloadPlan(
            uri: Uri.parse('$base/fail'),
            path: dest.path,
            authorization: 'Bearer test-token',
            log: 'civitai download account=local adult=false',
            refused: false,
          ),
        ),
        throwsStateError,
      );
      expect(dest.readAsBytesSync(), [9, 9, 9, 9]);
      expect(File('${dest.path}.part').existsSync(), isFalse);

      await expectLater(
        downloadCivitaiPlan(
          CivitaiDownloadPlan(
            uri: Uri.parse(short),
            path: dest.path,
            authorization: 'Bearer test-token',
            log: 'civitai download account=local adult=false',
            refused: false,
          ),
        ),
        throwsA(anything),
      );
      expect(dest.readAsBytesSync(), [9, 9, 9, 9]);
      expect(File('${dest.path}.part').existsSync(), isFalse);
    },
  );

  test(
    'a second download of the same file waits, and a stall cleans up',
    () async {
      final saved = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = saved);
      final dir = Directory.systemTemp.createTempSync('civitai-busy');
      addTearDown(() => dir.deleteSync(recursive: true));
      final dest = File('${dir.path}/model.safetensors');
      dest.writeAsBytesSync(const [7, 7]);
      final release = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        try {
          if (request.uri.path == '/stall') {
            request.response.statusCode = 200;
            request.response.contentLength = 8;
            request.response.add(const [1, 2]);
            await request.response.flush();
            await Future<void>.delayed(const Duration(seconds: 2));
            await request.response.close();
            return;
          }
          await release.future;
          request.response.statusCode = 200;
          request.response.add(const [3, 3, 3, 3]);
          await request.response.close();
        } catch (_) {}
      });
      final base = 'http://${server.address.host}:${server.port}';
      CivitaiDownloadPlan plan(String path) => CivitaiDownloadPlan(
        uri: Uri.parse('$base$path'),
        path: dest.path,
        authorization: 'Bearer test-token',
        log: 'civitai download account=local adult=false',
        refused: false,
      );
      final first = downloadCivitaiPlan(plan('/hold'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await expectLater(downloadCivitaiPlan(plan('/hold')), throwsStateError);
      release.complete();
      await first;
      expect(dest.readAsBytesSync(), [3, 3, 3, 3]);

      dest.writeAsBytesSync(const [7, 7]);
      await expectLater(
        downloadCivitaiPlan(
          plan('/stall'),
          idle: const Duration(milliseconds: 40),
        ),
        throwsA(anything),
      );
      expect(dest.readAsBytesSync(), [7, 7]);
      expect(File('${dest.path}.part').existsSync(), isFalse);
    },
  );
}
