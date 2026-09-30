// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Nothing started from the phone or the web raises the desktop's ComfyUI-GGUF
// loader dialog: the job would wait on a window nobody there is looking at.
// Chat turns (send, regenerate, continue, swipe), and the character creator's
// portrait, run as a phone caller; a desktop turn does not.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/services/image/comfy_gguf_city96_gate.dart';
import 'package:front_porch_ai/services/web/facade/chargen_facade.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';

import '../../helpers/reprocess_needs_harness.dart';
import '../image/city96_test_loader.dart';
import '../image/city96_test_probe.dart';

/// The scripted model, noting whether each call ran as a phone caller.
class _ZoneSpyLlm extends RecordingLlm {
  final List<bool> phone = [];

  @override
  Stream<String> generateStream(GenerationParams params) {
    phone.add(Zone.current[kCity96NoAsk] == true);
    return super.generateStream(params);
  }
}

/// Waits in real time (not a count of event-loop turns, which a slower disk
/// outruns) until the model has been asked, then for the turn to end. Say what
/// the chat looked like if it never was.
Future<void> _turn(ReprocessHarness h, _ZoneSpyLlm spy) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (spy.phone.isEmpty && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await h.settleTurn();
  expect(
    spy.phone,
    isNotEmpty,
    reason:
        'the model was never asked (generating=${h.chat.isGenerating}, '
        'settling=${h.chat.isSettlingTurn}, messages=${h.chat.messages.length}, '
        'last=${h.chat.messages.isEmpty ? null : h.chat.messages.last.sender})',
  );
}

