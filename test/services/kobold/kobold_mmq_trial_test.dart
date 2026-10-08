// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Auto mode learns whether MMQ is faster on this card from the speeds
// KoboldCpp prints after each reply: MMQ on for a while, then off, then the
// faster is kept. Only some replies can be timed (the prompt read must be
// long enough to say how fast it was read), and the learning has to go by
// those: going by every reply that was printed ended the "on" trial after
// three short replies, left MMQ off from then on, and could never learn
// anything, because "off" only grows while the trial is "off".

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../golden/support/fakes_storage.dart';
import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

String _line(int read, double readSeconds, int written, double writeSeconds) =>
    '[10:01:02] CtxLimit:${read + written}/16384, Init:0.01s, '
    'Processed:$read in ${readSeconds}s '
    '(${(read / readSeconds).toStringAsFixed(2)}T/s), '
    'Generated:$written/$written in ${writeSeconds}s '
    '(${(written / writeSeconds).toStringAsFixed(2)}T/s), '
    'Total:${readSeconds + writeSeconds}s';

// A long read and a real reply, with MMQ on and off (a GTX 1060's figures).
final _on = _line(32668, 42.892, 100, 10.104);
final _off = _line(32668, 33.044, 100, 4.989);

// A chat reply that read only what the user just wrote: it says how fast
// the card writes, and nothing of how fast it reads a prompt.
final _short = _line(54, 0.30, 40, 1.0);

// A judge's answer after a long prompt: it says how fast the card reads, and
// nothing of how fast it writes.
final _long = _line(32668, 42.892, 5, 0.5);

const _card = 'NVIDIA GeForce GTX 1060 6GB';
const _version = '1.122.1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  group('the replies that are timed', () {
    test('three replies too short to time do not end the "on" trial', () {
      final b = FakeStorageService().backendSettings;
      expect(b.mmqForLaunch(_card, _version), isTrue, reason: 'on first');
      for (var i = 0; i < 3; i++) {
        b.noteKoboldOutput('$_short\n');
      }
      expect(
        b.mmqForLaunch(_card, _version),
        isTrue,
        reason: 'nothing has been learned about "on" yet',
      );
      for (var i = 0; i < 3; i++) {
        b.noteKoboldOutput('$_on\n');
      }
      expect(
        b.mmqForLaunch(_card, _version),
        isFalse,
        reason: 'with three that could be timed, "on" is done',
      );
    });

    test('long replies that come rarely, among many short ones, still '
        'finish the timing of each', () {
      final b = FakeStorageService().backendSettings;
      void chat(String long) {
        // A long read, then a stretch of short replies.
        b.noteKoboldOutput('$long\n');
        for (var i = 0; i < 12; i++) {
          b.noteKoboldOutput('$_short\n');
        }
      }

      expect(b.mmqForLaunch(_card, _version), isTrue);
      for (var i = 0; i < 3; i++) {
        chat(_on);
      }
      expect(b.mmqForLaunch(_card, _version), isFalse, reason: 'then off');
      expect(b.mmqFor(_card, _version), isNull);
      for (var i = 0; i < 3; i++) {
        chat(_off);
      }
      expect(b.mmqFor(_card, _version), isFalse, reason: 'off was faster');
    });
  });

  group('what is kept of the replies', () {
    KoboldSpeed speed(String line) => parseKoboldSpeed(line)!;

    test('replies that only say how fast it reads do not push out the ones '
        'that say how fast it writes', () {
      final b = FakeStorageService().backendSettings;
      expect(b.mmqForLaunch(_card, _version), isTrue);
      for (var i = 0; i < 3; i++) {
        b.noteKoboldOutput('$_short\n');
      }
      // Far more than the eight a plain window would hold.
      for (var i = 0; i < 20; i++) {
        b.noteKoboldOutput('$_long\n');
      }
      expect(
        b.mmqForLaunch(_card, _version),
        isFalse,
        reason: '"on" has three that read and three that wrote',
      );
    });

    test('the newest eight of each kind are kept, in order, and a reply '
        'that is neither is not', () {
      final neither = speed(_line(54, 0.30, 5, 0.5));
      final reads = [
        for (var i = 0; i < 10; i++) speed(_line(1000 + i, 1.0, 5, 0.5)),
      ];
      final writes = [
        for (var i = 0; i < 10; i++) speed(_line(54, 0.30, 100 + i, 1.0)),
      ];
      final kept = koboldKeepTimed([
        neither,
        for (var i = 0; i < 10; i++) ...[reads[i], writes[i]],
        neither,
      ]);
      expect(kept, [
        for (var i = 2; i < 10; i++) ...[reads[i], writes[i]],
      ]);
      expect(koboldKeepTimed([neither, neither]), isEmpty);
    });
  });

  group('a launch that is not auto mode on CUDA', () {
    final nvidia = HardwareInfo(
      gpuName: _card,
      vramMb: 6144,
      ramMb: 16384,
      vendor: 'Nvidia',
      hasCuda: true,
    );

    late StorageService storage;
    late Directory binDir;

    setUp(() async {
      storage = await createStorageService();
      binDir = Directory.systemTemp.createTempSync('fpai_mmq_trial_');
    });

    tearDown(() => binDir.deleteSync(recursive: true));

    Future<void> launch({
      bool cublas = false,
      bool vulkan = false,
      String? preset,
    }) => buildKoboldLaunchArgs(
      storage: storage,
      executablePath: '${binDir.path}/koboldcpp',
      modelPath: '/models/a.gguf',
      kcppsPath: preset,
      mmprojPath: null,
      port: 5001,
      gpuLayers: 0,
      contextSize: 8192,
      useVulkan: vulkan,
      useCublas: cublas,
      useMetal: false,
      useRocm: false,
      hardware: nvidia,
    );

    /// A trial is open after an auto-mode launch on CUDA; whatever the next
    /// launch is, the replies of the engine it starts are then counted for
    /// "on" or not. True when three replies that could be timed were not
    /// counted, so "on" still has to be timed.
    bool onStillToTime() {
      for (var i = 0; i < 3; i++) {
        storage.backendSettings.noteKoboldOutput('$_on\n');
      }
      return storage.backendSettings.mmqForLaunch(_card, null);
    }

    test('an auto-mode launch on CUDA starts the trial', () async {
      await launch(cublas: true);
      expect(onStillToTime(), isFalse, reason: 'its replies were counted');
    });

    test('a preset launch ends it: the engine runs the user\'s file, not '
        'what auto mode is timing', () async {
      await launch(cublas: true);
      final file = File('${binDir.path}/mine.kcpps')
        ..writeAsStringSync(jsonEncode({'contextsize': 8192}));
      await launch(cublas: true, preset: file.path);
      expect(onStillToTime(), isTrue);
    });

    test('a launch on another backend ends it', () async {
      await launch(cublas: true);
      await launch(vulkan: true);
      expect(onStillToTime(), isTrue);
    });
  });
}
