// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Guards for KoboldService's half of the --jinja system-message workaround:
// WHEN the probe key is resolved, and what happens to it afterwards.
//
// The defect these were written for: the key was a getter that recomputed
// itself from three MUTABLE settings on every single generation, while only
// the model-ready transition ever armed the probe. So a `dropped` verdict was
// filed under the key as it read at load, and any later edit to a key
// component — the remote model name, a preset swap — moved the lookup off it
// and silently switched the workaround back OFF for the rest of the run, on a
// model still measured to drop. Same getter also put a synchronous preset-file
// read (existsSync + readAsStringSync + jsonDecode) on the per-generation
// path for every .kcpps user.
//
// The server here is a KoboldCpp stand-in that drops system messages, like
// intervitens-mini-magnum-12b-v1.1 does for real.
//
// ── Hermeticity, and why it is spelled out ────────────────────────────────
// The first version of this file was flaky at `--concurrency=4`, which is
// what CI runs, and green when run alone, which is how it was reported. Two
// causes, both of them "synchronise on the wrong thing":
//
//   1. It waited for THREE REQUESTS TO ARRIVE at the fake server and then
//      asserted the verdict. Arrival is not completion — the verdict is
//      written after the third RESPONSE comes back and is parsed — so the
//      assertion could run before the probe had decided. Reproduced under
//      load: `Expected: false  Actual: <null>`. Every wait here now goes
//      through the future `debugMarkModelReady()` returns, which IS the
//      measurement; there is no polling loop left.
//   2. It measured the engine's request slot with a stopwatch against fixed
//      response delays (arm the probe, sleep 20ms, assert waitForIdle takes
//      >= 100ms). Under a loaded CI box either side of that can slip. The
//      server is now GATED by the test — it accepts a request and answers
//      only when the test says so — so "is the slot held" is asked while the
//      answer cannot change, and the only sleep left asserts that something
//      has NOT happened yet, which load can only make more true.
//
// Every test also gets its own SystemRoleProbe, so no verdict map is shared
// between cases in this file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// KoboldService, StorageService, GenerationParams. system_role_probe.dart is
// deliberately NOT on this curated barrel (its only two production importers
// are its own siblings in lib/services/, which would self-import).
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/system_role_probe.dart';

// The path_provider mock + in-memory StorageService factory, rather than a
// second copy of the same 25 lines of scaffolding.
import 'kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

const String kCard =
    'You are Malumbra, an old warden of the Oblivian hall. Linus is the human '
    'you are talking with.';

