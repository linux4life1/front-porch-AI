// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live Mac fail (Carmen 1:1, PR #303 tip): character-edit Needs ON and
// Porch Life Needs ON, Trust chips move, but the sidebar Needs strip is
// missing — the chat acts like Needs is off.
//
// Cause: sessions.needs_sim_enabled defaults FALSE and hydrate trusts
// only that column. Card + Porch Life are AND-ed at new-chat seed, not
// on load. Sidebar bars require chat.needsSimEnabled && vector.isNotEmpty.
// Opening a lived-in 1:1 after checkout therefore clears the vector.
//
// Proven red on 5eccc1b0: load of a Carmen row with needsSimEnabled=false
// left chat.needsSimEnabled false and an empty vector.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/chat.dart'
    show needsSimAfterHydrate, visibleNeeds;
import 'package:front_porch_ai/services/services.dart';

class _ScriptedLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      yield '{"with_user": true}';
      return;
    }
    if (p.contains('hunger_delta')) {
      yield '{"hunger_delta": 0, "bladder_delta": 0, "energy_delta": 0, '
          '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
          '"comfort_delta": 0, "reason": "none"}';
      return;
    }
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":1,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    if (params.systemPrompt != null) {
      yield '*Carmen leans on the rail.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedNeedsGate';
}

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_needs_gate_').path;
        }
        return null;
      });
}

Future<void> _drain() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

