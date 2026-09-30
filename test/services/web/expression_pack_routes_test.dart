// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone starts, watches, cancels and imports an expression pack, called
// the way the web app calls it, over a real character library, a real account
// and a real loopback ComfyUI. The pack is the desktop's pack: the same
// decision (the Edit graph or a reason), the same lock, the same board.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/image/expression_pack_board.dart';
import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/image/comfy_gguf_city96_gate.dart'
    show kCity96NoAsk;
import 'package:front_porch_ai/services/image/image.dart'
    show kComfyUploadedWorkflowId;
import 'package:front_porch_ai/services/web/facade/image_facade.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';

import '../../helpers/crafted_pictures.dart';
import '../../helpers/huge_png.dart';
import 'desk_graphs.dart';
import 'image_desk_harness.dart';

final List<int> _portrait = img.encodePng(img.Image(width: 96, height: 120));

const String _pack = '/api/image/expression-pack';

/// Emotions the character already has, so a pack makes only the other two and
/// a test does not wait for eight pictures.
const List<String> _have = [
  'neutral',
  'anger',
  'fear',
  'surprise',
  'love',
  'embarrassment',
];
const List<String> _missing = ['joy', 'sadness'];

const List<String> _installed = [
  'edit-model.safetensors',
  'create-model.safetensors',
];

/// Comfy with both graphs uploaded and installed.
Future<void> _readyComfy(DeskHarness h) async {
  final s = h.settings;
  await s.setComfyCreateWorkflowId(kComfyUploadedWorkflowId);
  await s.setComfyCreateUploadedWorkflow(jsonEncode(deskCreateGraph));
  await s.setImageGenModel('create-model.safetensors');
  await s.setComfyEditWorkflowId(kComfyUploadedWorkflowId);
  await s.setComfyEditUploadedWorkflow(jsonEncode(deskEditGraph));
  await s.setImageGenEditModel('edit-model.safetensors');
}

