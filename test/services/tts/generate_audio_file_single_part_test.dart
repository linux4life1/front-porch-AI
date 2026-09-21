// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// generateAudioFile() must hand back a file that still EXISTS.
//
// The headless path (web/mobile Speak, story narration, audiobook export)
// used to run every result through WavUtils.concatenateWavFiles + a cleanup
// sweep. For a ONE-element list concatenateWavFiles returns that element by
// identity, so the sweep deleted the very file being returned — and every
// consumer checks existsSync() and silently gives up, so the PWA's Speak
// button simply produced nothing. One sentence is the common case (the
// splitter also merges short parts), and the default engine is affected.
//
// This drives the REAL TtsService against a loopback HTTP server standing in
// for the OpenAI TTS API — the one engine whose endpoint is configurable, so
// real WAV bytes can come back with no network and no model download.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import '../../golden/support/fakes_storage.dart';

/// Minimal 8-bit mono WAV with [samples] bytes of silence — enough for
/// WavUtils' 44-byte header parse to succeed when two parts are stitched.
Uint8List _wavBytes(int samples) {
  final bytes = BytesBuilder();
  final data = Uint8List(samples);
  final header = ByteData(44);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + data.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, 8000, Endian.little); // sample rate
  header.setUint32(28, 8000, Endian.little); // byte rate
  header.setUint16(32, 1, Endian.little); // block align
  header.setUint16(34, 8, Endian.little); // bits per sample
  ascii(36, 'data');
  header.setUint32(40, data.length, Endian.little);
  bytes.add(header.buffer.asUint8List());
  bytes.add(data);
  return bytes.toBytes();
}

class _TtsStorage extends FakeStorageService {
  _TtsStorage(this.baseUrl) {
    ttsSettings.setTtsEnabled(true);
    ttsSettings.setTtsEngine('openai');
    ttsSettings.setTtsVoiceModel('alloy');
    ttsSettings.setTtsReplaceCurlyQuotes(true);
    ttsSettings.setTtsConcurrency(2);
    ttsSettings.setTtsAudioLookahead(4);
    ttsSettings.setOpenaiTtsApiKey('test-key');
    ttsSettings.setOpenaiTtsModel('tts-1');
    ttsSettings.setOpenaiTtsBaseUrl(baseUrl);
    sttSettings.setCallBufferSentences(2);
  }

  final String baseUrl;
}

void _mockAudioChannels() {
  for (final name in [
    'xyz.luan/audioplayers',
    'xyz.luan/audioplayers.global',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannel(name),
          (MethodCall call) async => null,
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_mockAudioChannels);
  // flutter_test stubs HttpClient (every request answers 400); this suite
  // talks to a real loopback server, so restore real networking.
  setUpAll(() => HttpOverrides.global = null);

  late HttpServer api;
  late int requestCount;

  setUp(() async {
    requestCount = 0;
    api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api.listen((req) async {
      requestCount++;
      await req.drain<void>();
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('audio', 'wav')
        ..add(_wavBytes(160));
      await req.response.close();
    });
  });

  tearDown(() => api.close(force: true));

  TtsService makeTts() {
    final storage = _TtsStorage('http://127.0.0.1:${api.port}/v1');
    final tts = TtsService(storage, VoiceManager(storage));
    addTearDown(tts.dispose);
    return tts;
  }

  test(
    'a one-sentence line returns a file that still exists on disk',
    () async {
      final tts = makeTts();

      final file = await tts
          .generateAudioFile('She smiles at you.')
          .timeout(const Duration(seconds: 20));

      expect(requestCount, 1, reason: 'exactly one part was synthesised');
      expect(file, isNotNull);
      expect(
        file!.existsSync(),
        isTrue,
        reason:
            'the single generated part IS the result — cleanup must not '
            'delete the file that is being returned, or every consumer '
            '(voice_facade, audiobook export, story narration) drops it',
      );
      expect(file.lengthSync(), greaterThan(44));
      file.deleteSync();
    },
  );

  test(
    'multi-part text still stitches into one file and cleans up its parts',
    () async {
      final tts = makeTts();

      final file = await tts
          .generateAudioFile(
            'The porch light flickers once as the storm rolls in. '
            'She pulls the blanket tighter around her shoulders and waits.',
          )
          .timeout(const Duration(seconds: 20));

      expect(requestCount, 2, reason: 'two sentences, two synthesis calls');
      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
      // Stitched output carries both payloads, so it is longer than one part.
      expect(file.lengthSync(), greaterThan(44 + 160));
      file.deleteSync();
    },
  );
}