const String kModel = '/models/mini-magnum-12b.gguf';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late HttpServer server;
  late StorageService storage;
  late KoboldService kobold;
  late List<Map<String, dynamic>> received;

  /// This case's own verdict map — see the header. Never
  /// [SystemRoleProbe.instance].
  late SystemRoleProbe probe;

  /// Installed by the tests that need the server frozen mid-request: the
  /// handler reads the request (so it lands in [received]) and then waits here
  /// before answering. Lets a test ask "is the engine slot held?" at a moment
  /// it controls, instead of racing a wall-clock delay.
  Completer<void>? hold;

  /// Woken by the handler as each request arrives. See [waitForRequests].
  Completer<void>? arrival;

  int wordsIn(Object? content) {
    if (content is! String) return 0;
    final t = content.trim();
    return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
  }

  /// Block until the server has READ [n] requests. Event-driven, not polled,
  /// and only ever used to establish "the probe is on the wire" — never to
  /// decide that the probe has FINISHED, which is the confusion that made this
  /// file flaky. The timeout exists so a genuine hang fails loudly instead of
  /// wedging CI.
  Future<void> waitForRequests(int n) async {
    while (received.length < n) {
      arrival = Completer<void>();
      await arrival!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => fail(
          'the fake backend only ever saw ${received.length} of $n requests',
        ),
      );
    }
  }

  setUp(() async {
    HttpOverrides.global = null;
    received = [];
    hold = null;
    arrival = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      received.add(payload);
      final waiter = arrival;
      arrival = null;
      waiter?.complete();
      if (hold != null) await hold!.future;
      // A cancelled probe closes its socket mid-request; writing to it throws,
      // and an unhandled throw in this handler would poison later tests.
      try {
        // A template with no system branch: the message contributes nothing.
        var prompt = 6;
        for (final m in (payload['messages'] as List).cast<Map>()) {
          if (m['role'] != 'system') prompt += wordsIn(m['content']);
        }
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType('application', 'json');
        req.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'ok'},
                'finish_reason': 'length',
              },
            ],
            'usage': {'prompt_tokens': prompt, 'completion_tokens': 1},
          }),
        );
        await req.response.close();
      } catch (_) {
        // Socket already gone — the client cancelled. Nothing to report.
      }
    });
    storage = await createStorageService();
    // Its OWN probe, never SystemRoleProbe.instance: a verdict map shared
    // across test cases is shared state, and this file has no need of it.
    probe = SystemRoleProbe();
    kobold = KoboldService(storage, systemRoleProbe: probe);
    kobold.setBaseUrl('http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    // Release anything still frozen so the handler can unwind before the
    // server goes away.
    if (hold != null && !hold!.isCompleted) hold!.complete();
    hold = null;
    kobold.dispose();
    await server.close(force: true);
  });

  /// Bring the model up and wait for the measurement it arms to SETTLE — the
  /// future `debugMarkModelReady` returns is the probe chain itself, so this
  /// returns exactly when a verdict exists (or the retry budget is spent).
  Future<String> loadModel(String modelPath) async {
    await storage.backendSettings.setLastUsedModelPath(modelPath);
    received.clear();
    await kobold.debugMarkModelReady();
    return kobold.systemRoleIdentity;
  }

  Future<List<Map>> generate() async {
    received.clear();
    await kobold
        .generateStream(
          const GenerationParams(prompt: 'Hello there.', systemPrompt: kCard),
        )
        .toList();
    return (received.last['messages'] as List).cast<Map>();
  }

  test(
    'the model-ready transition resolves the probe key and measures it',
    () async {
      expect(
        kobold.systemRoleIdentity,
        isEmpty,
        reason: 'nothing to probe before a model is up',
      );

      final identity = await loadModel(kModel);

      expect(identity, contains('mini-magnum-12b.gguf'));
      expect(
        probe.verdictFor(identity),
        isFalse,
        reason: 'this fake template drops the system message',
      );

      // And the workaround is actually in effect: no system message on the wire,
      // the card riding the user turn instead.
      final messages = await generate();
      expect(messages.any((m) => m['role'] == 'system'), isFalse);
      expect(messages.single['content'], startsWith(kCard));
    },
  );

  test(
    'editing an unrelated setting cannot switch the workaround back off',
    () async {
      final identity = await loadModel(kModel);
      expect(probe.verdictFor(identity), isFalse);

      // The remote model name is part of the identity key but has nothing to do
      // with the running local model. Someone browsing OpenRouter models in
      // Settings used to silently un-fix their local chat.
      await storage.backendSettings.setRemoteModelName(
        'anthropic/claude-opus-4',
      );
      expect(
        kobold.systemRoleIdentity,
        identity,
        reason: 'the key is resolved once at model-ready, not per generation',
      );

      final messages = await generate();
      expect(
        messages.any((m) => m['role'] == 'system'),
        isFalse,
        reason: 'the card must still be folded into the user turn',
      );
      expect(messages.single['content'], startsWith(kCard));
    },
  );

  test(
    'stopping the backend forgets the verdict and refunds the budget',
    () async {
      final identity = await loadModel(kModel);
      expect(probe.verdictFor(identity), isFalse);

      await kobold.stopKobold();

      expect(
        probe.verdictFor(identity),
        isNull,
        reason: 'a verdict must not outlive the server it was measured on',
      );
      expect(kobold.systemRoleIdentity, isEmpty);
      // Nothing folds while no model is up, so the very first request after a
      // stop can never carry the previous model's workaround.
      final messages = await generate();
      expect(messages.first['role'], 'system');
    },
  );

  test('stopping the backend cancels a probe still on the wire', () async {
    // The other half of the stop: forgetting the verdict is not enough if the
    // measurement itself keeps running. Every probe arm holds this class's
    // single request slot, so an arm left waiting on a server that has just
    // been killed blocks the next model's probe AND the user's first message
    // until it times out — kSystemRoleProbeTimeout is 60 seconds.
    //
    // The server is frozen for the whole test and NEVER answers this arm, so
    // the only thing that can release the slot is the cancel itself.
    hold = Completer<void>();
    await storage.backendSettings.setLastUsedModelPath(kModel);
    final settled = kobold.debugMarkModelReady();
    final identity = kobold.systemRoleIdentity;
    await waitForRequests(1); // arm one is on the wire

    await kobold.stopKobold();

    await kobold.waitForIdle().timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail('the killed probe still owns the request slot'),
    );
    await settled.timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail('the cancelled probe chain never unwound'),
    );
    expect(probe.verdictFor(identity), isNull);
    expect(received.length, 1, reason: 'no further arms after the stop');
  });

  test(
    'a probe in flight occupies the engine\'s single request slot',
    () async {
      // The probe used to take ONE `waitForIdle` reading before its first arm
      // and then register nothing, so it neither waited properly nor made
      // anyone wait for it — its requests could land in the middle of the
      // user's own generation on a single-slot local engine. Every arm now
      // runs through the same `_pendingRequest` registration generateWithTools
      // uses, which is what `waitForIdle` observes.
      hold = Completer<void>();
      await storage.backendSettings.setLastUsedModelPath(kModel);
      final settled = kobold.debugMarkModelReady();
      await waitForRequests(1); // arm one has claimed the slot

      var idle = false;
      unawaited(kobold.waitForIdle().then((_) => idle = true));
      // The arm cannot finish while the server is frozen, so this window only
      // gives waitForIdle a chance to resolve EARLY — which is the failure. A
      // slow machine makes "not yet idle" more true, never less, so there is no
      // wall-clock race in either direction.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        idle,
        isFalse,
        reason:
            'waitForIdle returned while a probe arm was still on the '
            'wire — a real generation could have raced it',
      );

      hold!.complete(); // let the server answer; the chain runs to the end
      await settled;
      await kobold.waitForIdle();
      expect(
        idle,
        isTrue,
        reason: 'the slot was released when the arm finished',
      );
    },
  );

  test(
    'a model swap re-keys instead of inheriting the old model\'s verdict',
    () async {
      final magnum = await loadModel(kModel);
      expect(probe.verdictFor(magnum), isFalse);

      final gemma = await loadModel('/models/gemma-4-31B.gguf');

      expect(gemma, isNot(magnum));
      expect(gemma, contains('gemma-4-31B.gguf'));
      expect(
        probe.verdictFor(gemma),
        isFalse,
        reason: 'the new model is measured on its own account',
      );
    },
  );
}
