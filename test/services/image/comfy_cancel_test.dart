// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stopping a generation stops the job on ComfyUI, not only the wait for it, and
// an expression pack holds the generation lock for all of its pictures. Talks
// to a real loopback ComfyUI.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/image_job.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// A loopback ComfyUI whose jobs run until they are stopped (or, with
/// [finish], finish at once). [running] is what its queue says is running.
class _Comfy {
  _Comfy({this.finish = false, this.submitDelay = Duration.zero});

  final bool finish;
  final Duration submitDelay;
  final List<String> calls = [];
  final Set<String> running = {'p1'};
  final Completer<void> posted = Completer<void>();
  late HttpServer server;
  int _jobs = 0;

  String get url => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final response = request.response;
    final body = await utf8.decodeStream(request);
    response.headers.contentType = ContentType.json;
    if (path == '/object_info') {
      response.write(
        jsonEncode({
          'CheckpointLoaderSimple': <String, dynamic>{},
          'KSampler': {
            'input': {
              'required': {
                'sampler_name': [
                  ['euler'],
                ],
              },
            },
          },
        }),
      );
    } else if (request.method == 'POST' && path == '/prompt') {
      if (!posted.isCompleted) posted.complete();
      await Future<void>.delayed(submitDelay);
      _jobs++;
      response.write(jsonEncode({'prompt_id': 'p$_jobs'}));
    } else if (path.startsWith('/history/')) {
      final id = path.substring('/history/'.length);
      response.write(
        jsonEncode({
          if (finish)
            id: {
              'outputs': {
                'save': {
                  'images': [
                    {'filename': 'a.png', 'subfolder': '', 'type': 'output'},
                  ],
                },
              },
            },
        }),
      );
    } else if (path == '/view') {
      response.headers.contentType = ContentType('image', 'png');
      response.add([1, 2, 3, 4]);
    } else if (path == '/queue' && request.method == 'GET') {
      response.write(
        jsonEncode({
          'queue_running': [
            for (final id in running) [0, id, <String, dynamic>{}],
          ],
          'queue_pending': <dynamic>[],
        }),
      );
    } else if (path == '/queue') {
      calls.add('queue $body');
      response.write('{}');
    } else if (path == '/interrupt') {
      calls.add('interrupt $body');
      response.write('{}');
    } else {
      response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  }

  Future<void> stop() => server.close(force: true);
}

Future<ImageGenService> _studio(_Comfy comfy, Directory dir) async {
  final storage = StorageService.sandbox(dir.path);
  final settings = storage.imageGenSettings;
  await settings.setImageGenBackend('comfyui');
  await settings.setComfyUiUrl(comfy.url);
  await settings.setComfyCreateWorkflowId('sd');
  await settings.setComfyCreateModelChoice(
    'sd',
    '%MODEL_CHECKPOINT%',
    'v1-5-pruned.safetensors',
  );
  return ImageGenService(storage);
}

void main() {
  late Directory dir;

  setUp(() {
    HttpOverrides.global = null;
    dir = Directory.systemTemp.createTempSync('comfy-cancel');
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  Future<_Comfy> comfy({
    bool finish = false,
    Duration submitDelay = Duration.zero,
  }) async {
    final c = _Comfy(finish: finish, submitDelay: submitDelay);
    await c.start();
    addTearDown(c.stop);
    return c;
  }

  group('cancelling a job', () {
    test('interrupts a running job and takes it off the queue', () async {
      final c = await comfy();
      final image = await _studio(c, dir);
      final pending = image.generateImage(prompt: 'a porch at dusk');
      await c.posted.future;
      await Future<void>.delayed(const Duration(milliseconds: 300));

      await image.cancelJob();
      final bytes = await pending.timeout(const Duration(seconds: 10));

      expect(bytes, isNull);
      expect(image.statusMessage, 'Cancelled.');
      expect(c.calls, contains(startsWith('interrupt')));
      expect(c.calls.join(), contains('"prompt_id":"p1"'));
      expect(c.calls, contains('queue {"delete":["p1"]}'));
      expect(image.isGenerating, isFalse);
    });

    test('a job that is only queued is removed, and nothing else is '
        'interrupted', () async {
      final c = await comfy();
      c.running.clear();
      final image = await _studio(c, dir);
      final pending = image.generateImage(prompt: 'a porch at dusk');
      await c.posted.future;
      await Future<void>.delayed(const Duration(milliseconds: 300));

      await image.cancelJob();
      await pending.timeout(const Duration(seconds: 10));

      expect(c.calls, contains('queue {"delete":["p1"]}'));
      expect(c.calls.where((c) => c.startsWith('interrupt')), isEmpty);
    });

    test('asked while the workflow is still being posted, it stops once the '
        'job has a name', () async {
      final c = await comfy(submitDelay: const Duration(milliseconds: 600));
      final image = await _studio(c, dir);
      final pending = image.generateImage(prompt: 'a porch at dusk');
      await c.posted.future;

      await image.cancelJob();
      final bytes = await pending.timeout(const Duration(seconds: 10));

      expect(bytes, isNull);
      expect(image.statusMessage, 'Cancelled.');
      expect(c.calls, contains(startsWith('interrupt')));
    });

    test('with nothing running it does nothing', () async {
      final c = await comfy();
      final image = await _studio(c, dir);
      await image.cancelJob();
      expect(c.calls, isEmpty);
    });
  });

  group('an expression pack flight', () {
    test('holds the lock from one picture to the next', () async {
      final c = await comfy(finish: true);
      final image = await _studio(c, dir);
      Uint8List? refused;
      Uint8List? first;
      Uint8List? second;
      final names = await image.startExpressionPack(['happy', 'sad'], (
        emotions,
      ) async {
        first = await image.expressionFrame(prompt: 'happy');
        // Between two pictures, someone else asks for one.
        refused = await image.generateImage(prompt: 'sneaking in');
        expect(image.statusMessage, kAlreadyGeneratingMessage);
        expect(image.isGenerating, isTrue);
        second = await image.expressionFrame(prompt: 'sad');
        return emotions;
      });

      expect(names, ['happy', 'sad']);
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(refused, isNull);
      expect(image.isGenerating, isFalse);
    });

    test('a second start is refused and its driver never runs', () async {
      final c = await comfy(finish: true);
      final image = await _studio(c, dir);
      final gate = Completer<void>();
      var secondRan = false;
      final first = image.startExpressionPack(['a'], (_) async {
        await gate.future;
        return ['a'];
      });
      final second = await image.startExpressionPack(['b'], (_) async {
        secondRan = true;
        return ['b'];
      });
      gate.complete();

      expect(second, isNull);
      expect(secondRan, isFalse);
      expect(await first, ['a']);
    });

    test('is refused while a picture is being made', () async {
      final c = await comfy();
      final image = await _studio(c, dir);
      final pending = image.generateImage(prompt: 'a porch at dusk');
      await c.posted.future;
      var ran = false;
      final names = await image.startExpressionPack(['a'], (_) async {
        ran = true;
        return ['a'];
      });
      expect(names, isNull);
      expect(ran, isFalse);
      await image.cancelJob();
      await pending.timeout(const Duration(seconds: 10));
    });

    test('lets go of the lock when its driver throws', () async {
      final c = await comfy();
      final image = await _studio(c, dir);
      await expectLater(
        image.startExpressionPack(['a'], (_) async => throw StateError('x')),
        throwsStateError,
      );
      expect(image.isGenerating, isFalse);
    });
  });
}
