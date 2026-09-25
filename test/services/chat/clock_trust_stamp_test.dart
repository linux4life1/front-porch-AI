// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Clock stamp must never pin Realism trust. Public ChatService API
// only so this file compiles on 35acecc6 / 97a8d165.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_clk_trust_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  String nextReply = '*Nia leans on the rail.*';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield nextReply;
      return;
    }
    final p = params.prompt;
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":1,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
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
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedTrustStamp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('clock stamp never pins trust', () {
    AppDatabase? db;
    StorageService? storage;
    CharacterRepository? repo;
    ChatService? chat;
    late _ScriptedLlm llm;

    Future<void> drain() async {
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

    Future<void> boot() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': true,
        'needs_sim_default': true,
        'passage_of_time_default': true,
      });
      db = AppDatabase.forTesting();
      storage = StorageService();
      repo = CharacterRepository(db!, storage!);
      llm = _ScriptedLlm();
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
      final nia = CharacterCard(
        name: 'Nia',
        firstMessage: 'Evening.',
        imagePath: '/tmp/nia-trust-stamp.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
          passageOfTimeEnabled: true,
        ),
      );
      await repo!.addCharacter(nia);
      await chat!.setActiveCharacter(nia);
      await chat!.setRealismEnabled(true);
      await drain();
    }

    void pinTrust(int n) {
      final rel = chat!.relationshipService;
      rel.loadScalars(
        affectionScore: rel.affectionScore,
        longTermScore: rel.longTermScore,
        trustLevel: n,
      );
      for (final m in chat!.messages) {
        if (m.isUser || m.sender == 'System') continue;
        final slot = m.activeMetadata ?? <String, dynamic>{};
        m.activeMetadata ??= slot;
        final raw = slot['realism_state'];
        final rs = raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
        rs['trustLevel'] = n;
        slot['realism_state'] = rs;
        m.metadata ??= slot;
        final metaRs = m.metadata!['realism_state'];
        if (metaRs is Map) {
          metaRs['trustLevel'] = n;
        } else {
          m.metadata!['realism_state'] = Map<String, dynamic>.from(rs);
        }
      }
    }

    int? snapTrust(ChatMessage m) {
      final rs = m.activeMetadata?['realism_state'];
      if (rs is! Map) return null;
      final v = rs['trustLevel'];
      return v is num ? v.toInt() : null;
    }

    tearDown(() async {
      chat?.dispose();
      await db?.close();
    });

    test(
      'trust_delta moves trust off 12 and survives stamp, reload, regen, swipe',
      () async {
        await boot();
        expect(chat!.realismEnabled, isTrue);
        pinTrust(12);
        await chat!.flushPendingSaves();
        expect(
          chat!.relationshipService.trustLevel,
          12,
          reason: 'planted lived-in trust before the send',
        );

        await chat!.sendMessage('Hey.');
        await drain();

        final afterSend = chat!.relationshipService.trustLevel;
        expect(
          afterSend,
          isNot(12),
          reason:
              'Realism ON + trust_delta 1 must move trust off 12. '
              'Clock stamp must not write back the pre-eval snapshot.',
        );
        expect(afterSend, 13);

        final bot = chat!.messages.lastWhere((m) => !m.isUser);
        expect(
          snapTrust(bot),
          afterSend,
          reason: 'clock stamp must not replace realism_state trust',
        );
        expect(bot.activeMetadata?['story_clock_after'], isNotNull);
        expect(
          bot.metadata?['story_clock_after'],
          isNotNull,
          reason:
              'clock writer must mutate the attached slot. Map.from + '
              'activeMetadata= leaves legacy metadata without after, '
              'so a later restore can pin pre-eval trust.',
        );
        final metaRs = bot.metadata?['realism_state'];
        expect(
          metaRs is Map ? (metaRs['trustLevel'] as num?)?.toInt() : null,
          afterSend,
          reason: 'legacy metadata must keep post-eval trust, not 12',
        );

        await chat!.flushPendingSaves();
        await chat!.reloadCurrentSession();
        await drain();
        expect(
          chat!.relationshipService.trustLevel,
          afterSend,
          reason: 'reloaded live trust must stay off 12',
        );

        llm.nextReply = '*Nia stays on the rail.*';
        await chat!.regenerateLastMessage();
        await drain();
        expect(
          chat!.relationshipService.trustLevel,
          afterSend,
          reason: 'regen re-applies the same delta from the planted 12',
        );

        final idx = chat!.messages.lastIndexWhere((m) => !m.isUser);
        await chat!.selectSwipe(idx, 0);
        expect(
          chat!.relationshipService.trustLevel,
          afterSend,
          reason: 'swipe back must restore the stamped swipe, not trust 12',
        );
      },
    );
  });
}
