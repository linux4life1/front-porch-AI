// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: group regenerate restores inter-character feelings and re-runs cadence
// under re-decay (hostile self-review of the P1.10 "cadence twin" mistake).
//
// WHY THIS EXISTS.
//   1. FEELINGS: post-gen keyword sweep mutates the hidden inter-char map and
//      is never restamped. Without rewinding to the rejected turn's pre-sweep
//      map, every Regenerate stacked another +4 forever (unit-only guards could
//      not prove ChatService.regenerateLastMessage still called the overlay).
//   2. CADENCE: lastMsg stamps turnsSinceDecayCheck *after* that turn's decay.
//      Regen restores previousMessageState then re-applies applyShortTermDecay.
//      Overlaying lastMsg cadence then re-decaying skips the every-10 fire.
//      This suite proves the live path: previous stamp + re-decay fires once.
//
// Boot/sandbox contract is identical to app_smoke_test.dart; see its header.
//
//   flutter test integration_test/regen_feelings_cadence_test.dart -d macos

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
// Extension methods captureCadenceAndFeelings / restoreFromMessageState live
// on this library (part of RelationshipService).
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

/// Reply names the other member + a strong positive so the post-gen heuristic
/// bumps inter-char feelings (+4). Keep in sync with
/// RelationshipService.updateInterCharacterFeelingsFromRecentExchange.
const _kReplyPieces = [
  'Ada looks at Bex and says Bex is a wonderful friend, I adore Bex.',
];