CharacterCard _carmen({required bool cardNeeds, bool cardRealism = true}) {
  return CharacterCard(
    name: 'Carmen',
    firstMessage: 'Evening.',
    imagePath: '/tmp/carmen-gate.png',
    frontPorchExtensions: FrontPorchExtensions(
      realismEnabled: cardRealism,
      needsSimEnabled: cardNeeds,
      passageOfTimeEnabled: true,
      needsBaselineHunger: 80,
      needsBaselineBladder: 80,
      needsBaselineEnergy: 80,
      needsBaselineSocial: 80,
      needsBaselineFun: 80,
      needsBaselineHygiene: 80,
      needsBaselineComfort: 80,
    ),
  )..dbId = 'carmen-gate';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('needsSimAfterHydrate promotes stale 1:1 off, not groups or vetoes', () {
    expect(
      needsSimAfterHydrate(
        sessionEnabled: false,
        cardEnabled: true,
        globalDefault: true,
        hasSavedVector: false,
        isGroup: false,
      ),
      isTrue,
    );
    expect(
      needsSimAfterHydrate(
        sessionEnabled: false,
        cardEnabled: false,
        globalDefault: true,
        hasSavedVector: false,
        isGroup: false,
      ),
      isFalse,
    );
    expect(
      needsSimAfterHydrate(
        sessionEnabled: false,
        cardEnabled: true,
        globalDefault: false,
        hasSavedVector: false,
        isGroup: false,
      ),
      isFalse,
    );
    expect(
      needsSimAfterHydrate(
        sessionEnabled: false,
        cardEnabled: false,
        globalDefault: false,
        hasSavedVector: true,
        isGroup: false,
      ),
      isTrue,
    );
    expect(
      needsSimAfterHydrate(
        sessionEnabled: false,
        cardEnabled: true,
        globalDefault: true,
        hasSavedVector: false,
        isGroup: true,
      ),
      isFalse,
    );
  });

  test('empty needsOff does not empty the strip', () {
    const vector = {'hunger': 80, 'bladder': 80};
    expect(visibleNeeds(vector, const []), vector);
  });

  AppDatabase? db;
  StorageService? storage;
  CharacterRepository? repo;
  ChatService? chat;
  DebugPrintCallback? previousPrint;

  setUp(() {
    previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
  });

  Future<void> boot({
    bool needsGlobal = true,
    bool realismGlobal = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'needs_sim_default': needsGlobal,
      'realism_default': realismGlobal,
      'passage_of_time_default': true,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    repo = CharacterRepository(db!, storage!);
    chat =
        ChatService(
            KoboldService(storage!),
            UserPersonaService(db!),
            storage!,
            WorldRepository(storage!, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo!)
          ..testLlmServiceOverride = _ScriptedLlm();
    await storage!.initialized;
  }

  Future<void> plantSession({
    required bool sessionNeeds,
    String? needsVector,
  }) async {
    await db!.insertSession(
      SessionsCompanion.insert(
        id: 'carmen-sess',
        characterId: const Value('carmen-gate'),
        realismEnabled: const Value(true),
        passageOfTimeEnabled: const Value(true),
        needsSimEnabled: Value(sessionNeeds),
        needsVector: Value(needsVector),
      ),
    );
    // Lived-in transcript. An empty row re-seeds from the card
    // (`if (_messages.isEmpty)`), which hid this mismatch. Carmen
    // already had replies — Trust moved — so hydrate is the authority.
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'carmen-m0',
        sessionId: 'carmen-sess',
        position: 0,
        sender: 'Carmen',
        isUser: false,
        swipes: Value(jsonEncode(['Evening.'])),
      ),
    );
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'carmen-m1',
        sessionId: 'carmen-sess',
        position: 1,
        sender: 'You',
        isUser: true,
        swipes: Value(jsonEncode(['How are you?'])),
      ),
    );
  }

  bool sidebarWouldShowBars() {
    // Mirrors character_state_group.dart 1:1 gate. Realism is NOT
    // part of it — bars answer to the Needs switch.
    return chat!.needsSimEnabled && chat!.needsSimulation.vector.isNotEmpty;
  }

  tearDown(() async {
    debugPrint = previousPrint ?? debugPrint;
    chat?.dispose();
    await _drain();
    await db?.close();
    await _drain();
  });

  test(
    '1:1 Carmen: card+Porch Life ON promote a session that still has needsSim false',
    () async {
      await boot();
      await plantSession(sessionNeeds: false);
      final carmen = _carmen(cardNeeds: true);
      final c = chat!;
      await c.setActiveCharacter(carmen);

      expect(
        c.needsSimEnabled,
        isTrue,
        reason:
            'hydrate must not treat sessions.needs_sim_enabled=false as '
            'user-off when the card and Porch Life both ask for Needs',
      );
      expect(
        c.needsSimulation.vector,
        isNotEmpty,
        reason: 'sidebar bars also require a live vector',
      );
      expect(sidebarWouldShowBars(), isTrue);
      expect(
        visibleNeeds(
          c.needsSimulation.vector,
          carmen.frontPorchExtensions?.needsOff ?? const [],
        ),
        isNotEmpty,
        reason: 'empty needsOff must not empty the strip',
      );
      expect(c.needsSimulation.vector['hunger'], 80);

      await c.sendMessage('Still here?');
      for (var i = 0; i < 400 && (c.isGenerating || c.isSettlingTurn); i++) {
        await Future<void>.delayed(Duration.zero);
      }
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        c.needsSimulation.vector['hunger'],
        78,
        reason: 'once bars exist, a 30-min 1:1 send must wear',
      );
      expect(
        c.messages.lastWhere((m) => !m.isUser).activeMetadata?['time_passed'],
        '30 min',
        reason: 'live fail: no time_passed chip on a normal 1:1 send',
      );
    },
  );

  test('1:1 does not invent Needs when the card is still off', () async {
    await boot();
    await plantSession(sessionNeeds: false);
    final c = chat!;
    await c.setActiveCharacter(_carmen(cardNeeds: false));

    expect(c.needsSimEnabled, isFalse);
    expect(c.needsSimulation.vector, isEmpty);
    expect(sidebarWouldShowBars(), isFalse);
  });

  test('1:1 does not invent Needs when Porch Life Needs is off', () async {
    await boot(needsGlobal: false);
    await plantSession(sessionNeeds: false);
    final c = chat!;
    await c.setActiveCharacter(_carmen(cardNeeds: true));

    expect(
      c.needsSimEnabled,
      isFalse,
      reason:
          'Porch Life is the seed AND — a stale false row stays off '
          'when the global veto is on',
    );
    expect(sidebarWouldShowBars(), isFalse);
  });

  test(
    'saved needs vector is restored even if the session flag is still false',
    () async {
      await boot();
      await plantSession(
        sessionNeeds: false,
        needsVector: jsonEncode({
          'vector': {
            'hunger': 71,
            'bladder': 80,
            'energy': 80,
            'social': 80,
            'fun': 80,
            'hygiene': 80,
            'comfort': 80,
          },
        }),
      );
      final c = chat!;
      await c.setActiveCharacter(_carmen(cardNeeds: false));

      expect(
        c.needsSimEnabled,
        isTrue,
        reason:
            'a stored vector means this chat already ran Needs — '
            'hide ≠ erase; do not clear it because the column defaulted 0',
      );
      expect(c.needsSimulation.vector['hunger'], 71);
      expect(sidebarWouldShowBars(), isTrue);
    },
  );

  test(
    'brand-new 1:1 startNewChat seeds bars when card+Porch Life Needs are ON',
    () async {
      await boot();
      final carmen = _carmen(cardNeeds: true);
      await repo!.addCharacter(carmen);
      final c = chat!;
      await c.setActiveCharacter(carmen);
      await c.startNewChat();

      expect(
        c.needsSimEnabled,
        isTrue,
        reason:
            'New Chat must AND the card with Porch Life, not leave '
            'the chat-scoped flag false',
      );
      expect(
        c.needsSimulation.vector,
        isNotEmpty,
        reason:
            'live Mac: brand-new Carmen, Needs toggle ON, sidebar had '
            'no bars — vector was empty',
      );
      expect(sidebarWouldShowBars(), isTrue);
      expect(c.needsSimulation.vector['hunger'], 80);
    },
  );

  test('Needs off then on reseeds the 1:1 vector so bars come back', () async {
    await boot();
    final carmen = _carmen(cardNeeds: true);
    await repo!.addCharacter(carmen);
    final c = chat!;
    await c.setActiveCharacter(carmen);
    await c.startNewChat();
    await c.setNeedsSimEnabled(false);
    expect(c.needsSimEnabled, isFalse);
    expect(sidebarWouldShowBars(), isFalse, reason: 'off must hide the strip');

    await c.setNeedsSimEnabled(true);
    expect(c.needsSimEnabled, isTrue);
    expect(
      c.needsSimulation.vector,
      isNotEmpty,
      reason:
          'live Mac: flip Needs off→on still no bars — re-enable must '
          'seed a vector, not leave {}',
    );
    expect(sidebarWouldShowBars(), isTrue);
    expect(
      () => (carmen.frontPorchExtensions!.needsOff).add('fun'),
      returnsNormally,
      reason: 're-enable Save must not hit an unmodifiable needsOff',
    );
  });

  test('chat Needs toggle seeds bars even when the card never asked', () async {
    await boot();
    final carmen = _carmen(cardNeeds: false);
    await repo!.addCharacter(carmen);
    final c = chat!;
    await c.setActiveCharacter(carmen);
    await c.startNewChat();
    expect(c.needsSimEnabled, isFalse);
    expect(c.needsSimulation.vector, isEmpty);

    await c.setNeedsSimEnabled(true);
    expect(
      c.needsSimEnabled,
      isTrue,
      reason: 'the chat-scoped switch is the live gate, not the card',
    );
    expect(
      c.needsSimulation.vector,
      isNotEmpty,
      reason:
          'flip Needs on mid-chat must seed baselines — empty '
          '{} is the live Mac no-bars fail',
    );
    expect(sidebarWouldShowBars(), isTrue);
  });

  test(
    'brand-new 1:1 seeds Needs bars when Realism default is still off',
    () async {
      await boot(realismGlobal: false);
      final carmen = _carmen(cardNeeds: true, cardRealism: false);
      await repo!.addCharacter(carmen);
      final c = chat!;
      await c.setActiveCharacter(carmen);
      await c.startNewChat();

      expect(
        c.realismEnabled,
        isFalse,
        reason: 'Porch Life Realism default is off and the card did not ask',
      );
      expect(c.needsSimEnabled, isTrue);
      expect(
        c.needsSimulation.vector,
        isNotEmpty,
        reason:
            'Needs is its own switch — a brand-new chat must seed '
            'bars even when the Realism header stays off',
      );
      expect(sidebarWouldShowBars(), isTrue);
    },
  );
}