Future<HttpServer> _comfy() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == '/object_info') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          for (final c in [
            'UnetLoaderGGUF',
            'CLIPLoaderGGUF',
            'UNETLoader',
            'CLIPLoader',
            'VAELoader',
            'TextEncodeQwenImage21',
            'EmptySD3LatentImage',
            'KSampler',
            'VAEDecode',
            'SaveImage',
          ])
            c: <String, dynamic>{},
        }),
      );
    } else {
      await request.drain<void>();
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  return server;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  group('a chat turn', () {
    late ReprocessHarness h;
    late ChatFacade facade;
    late _ZoneSpyLlm spy;
    late int last;

    setUp(() async {
      h = ReprocessHarness();
      await h.boot();
      last = await h.oneToOneWithStampedReply(needsCard('Mara'));
      spy = _ZoneSpyLlm();
      h.chat.testLlmServiceOverride = spy;
      facade = ChatFacade(h.chat, h.repo, null, null, null);
    });
    tearDown(() => h.dispose());

    test('on the desktop is not a phone caller', () async {
      await h.chat.sendMessage('Still there?');
      await h.settleTurn();
      expect(spy.phone, isNotEmpty);
      expect(spy.phone, everyElement(isFalse));
    });

    test('sent from the phone is', () async {
      facade.send('Still there?');
      await _turn(h, spy);
      expect(spy.phone, isNotEmpty);
      expect(spy.phone, everyElement(isTrue));
    });

    test('regenerated from the phone is', () async {
      facade.regenerate();
      await _turn(h, spy);
      expect(spy.phone, isNotEmpty);
      expect(spy.phone, everyElement(isTrue));
    });

    test('continued from the phone is', () async {
      facade.continueGeneration();
      await _turn(h, spy);
      expect(spy.phone, isNotEmpty);
      expect(spy.phone, everyElement(isTrue));
    });

    test('swiped from the phone is', () async {
      facade.swipe(last, 1);
      await _turn(h, spy);
      expect(spy.phone, isNotEmpty);
      expect(spy.phone, everyElement(isTrue));
    });
  });

  test(
    'an image asked for from phone chat never asks, and writes nothing',
    () async {
      final h = ReprocessHarness();
      await h.boot();
      addTearDown(h.dispose);
      await h.oneToOneWithStampedReply(needsCard('Mara'));
      h.llm.mouth = 'a woman on a porch at dusk, warm light';
      final server = await _comfy();
      addTearDown(() => server.close(force: true));
      final dir = Directory.systemTemp.createTempSync('chat-image-city96');
      addTearDown(() => dir.deleteSync(recursive: true));
      final loader = File('${dir.path}/loader.py')
        ..writeAsStringSync(kStockCity96Loader);
      var asked = 0;
      final saved = City96Gate.instance;
      City96Gate.instance = City96Gate(
        locate: (_) async => loader,
        probe: const FakeProbe(),
        pidFor: (_) async => 100,
        // The desktop window: a question that nobody answers.
        ask: (_) {
          asked++;
          return Completer<bool>().future;
        },
      );
      addTearDown(() => City96Gate.instance = saved);
      final s = h.storage.imageGenSettings;
      await s.setImageGenEnabled(true);
      await s.setImageGenPromptReview(false);
      await s.setImageGenBackend('comfyui');
      await s.setComfyUiUrl('http://127.0.0.1:${server.port}');
      await s.setComfyCreateWorkflowId('qwen_image_21');
      for (final e in {
        '%MODEL_DIFFUSION%': 'qwen-image-2.1-Q2_K.gguf',
        '%MODEL_CLIP%': 'Qwen3-VL-8B-Instruct-Q4_K_M.gguf',
        '%MODEL_VAE%': 'qwen_image_2.1_vae_bf16.safetensors',
      }.entries) {
        await s.setComfyCreateModelChoice('qwen_image_21', e.key, e.value);
      }
      final image = ImageGenService(h.storage);
      h.chat.setImageGenService(image);
      final facade = ChatFacade(h.chat, h.repo, null, null, null);

      facade.send('/image a quiet porch');
      // The turn ends with the refusal, however busy the machine is.
      for (var i = 0; i < 1200; i++) {
        if (image.statusMessage.contains(kCity96ConfirmOnDesktop)) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await h.settleTurn();

      expect(image.statusMessage, contains(kCity96ConfirmOnDesktop));
      expect(asked, 0);
      expect(loader.readAsStringSync(), kStockCity96Loader);
      expect(File('${loader.path}.bak').existsSync(), isFalse);
    },
  );

  test('the character creator\'s portrait is answered at once', () async {
    HttpOverrides.global = null;
    final server = await _comfy();
    addTearDown(() => server.close(force: true));
    final dir = Directory.systemTemp.createTempSync('chargen-city96');
    addTearDown(() => dir.deleteSync(recursive: true));
    final loader = File('${dir.path}/loader.py')
      ..writeAsStringSync(kStockCity96Loader);
    var asked = 0;
    final saved = City96Gate.instance;
    City96Gate.instance = City96Gate(
      locate: (_) async => loader,
      probe: const FakeProbe(),
      pidFor: (_) async => 100,
      // The desktop window: a question that nobody answers.
      ask: (_) {
        asked++;
        return Completer<bool>().future;
      },
    );
    addTearDown(() => City96Gate.instance = saved);
    final storage = StorageService.sandbox(dir.path);
    final s = storage.imageGenSettings;
    await s.setImageGenBackend('comfyui');
    await s.setComfyUiUrl('http://127.0.0.1:${server.port}');
    await s.setComfyCreateWorkflowId('qwen_image_21');
    for (final e in {
      '%MODEL_DIFFUSION%': 'qwen-image-2.1-Q2_K.gguf',
      '%MODEL_CLIP%': 'Qwen3-VL-8B-Instruct-Q4_K_M.gguf',
      '%MODEL_VAE%': 'qwen_image_2.1_vae_bf16.safetensors',
    }.entries) {
      await s.setComfyCreateModelChoice('qwen_image_21', e.key, e.value);
    }
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final image = ImageGenService(storage);
    final facade = ChargenFacade(
      LLMProvider(
        KoboldService(storage),
        OpenRouterService(),
        storage,
        BackendManager(storage),
      ),
      CharacterFacade(
        db,
        storage,
        null,
        null,
        CharacterRepository(db, storage),
      ),
      null,
      image,
      storage,
    );

    final bytes = await facade
        .renderPortrait('Mara', 'a woman on a porch')
        .timeout(const Duration(seconds: 10));

    expect(bytes, isNull);
    expect(asked, 0);
    expect(image.statusMessage, contains(kCity96ConfirmOnDesktop));
    expect(loader.readAsStringSync(), kStockCity96Loader);
  });
}
