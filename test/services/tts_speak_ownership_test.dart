// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Two speak() defects the 1.3 sweep confirmed, guarded against the REAL
// TtsService (tts_service_orchestration_test.dart is the precedent for
// driving it offline; this file goes one step further and gives the cloud
// engine a LOOPBACK server so generation actually produces audio files):
//
//  1. A single generated file was deleted before it could be played.
//     WavUtils.concatenateWavFiles hands back the very same File for a
//     one-element list, and the cleanup on the next line unlinked it. The
//     ElevenLabs-only guard above it did not cover OpenAI, and _splitSentences
//     merges aggressively — so any short reply produced exactly one file and
//     TTS went silently dead.
//
//  2. speak() had no supersede token. A second Speak sets _isSpeaking back to
//     true, so the first — still suspended inside generation — woke up,
//     believed it was still the active utterance, played its own audio over
//     the new one, and cleared the new one's speaking state on the way out.
//
// No network beyond 127.0.0.1, no model files, no real voice.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import '../golden/support/fakes_storage.dart';

/// TtsService constructs an [AudioPlayer] eagerly, which fires a platform
/// `create` call the headless test binding has no implementation for. Same
/// mock (and same two channel names) as tts_service_orchestration_test.dart.
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

/// Everything TtsService's cloud path reads, pointed at a local fake server.
class _CloudProbeStorage extends FakeStorageService {
  _CloudProbeStorage(this.baseUrl) {
    ttsSettings.setTtsEnabled(true);
    ttsSettings.setTtsEngine('openai');
    ttsSettings.setTtsVoiceModel('alloy');
    ttsSettings.setTtsConcurrency(2);
    ttsSettings.setTtsAudioLookahead(4);
    ttsSettings.setOpenaiTtsApiKey('test-key');
    ttsSettings.setOpenaiTtsModel('tts-1');
    ttsSettings.setOpenaiTtsBaseUrl(baseUrl);
    sttSettings.setCallBufferSentences(2);
  }

  final String baseUrl;
}

/// A real (if very short) 16-bit mono PCM WAV, so playback is handed
/// something a decoder accepts instead of garbage.
Uint8List _silentWav({int samples = 400, int rate = 8000}) {
  final dataBytes = samples * 2;
  final data = ByteData(44 + dataBytes);
  final bytes = data.buffer.asUint8List();
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  data.setUint32(4, 36 + dataBytes, Endian.little);
  bytes.setRange(8, 12, ascii.encode('WAVE'));
  bytes.setRange(12, 16, ascii.encode('fmt '));
  data.setUint32(16, 16, Endian.little); // fmt chunk size
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little); // byte rate
  data.setUint16(32, 2, Endian.little); // block align
  data.setUint16(34, 16, Endian.little); // bits per sample
  bytes.setRange(36, 40, ascii.encode('data'));
  data.setUint32(40, dataBytes, Endian.little);
  return bytes;
}

/// The temp files OpenAiTtsEngine writes, by path.
Set<String> _generatedWavPaths() => Directory.systemTemp
    .listSync()
    .whereType<File>()
    .map((f) => f.path)
    .where(
      (p) => p.split(Platform.pathSeparator).last.startsWith('openai_tts_'),
    )
    .toSet();

Future<void> _pumpUntil(
  bool Function() done, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition never became true within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    _mockAudioChannels();
    // flutter_test installs an HttpOverrides that answers every request with
    // 400; clearing it restores the real client so the loopback server below
    // is actually reachable (same trick as open_router_tools_test.dart).
    HttpOverrides.global = null;
  });

  late HttpServer server;

  /// Requests the fake TTS endpoint has received, and (optionally) a gate a
  /// test can hold a response behind to control the race.
  late List<String> requestedText;
  late Completer<void>? Function(String text) gateFor;

  setUp(() async {
    requestedText = [];
    gateFor = (_) => null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final input = (jsonDecode(body) as Map)['input'] as String;
      requestedText.add(input);
      final gate = gateFor(input);
      if (gate != null) await gate.future;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('audio', 'wav')
        ..add(_silentWav());
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  TtsService makeTts() {
    final storage = _CloudProbeStorage('http://127.0.0.1:${server.port}');
    final tts = TtsService(storage, VoiceManager(storage));
    addTearDown(tts.dispose);
    return tts;
  }

  test(
    'a reply that generates exactly ONE audio file keeps that file — the '
    'concat passthrough must not be followed by a cleanup that deletes it',
    () async {
      final tts = makeTts();
      final before = _generatedWavPaths();

      // One sentence in, one file out (that is the whole bug's precondition).
      unawaited(tts.speak('Hi there friend.', messageId: 'm1'));

      // Wait until generation is finished and playback has been reached.
      await _pumpUntil(() => tts.isSpeaking && !tts.isGenerating);
      // …and give the concatenate/cleanup step its turn of the event loop.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(requestedText, hasLength(1), reason: 'one sentence, one request');
      expect(
        _generatedWavPaths().difference(before),
        isNotEmpty,
        reason:
            'the audio the user is about to hear (and that gets cached '
            'for instant replay) must still exist on disk at playback time',
      );

      await tts.stop();
      // Let the suspended speak() unwind before the tearDown disposes it.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
  );

  test(
    'a second Speak supersedes the first: the first must not play, must not '
    'take the cache, and must not switch off the Speak that replaced it',
    () async {
      final tts = makeTts();
      final gateA = Completer<void>();
      final gateB = Completer<void>();
      gateFor = (text) => text.contains('Alpha') ? gateA : gateB;

      final first = tts.speak('Alpha alpha alpha alpha.', messageId: 'A');
      await _pumpUntil(() => requestedText.length == 1);

      final second = tts.speak('Beta beta beta beta.', messageId: 'B');
      await _pumpUntil(() => requestedText.length == 2);
      expect(
        tts.currentMessageId,
        'B',
        reason: 'the newer Speak owns the service once it has claimed state',
      );

      // The first utterance's audio arrives late — long after it lost the
      // service. It must go quietly.
      gateA.complete();
      await first.timeout(
        const Duration(seconds: 3),
        onTimeout: () {}, // with the bug it blocks in playback; assert anyway
      );

      expect(
        tts.currentMessageId,
        'B',
        reason:
            'the superseded call cleared the new utterance\'s state on '
            'its way out — Speak looked dead while B was still generating',
      );
      expect(tts.isSpeaking, isTrue, reason: 'B is still the active utterance');
      expect(
        tts.isGenerating,
        isTrue,
        reason: 'B is still generating; only A finished, and A is nobody',
      );

      gateB.complete();
      await tts.stop();
      await second.timeout(const Duration(seconds: 3), onTimeout: () {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
  );
}
