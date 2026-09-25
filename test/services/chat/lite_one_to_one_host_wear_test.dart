// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// HOLD: 1:1 Scene Guest lite ticks still move the chat clock. They must
// not tax the host's Needs from the clock. An aborted lite finalize must
// not invent that tax either.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_11_wear_').path;
        }
        return null;
      });
}

const _hostNeeds = {
  'hunger': 40,
  'bladder': 80,
  'energy': 80,
  'social': 80,
  'fun': 80,
  'hygiene': 80,
  'comfort': 80,
};

class _ScriptedLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*Riley leans on the rail.*';
      return;
    }
    if (params.prompt.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedOneToOneWear';
}

class _HangSecondClockLlm extends LLMService {
  Completer<void>? _hang;
  int clockCalls = 0;

  void releaseHang() {
    final hang = _hang;
    if (hang != null && !hang.isCompleted) hang.complete();
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*Riley leans on the rail.*';
      return;
    }
    if (params.prompt.contains('minutes_elapsed')) {
      clockCalls++;
      if (clockCalls == 2) {
        _hang = Completer<void>();
        await _hang!.future;
      }
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'HangSecondClock';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  CharacterRepository? repo;
  ChatService? chat;
  LLMService? llm;
  DebugPrintCallback? previousPrint;
  late CharacterCard host;
  late CharacterCard guest;

  Future<void> drainTurn() async {
    for (
      var i = 0;
      i < 400 && (chat!.isGenerating || chat!.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> waitUntil(bool Function() pred) async {
    for (var i = 0; i < 250 && !pred(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> boot(LLMService override) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': true,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    repo = CharacterRepository(db!, storage!);
    llm = override;
    chat =
        ChatService(
            KoboldService(storage!),
            UserPersonaService(db!),
            storage!,
            WorldRepository(storage!, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo!)
          ..testLlmServiceOverride = llm;
    await storage!.initialized;

    host = CharacterCard(
      name: 'Flora',
      firstMessage: 'Evening.',
      imagePath: '/tmp/flora-host.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
        needsBaselineHunger: 40,
      ),
    );
    guest = CharacterCard(
      name: 'Riley',
      firstMessage: 'Hi.',
      imagePath: '/tmp/riley-guest.png',
      frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
    );
    await repo!.addCharacter(host);
    await repo!.addCharacter(guest);
    await chat!.setActiveCharacter(host);
    await chat!.setRealismEnabled(true);
    await chat!.setNeedsSimEnabled(true);
    await chat!.setPassageOfTimeEnabled(true);
    chat!.needsSimulation.restoreFromSnapshot({'vector': _hostNeeds});
    await chat!.joinSceneGuest(guest);
    await drainTurn();
    // Entrance is itself a lite tick. Re-seed so the turn under test starts
    // from a known 40 — the stamp on the entrance bubble is not this pin.
    chat!.needsSimulation.restoreFromSnapshot({'vector': _hostNeeds});
  }

  int hunger() => chat!.needsSimulation.vector['hunger']!;

  CharacterCard liveGuest() =>
      chat!.sceneGuestCards.firstWhere((c) => c.name == 'Riley');

  setUp(() {
    previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
  });

  tearDown(() async {
    debugPrint = previousPrint ?? debugPrint;
    await disposeChatThenCloseDb(chat, db);
  });

  test(
    '1:1 guest turn stamps time without taxing the host; regen/swipe stay put',
    () async {
      await boot(_ScriptedLlm());
      expect(hunger(), 40);

      await chat!.speakGuestNow(liveGuest());
      await drainTurn();
      expect(
        hunger(),
        40,
        reason: '30 min on the clock is not a host body tax',
      );
      final reply = chat!.messages.lastWhere((m) => !m.isUser);
      expect(reply.sender, 'Riley');
      expect(reply.activeMetadata?['time_passed'], '30 min');

      await chat!.regenerateLastMessage();
      await drainTurn();
      expect(
        hunger(),
        40,
        reason: 'guest regen must not invent a clock tax on the host',
      );
      expect(chat!.messages.last.swipes.length, greaterThan(1));
      expect(chat!.messages.last.activeMetadata?['time_passed'], '30 min');

      final idx = chat!.messages.indexOf(chat!.messages.last);
      await chat!.swipeMessage(idx, -1);
      await drainTurn();
      expect(hunger(), 40);
    },
  );

  test('delete of a 1:1 guest reply does not invent host wear', () async {
    await boot(_ScriptedLlm());
    await chat!.speakGuestNow(liveGuest());
    await drainTurn();
    expect(hunger(), 40);

    final idx = chat!.messages.indexWhere(
      (m) => !m.isUser && m.sender == 'Riley' && m == chat!.messages.last,
    );
    expect(idx, greaterThanOrEqualTo(0));
    chat!.deleteMessage(idx);
    await drainTurn();
    expect(
      hunger(),
      40,
      reason: 'tail-delete must not invent a drop the clock never applied',
    );
  });

  test('aborted lite finalize does not leave host wear applied', () async {
    final hang = _HangSecondClockLlm();
    await boot(hang);
    expect(hunger(), 40);
    expect(hang.clockCalls, 1);

    final sent = chat!.sendMessage('Riley, say hello.');
    await waitUntil(() => hang.clockCalls >= 2);
    expect(chat!.isSettlingTurn, isTrue);
    expect(hunger(), 40);

    // Same flag regen sets. Release the clock hang AFTER abort so the
    // decide can still apply minutes — unfixed lite would then wear.
    chat!.debugRequestPostGenAbort();
    hang.releaseHang();
    await sent;
    await drainTurn();
    expect(chat!.messages.last.sender, 'Riley');
    expect(
      hunger(),
      40,
      reason: 'aborted lite finalize must not invent a clock tax on the host',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
