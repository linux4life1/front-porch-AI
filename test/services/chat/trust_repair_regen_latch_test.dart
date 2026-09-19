// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// pendingTrustRepair lives on RelationshipService and is consumed on the
// next user turn. Regen reverts trust but used to leave the latch false, so
// the repair judges did not run. The latch must ride realism_state the same
// way trust does, and 1:1 regen must share the dance's pre-gen judge
// dispatch so restored latches actually fire.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/fpchat_format.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/services.dart';

import 'relationship_service_test.dart' show createTestRelationship;

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_trust_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('restoreFromMessageState puts the repair latch back', () {
    final svc = createTestRelationship();
    svc.applyTrustDelta(-25);
    expect(svc.pendingTrustRepair, isTrue);
    final trust = svc.trustLevel;
    final snap = <String, dynamic>{
      'pendingTrustRepair': true,
      'trustLevel': trust,
    };

    svc.consumePendingTrustRepair();
    expect(svc.pendingTrustRepair, isFalse);

    svc.restoreFromMessageState(snap);
    expect(
      svc.pendingTrustRepair,
      isTrue,
      reason: 'regen of the repair turn must re-arm from the drop snapshot',
    );
    expect(svc.trustLevel, trust);
  });

  test('absent latch key does not clobber a live window', () {
    final svc = createTestRelationship();
    svc.applyTrustDelta(-25);
    expect(svc.pendingTrustRepair, isTrue);
    svc.restoreFromMessageState({'trustLevel': svc.trustLevel});
    expect(
      svc.pendingTrustRepair,
      isTrue,
      reason: 'old messages without the key must not wipe a live latch',
    );
  });

  test('false on the snapshot clears a consumed-then-rewound latch', () {
    final svc = createTestRelationship();
    svc.applyTrustDelta(-25);
    svc.restoreFromMessageState({'pendingTrustRepair': false});
    expect(svc.pendingTrustRepair, isFalse);
  });

  test('live capture stamps pendingTrustRepair onto realism_state', () async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
    });
    final db = AppDatabase.forTesting();
    final storage = StorageService();
    final personas = UserPersonaService(db);
    final chat = ChatService(
      KoboldService(storage),
      personas,
      storage,
      WorldRepository(storage, db),
    )..setDatabase(db);
    addTearDown(() async {
      chat.dispose();
      await db.close();
    });
    await storage.initialized;
    await chat.startFreshChatWith(
      character: CharacterCard(
        name: 'Misty',
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
      )..dbId = 'char-trust-latch',
      personaId: personas.persona.id,
    );

    chat.relationshipService.applyTrustDelta(-25);
    final captured = chat.debugCaptureRealismStateForFpchat();
    expect(
      captured['pendingTrustRepair'],
      isTrue,
      reason:
          'the drop turn\'s snapshot is what regen of the next reply rewinds to',
    );
    expect(kFpchatRealismStateCoreKeys.contains('pendingTrustRepair'), isTrue);
  });

  test('1:1 regen and the group dance share pre-gen judge dispatch', () {
    final dance = File(
      'lib/services/chat/chat_service_realism_dance.dart',
    ).readAsStringSync();
    final regen = File(
      'lib/services/chat/chat_service_reprocess.dart',
    ).readAsStringSync();
    final evals = File(
      'lib/services/chat/chat_service_realism_evals.dart',
    ).readAsStringSync();
    expect(
      evals.contains('_runPreGenRealismJudges'),
      isTrue,
      reason: 'one helper so 1:1 regen cannot skip the repair branch',
    );
    expect(dance.contains('_runPreGenRealismJudges'), isTrue);
    expect(regen.contains('_runPreGenRealismJudges'), isTrue);
    expect(
      evals.contains('pendingTrustRepair'),
      isTrue,
      reason: 'the helper must still consult the latch',
    );
  });
}