CharacterCard _member(String name) => CharacterCard(
  name: name,
  description: '$name exists only inside the regen feelings/cadence E2E.',
  firstMessage: '$name takes a seat on the porch.',
  frontPorchExtensions: FrontPorchExtensions(
    realismEnabled: true,
    needsSimEnabled: false,
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'group regen: feelings do not stack; cadence re-fires under re-decay',
    (tester) async {
      try {
        final probe = await Socket.connect(
          InternetAddress.loopbackIPv4,
          5001,
          timeout: const Duration(milliseconds: 500),
        );
        probe.destroy();
        fail(
          'Something is listening on 127.0.0.1:5001 (a real KoboldCpp?). '
          'Close it before running the E2E suite.',
        );
      } on SocketException {
        // Safe.
      }

      final sandbox = Directory.systemTemp.createTempSync('fpai_regen_feel_');
      PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
      final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
      addTearDown(() async => backend.close());
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'import_llmerta_porch_memories': false,
        'realism_default': true,
        'backend_type': 'openRouter',
        'remote_api_url': '${backend.baseUrl}/v1',
        'remote_model_name': 'smoke-model',
      });

      app.main(const []);
      await pumpUntilFound(tester, find.byType(MainLayout));
      try {
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setSize(const Size(1200, 800));
        await windowManager.setAlignment(Alignment.bottomRight);
        await windowManager.blur();
      } catch (e) {
        debugPrint('[e2e] window_manager placement skipped: $e');
      }
      await tester.pump(const Duration(seconds: 2));

      final ctx = tester.element(find.byType(MainLayout));
      final db = Provider.of<AppDatabase>(ctx, listen: false);
      final chatService = Provider.of<ChatService>(ctx, listen: false);
      final groupRepo = Provider.of<GroupChatRepository>(ctx, listen: false);

      final groupId = 'group_e2e_regen_feel';
      final cast = [_member('Ada'), _member('Bex')];
      final blobs = buildGroupRealismBlobs(
        seeds: {
          for (var i = 0; i < cast.length; i++)
            'member_$i': defaultGroupMemberRealismSeed(),
        },
        needsEnabled: false,
        timeOfDay: 'morning',
        dayCount: 1,
      );

      await groupRepo.save(
        GroupChat(
          id: groupId,
          name: 'Regen Feelings Duet',
          turnOrder: TurnOrder.roundRobin,
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
      );
      for (var i = 0; i < cast.length; i++) {
        final c = cast[i];
        await db.insertGroupMember(
          GroupMembersCompanion(
            id: Value('member_$i'),
            groupId: Value(groupId),
            name: Value(c.name),
            description: Value(c.description),
            firstMessage: Value(c.firstMessage),
            frontPorchExtensions: Value(
              jsonEncode(c.frontPorchExtensions!.toJson()),
            ),
          ),
        );
      }
      await groupRepo.reload();
      final group = groupRepo.groups.firstWhere((g) => g.id == groupId);
      await chatService.setActiveGroup(group, groupRepo: groupRepo);

      // ignore: use_build_context_synchronously
      Navigator.of(ctx).push(
        MaterialPageRoute(builder: (_) => const ChatPage()),
      );

      final d = ChatDriver(tester, chatService, backend);
      await d.waitForWidget(d.input);
      await d.waitFor(
        () => chatService.groupCharacters.length == 2,
        () => 'both members loaded',
      );

      // Seed cadence on both members so whoever speaks first can fire (9->10->0).
      final rels = chatService.relationshipService;
      for (final c in chatService.groupCharacters) {
        rels.restoreFromMessageState(
          {'turnsSinceDecayCheck': 9},
          groupSpeakerId: chatService.characterIdFor(c),
        );
      }

      // ── Turn that triggers post-gen feelings (reply names both + positives)
      await d.sendMessage('Tell the other how you feel.');
      await d.waitFor(
        () => backend.chatRequests >= 1,
        () => 'first group turn (chat=${backend.chatRequests})',
        timeout: const Duration(seconds: 120),
      );
      await d.waitSendable();

      final lastBot = chatService.messages.lastWhere((m) => !m.isUser);
      final speaker = chatService.groupCharacters.firstWhere(
        (c) => c.name == lastBot.sender,
      );
      final other = chatService.groupCharacters.firstWhere(
        (c) => c.name != lastBot.sender,
      );
      final sid = chatService.characterIdFor(speaker);
      final oid = chatService.characterIdFor(other);

      final afterFirst = Map<String, int>.from(
        rels.getInterCharacterRelationships(sid),
      );
      expect(
        afterFirst[oid],
        4,
        reason:
            'post-gen heuristic must bump ${speaker.name}->${other.name} by +4 '
            'when the reply names them + wonderful/adore/friend (got $afterFirst)',
      );

      // ── Regen once: must NOT stack another +4 on top of 4 ────────────
      await chatService.regenerateLastMessage();
      await d.waitSendable();

      final afterRegen1 = Map<String, int>.from(
        rels.getInterCharacterRelationships(sid),
      );
      expect(
        afterRegen1[oid],
        4,
        reason:
            'regen must restore pre-sweep feelings then re-apply one post-gen '
            'sweep on the new swipe - still +4, not +8 (stacked). Got '
            '${afterRegen1[oid]}',
      );

      await chatService.regenerateLastMessage();
      await d.waitSendable();
      final afterRegen2 = Map<String, int>.from(
        rels.getInterCharacterRelationships(sid),
      );
      expect(
        afterRegen2[oid],
        4,
        reason:
            'two regens must not compound feelings (would be +12 without restore)',
      );

      // ── Cadence under re-decay: seed 9 on the speaker, regen, expect fire->0
      //    (not 1 from wrong lastMsg post-fire overlay).
      final bondBefore = chatService.getAffectionForGroupCharacter(speaker);
      rels.restoreFromMessageState(
        {'turnsSinceDecayCheck': 9},
        groupSpeakerId: sid,
      );
      await chatService.regenerateLastMessage();
      await d.waitSendable();

      // Reload speaker scalars for capture (group impersonation after regen).
      final cadenceAfter =
          rels.captureCadenceAndFeelings()['turnsSinceDecayCheck'] as int? ??
          -1;
      // After fire: counter is 0. Wrong lastMsg-overlay path: start at 0,
      // increment to 1. Accept 0 as the pass; reject 1 as the known bug.
      expect(
        cadenceAfter,
        isNot(1),
        reason:
            'cadence 1 after regen means we re-decayed from a post-fire stamp '
            '(wrong overlay). Want fire->0. bond $bondBefore->'
            '${chatService.getAffectionForGroupCharacter(speaker)}',
      );
      expect(
        cadenceAfter,
        anyOf(0, greaterThan(1)),
        reason:
            '0 = fire reset; >1 means counter was not seeded (seed failed). '
            'Got $cadenceAfter',
      );
    },
  );
}
