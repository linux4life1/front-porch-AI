// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Needs catastrophe is armed on decay and consumed only when the generation
// plan is built. Cancel / stop before that consume used to leave
// `_pendingCatastrophe` armed, so the next speaker inherited a body-failure
// beat that was never theirs. 1:1 evals run before `_isGenerating`; group
// dance arms it inside `_generateResponse`. Every abort-before-consume path
// must discard it.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import 'needs_simulation_test.dart' show createTestSim;

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_catas_').path;
        }
        return null;
      });
}

Map<String, int> get _bottomHunger => {
  'hunger': 0,
  'bladder': 60,
  'energy': 60,
  'social': 60,
  'fun': 60,
  'hygiene': 60,
  'comfort': 60,
};

String _methodBody(String src, String signature, String nextSignature) {
  final start = src.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $signature');
  final end = src.indexOf(nextSignature, start + signature.length);
  expect(
    end,
    greaterThan(start),
    reason: 'missing $nextSignature after $signature',
  );
  return src.substring(start, end);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('stopGeneration discards a pending catastrophe even when idle', () {
    final src = File(
      'lib/services/chat/chat_service_message_ops.dart',
    ).readAsStringSync();
    final body = _methodBody(
      src,
      'void stopGeneration() {',
      'Future<void> _cancelAndWaitForGeneration()',
    );
    expect(
      body.contains('consumePendingCatastrophe'),
      isTrue,
      reason:
          'Stop before plan must drop the armed beat so the next speaker '
          'cannot inherit it',
    );
  });

  test('cancelRealismEval discards a pending catastrophe', () {
    final src = File(
      'lib/services/chat/chat_service_message_ops.dart',
    ).readAsStringSync();
    final start = src.indexOf('Future<void> cancelRealismEval()');
    expect(start, greaterThanOrEqualTo(0));
    expect(
      src.substring(start).contains('consumePendingCatastrophe'),
      isTrue,
      reason:
          '1:1 evals run before _isGenerating; cancel during evals is the '
          'abort-before-consume path',
    );
  });

  test('_cancelAndWaitForGeneration discards a pending catastrophe', () {
    final src = File(
      'lib/services/chat/chat_service_message_ops.dart',
    ).readAsStringSync();
    final body = _methodBody(
      src,
      'Future<void> _cancelAndWaitForGeneration() async {',
      'void _rewindPocketsForDeletedMessage(',
    );
    expect(
      body.contains('consumePendingCatastrophe'),
      isTrue,
      reason: 'regen/delete abort of an in-flight turn must not leak the beat',
    );
  });

  test('1:1 send cancel before generate discards catastrophe', () {
    final src = File(
      'lib/services/chat/chat_service_send_handoff.dart',
    ).readAsStringSync();
    final start = src.indexOf('if (_realismEvalCancelled)');
    expect(start, greaterThanOrEqualTo(0));
    final ret = src.indexOf('return;', start);
    expect(
      src.substring(start, ret).contains('consumePendingCatastrophe'),
      isTrue,
      reason: '1:1 send aborts after evals, before plan consume',
    );
  });

  test('group generate cancel before plan discards catastrophe', () {
    final src = File(
      'lib/services/chat/chat_service_generation.dart',
    ).readAsStringSync();
    final dance = src.indexOf('await _evaluateRealismForUpcomingSpeaker');
    expect(dance, greaterThanOrEqualTo(0));
    final cancelled = src.indexOf('if (_realismEvalCancelled)', dance);
    final ret = src.indexOf('return;', cancelled);
    expect(
      src.substring(cancelled, ret).contains('consumePendingCatastrophe'),
      isTrue,
      reason:
          'group dance arms the beat; cancel before plan is the inherit bug',
    );
  });

  test('ChatService.stopGeneration clears an armed catastrophe', () async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
    });
    final db = AppDatabase.forTesting();
    final storage = StorageService();
    final chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage));
    addTearDown(() async {
      chat.dispose();
      await db.close();
    });
    await storage.initialized;
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Mara',
        description: 'Catastrophe cancel fixture.',
        firstMessage: 'Hi.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
        ),
      )..dbId = 'char-catas-1',
    );
    chat.setRealismEnabled(true);
    await chat.setNeedsSimEnabled(true);
    chat.needsSimulation.restoreFromSnapshot({'vector': _bottomHunger});
    chat.needsSimulation.applyCatastropheIfNeeded();
    expect(
      chat.needsSimulation.pendingCatastrophe,
      isNotNull,
      reason: 'precondition: hunger 0 must arm a beat',
    );

    chat.stopGeneration();

    expect(
      chat.needsSimulation.pendingCatastrophe,
      isNull,
      reason: 'the next speaker must not inherit a cancelled beat',
    );
  });

  test('createTestSim consume still clears (sanity of the sim API)', () {
    final sim = createTestSim();
    sim.initializeFresh();
    sim.restoreFromSnapshot({'vector': _bottomHunger});
    sim.applyCatastropheIfNeeded();
    expect(sim.pendingCatastrophe, isNotNull);
    sim.consumePendingCatastrophe();
    expect(sim.pendingCatastrophe, isNull);
  });
}