Future<Map<String, dynamic>> _untilStopped(DeskHarness h) async {
  for (var i = 0; i < 300; i++) {
    final (_, view) = await h.call('GET', _pack);
    if (view['running'] == false) return view;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('the pack never stopped');
}

/// A scripted engine that notes whether each picture was asked for as a
/// phone caller (one that must never raise the desktop's loader dialog).
class _ZoneEngine extends ChangeNotifier implements ImageGenService {
  final List<bool> phone = [];

  @override
  String get statusMessage => '';

  @override
  Future<Uint8List?> generateImage({
    required String prompt,
    String? negativePrompt,
    String? size,
    Uint8List? referenceImage,
    String? model,
    bool isPortrait = false,
    int? seed,
    double? denoise,
    StudioIntent intent = StudioIntent.create,
    double? editStrength,
  }) async {
    phone.add(Zone.current[kCity96NoAsk] == true);
    return Uint8List.fromList(_portrait);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DeskHarness h;
  late String mara;

  setUp(() => expressionPackBoard.clear());
  tearDown(() => expressionPackBoard.clear());

  Future<DeskComfy> boot({bool finish = true, bool hang = false}) async {
    final comfy = await DeskComfy.start(
      checkpoints: _installed,
      finish: finish,
      hang: hang,
    );
    h = await DeskHarness.boot(comfy: comfy, withCharacters: true);
    await _readyComfy(h);
    mara = await h.addCharacter('Mara', portrait: _portrait);
    for (final emotion in _have) {
      await h.characters!.addAvatar(
        mara,
        'Mara',
        Uint8List.fromList(_portrait),
        emotion,
      );
    }
    return comfy;
  }

  group('a pack from the phone', () {
    test('nothing is running until one is started', () async {
      await boot();
      final (status, body) = await h.call('GET', _pack);
      expect(status, 404);
      expect(body['code'], 'no_pack');
    });

    test('starts at once, runs the Edit graph for each emotion, and waits '
        'to be imported', () async {
      final comfy = await boot();

      final (status, started) = await h.call('POST', _pack, {
        'characterId': mara,
      });
      expect(status, 200, reason: '$started');
      expect(started['running'], isTrue);
      expect(started['mode'], 'edit');
      expect(started['origin'], 'phone');
      expect(started['characterName'], 'Mara');
      expect(started['total'], _missing.length);

      final done = await _untilStopped(h);
      expect(done['done'], _missing.length);
      expect(done['canImport'], isTrue);
      expect(comfy.postedAll, hasLength(_missing.length));
      for (final graph in comfy.postedAll) {
        expect(
          ((graph['ckpt'] as Map)['inputs'] as Map)['ckpt_name'],
          'edit-model.safetensors',
        );
      }
      expect(comfy.uploads, _missing.length);
      expect(h.image.isGenerating, isFalse);
      expect([
        for (final slot in done['slots'] as List) (slot as Map)['emotion'],
      ], _missing);
    });

    test(
      'each finished picture can be fetched, and only a finished one',
      () async {
        await boot();
        await h.call('POST', _pack, {'characterId': mara});
        await _untilStopped(h);

        final ok = await h.callRaw('GET', '$_pack/picture?emotion=joy');
        expect(ok.statusCode, 200);
        expect(ok.headers['content-type'], 'image/png');
        expect(ok.headers['cache-control'], 'no-store');
        expect(await ok.read().expand((c) => c).toList(), isNotEmpty);

        final nope = await h.callRaw('GET', '$_pack/picture?emotion=nonsense');
        expect(nope.statusCode, 404);
        final none = await h.callRaw('GET', '$_pack/picture');
        expect(none.statusCode, 404);
      },
    );

    test('a picture that is not made yet cannot be fetched', () async {
      final comfy = await boot(finish: false, hang: true);
      await h.call('POST', _pack, {'characterId': mara});
      while (comfy.postedAll.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final making = await h.callRaw('GET', '$_pack/picture?emotion=joy');
      final waiting = await h.callRaw('GET', '$_pack/picture?emotion=sadness');

      expect(making.statusCode, 404);
      expect(waiting.statusCode, 404);
      await h.call('POST', '$_pack/cancel');
      await _untilStopped(h);
    });

    test('importing puts only the kept pictures into the character', () async {
      await boot();
      await h.call('POST', _pack, {'characterId': mara});
      await _untilStopped(h);

      final (status, body) = await h.call('POST', '$_pack/import', {
        'keep': ['joy'],
      });

      expect(status, 200, reason: '$body');
      expect(body['imported'], 1);
      expect(body['canImport'], isFalse);
      final labels = [
        for (final a in await h.characters!.getAvatarImages(mara)) a.label,
      ];
      expect(labels, contains('joy'));
      expect(labels, isNot(contains('sadness')), reason: 'it was left out');
      expect(
        labels.where((l) => l != null),
        hasLength(_have.length + 1),
        reason: 'the ones it already had stay',
      );

      final (again, refused) = await h.call('POST', '$_pack/import', {});
      expect(again, 409);
      expect(refused['code'], 'already_imported');
    });

    test('importing with nothing kept says so and imports nothing', () async {
      await boot();
      await h.call('POST', _pack, {'characterId': mara});
      await _untilStopped(h);

      final (status, body) = await h.call('POST', '$_pack/import', {
        'keep': <String>[],
      });

      expect(status, 409);
      expect(body['code'], 'nothing_to_import');
      final labels = [
        for (final a in await h.characters!.getAvatarImages(mara)) a.label,
      ];
      expect(labels, isNot(contains('joy')));
    });

    test('a pack still making pictures cannot be imported', () async {
      await boot(finish: false, hang: true);
      await h.call('POST', _pack, {'characterId': mara});
      final (status, body) = await h.call('POST', '$_pack/import', {});
      expect(status, 409);
      expect(body['code'], 'running');
      await h.call('POST', '$_pack/cancel');
      await _untilStopped(h);
    });

    test('a pack the desktop started is watched and cancelled here but '
        'imported there', () async {
      await boot();
      await h.call('POST', _pack, {'characterId': mara});
      await _untilStopped(h);
      // The same pack, as if the desktop dialog had started it.
      final run = expressionPackBoard.run!;
      expressionPackBoard.publish(
        PackRun(
          session: run.session,
          mode: run.mode,
          origin: PackOrigin.desktop,
          characterName: 'Mara',
          characterId: mara,
        ),
      );

      final (status, body) = await h.call('POST', '$_pack/import', {});
      expect(status, 409);
      expect(body['code'], 'desktop_pack');
    });

    test('cancelling stops the ComfyUI job, and what was stopped is left to '
        'do again, not failed', () async {
      final comfy = await boot(finish: false, hang: true);
      await h.call('POST', _pack, {'characterId': mara});
      while (comfy.postedAll.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final (status, _) = await h.call('POST', '$_pack/cancel');
      final stopped = await _untilStopped(h);

      expect(status, 200);
      expect(comfy.stops.join(), contains('interrupt'));
      expect(stopped['done'], 0);
      final first = (stopped['slots'] as List).first as Map;
      expect(first['state'], 'pending');
      expect(first['error'], isNull);
      expect(h.image.isGenerating, isFalse);
    });

    test('cancelling with no pack says so', () async {
      await boot();
      final (status, body) = await h.call('POST', '$_pack/cancel');
      expect(status, 404);
      expect(body['code'], 'no_pack');
    });
  });

  group('a pack that cannot start says why and makes nothing', () {
    test(
      'an Edit graph that is not ready, with the Create graph ready',
      () async {
        final comfy = await boot();
        await h.settings.setComfyEditWorkflowId('qwen_image_edit');

        final (status, body) = await h.call('POST', _pack, {
          'characterId': mara,
        });

        expect(status, 409);
        expect(body['code'], 'not_ready');
        expect(body['error'], contains('runs your Edit graph'));
        expect(body['error'], contains('never made with the Create graph'));
        expect(comfy.postedAll, isEmpty);
        expect(comfy.uploads, 0);
        final (gone, _) = await h.call('GET', _pack);
        expect(gone, 404);
      },
    );

    test('while another picture is being made', () async {
      final comfy = await boot(finish: false, hang: true);
      final busy = h.image.generateImage(prompt: 'a quiet porch');
      while (comfy.postedAll.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final (status, body) = await h.call('POST', _pack, {'characterId': mara});

      expect(status, 409);
      expect(body['code'], 'busy');
      await h.image.cancelJob();
      await busy;
    });

    test('a character that is not in the library', () async {
      await boot();
      final (status, body) = await h.call('POST', _pack, {
        'characterId': 'nobody',
      });
      expect(status, 404);
      expect(body['code'], 'no_character');
    });

    test('a character with no portrait and no picture sent', () async {
      await boot();
      final bare = await h.addCharacter('Bare');
      final (status, body) = await h.call('POST', _pack, {'characterId': bare});
      expect(status, 400);
      expect(body['code'], 'no_base');
    });

    test('a picture that is not a picture', () async {
      await boot();
      final (status, body) = await h.call('POST', _pack, {
        'characterId': mara,
        'referenceImage': 'data:image/png;base64,${base64Encode([1, 2, 3])}',
      });
      expect(status, 400);
      expect(body['code'], 'bad_picture');
    });

    test(
      'a picture that declares over 40 megapixels is refused, undecoded',
      () async {
        final comfy = await boot();
        final huge = hugePng(16000, 16000);

        final watch = Stopwatch()..start();
        final (status, body) = await h.call('POST', _pack, {
          'characterId': mara,
          'referenceImage': 'data:image/png;base64,${base64Encode(huge)}',
        });
        watch.stop();

        expect(status, 413);
        expect(body['code'], 'too_large');
        expect(body['error'], contains('16000x16000'));
        expect(watch.elapsedMilliseconds, lessThan(2000));
        expect(comfy.uploads, 0);
        final (gone, _) = await h.call('GET', _pack);
        expect(gone, 404);
      },
    );

    group('only a PNG picture is taken as the base', () {
      final jpeg = base64Encode(
        img.encodeJpg(img.Image(width: 96, height: 120)),
      );
      // A real 1x1 lossless WebP.
      const webp = 'UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==';

      for (final (name, mime, data) in [
        ('a real JPEG', 'image/jpeg', jpeg),
        ('a real WebP', 'image/webp', webp),
      ]) {
        test('$name is refused with 400 and asked to be a PNG', () async {
          final comfy = await boot();
          final (status, body) = await h.call('POST', _pack, {
            'characterId': mara,
            'referenceImage': 'data:$mime;base64,$data',
          });
          expect(status, 400, reason: '$body');
          expect(body['code'], 'bad_picture');
          expect(body['error'], contains('Please use a PNG'));
          expect(comfy.uploads, 0);
          expect(comfy.postedAll, isEmpty);
          final (gone, _) = await h.call('GET', _pack);
          expect(gone, 404);
        });
      }

      test('a normal PNG sent with the request still makes the pack', () async {
        final comfy = await boot();
        final (status, started) = await h.call('POST', _pack, {
          'characterId': mara,
          'referenceImage':
              'data:image/png;base64,${base64Encode(img.encodePng(img.Image(width: 300, height: 200)))}',
        });
        expect(status, 200, reason: '$started');

        final done = await _untilStopped(h);
        expect(done['done'], _missing.length);
        expect(done['canImport'], isTrue);
        expect(comfy.uploads, _missing.length);
      });
    });

    group(
      'a crafted picture is refused at once, and never as a server error',
      () {
        final crafted = <String, (Uint8List, int, String)>{
          'a PNG that inflates to hundreds of megabytes': (
            pngBomb(inflated: 256 * 1024 * 1024),
            400,
            'bad_picture',
          ),
          'an APNG with a huge frame': (
            apng(frameWidth: 16000, frameHeight: 16000),
            400,
            'bad_picture',
          ),
          'a 30-frame APNG': (
            apng(frames: 30, frameWidth: 6000, frameHeight: 6000),
            400,
            'bad_picture',
          ),
        };
        crafted.forEach((name, spec) {
          test(name, () async {
            final comfy = await boot();
            final watch = Stopwatch()..start();
            final (status, body) = await h.call('POST', _pack, {
              'characterId': mara,
              'referenceImage':
                  'data:image/png;base64,${base64Encode(spec.$1)}',
            });
            watch.stop();

            expect(status, spec.$2, reason: '$body');
            expect(body['code'], spec.$3);
            expect(watch.elapsedMilliseconds, lessThan(1500));
            expect(comfy.uploads, 0);
            expect(comfy.postedAll, isEmpty);
          });
        });

        test('a picture that passes the checks and then will not decode is '
            '"not a picture" (400)', () async {
          await boot();
          final rows = Uint8List(8 * (1 + 8 * 4))..[0] = 9;
          final broken = Uint8List.fromList([
            137, 80, 78, 71, 13, 10, 26, 10, //
            ...pngHeader(8, 8),
            ...pngChunk('IDAT', ZLibEncoder().convert(rows)),
            ...pngChunk('IEND', const []),
          ]);
          final (status, body) = await h.call('POST', _pack, {
            'characterId': mara,
            'referenceImage': 'data:image/png;base64,${base64Encode(broken)}',
          });
          expect(status, 400);
          expect(body['code'], 'bad_picture');
        });
      },
    );

    test('a character that already has every one of them', () async {
      await boot();
      for (final emotion in _missing) {
        await h.characters!.addAvatar(
          mara,
          'Mara',
          Uint8List.fromList(_portrait),
          emotion,
        );
      }
      final (status, body) = await h.call('POST', _pack, {'characterId': mara});
      expect(status, 409);
      expect(body['code'], 'nothing_to_do');

      // Asked for everything anyway, it goes ahead.
      final (again, started) = await h.call('POST', _pack, {
        'characterId': mara,
        'skipExisting': false,
      });
      expect(again, 200, reason: '$started');
      await h.call('POST', '$_pack/cancel');
      await _untilStopped(h);
    });

    test('a pack from the phone never raises the desktop dialog', () async {
      await boot();
      await h.settings.setImageGenBackend('a1111');
      final engine = _ZoneEngine();
      final facade = ImageFacade(engine, h.storage, h.characters);

      await facade.startPack({
        'characterId': mara,
        'prompt': 'a woman on a porch',
      });
      while (facade.packView()!['running'] == true) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(engine.phone, hasLength(_missing.length));
      expect(engine.phone, everyElement(isTrue));
    });

    test('img2img, which needs a description of the character', () async {
      await boot();
      await h.settings.setImageGenBackend('a1111');
      final (status, body) = await h.call('POST', _pack, {'characterId': mara});
      expect(status, 400);
      expect(body['code'], 'needs_prompt');
    });
  });
}
