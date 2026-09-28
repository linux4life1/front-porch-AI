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
}
