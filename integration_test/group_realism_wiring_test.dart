// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: the group realism WIRING — every field the impersonation dance writes
// must reach the persisted map, keyed to the right member, and survive the
// round trip back into a prompt.
//
// WHY THIS EXISTS. The realism-audit's Phase 2 pinned the speaker-resolution
// RULE but recorded, in as many words, that it did not pin the WIRING — "that
// needs a live ChatService with a seeded group". This is that test, and it is
// the explicit precondition for U7 (retyping the untyped `_groupRealism` map):
// U7 must keep every assertion here green while changing the type under it.
//
// group_smoke_test.dart already guards ISOLATION and bond/needs PERSISTENCE.
// This file guards COMPLETENESS, at the layer U7 will rewrite:
//
//   1. After real scored turns, the sessions row's group_realism_state JSON
//      must contain the full key inventory the save writers produce, per
//      member, with the right runtime types. A field the dance drops — or
//      that a retype forgets to serialize — fails HERE, by name.
//   2. The values in that JSON must agree with the public per-member getters
//      (same numbers the sidebar shows), proving column and map are one
//      state, not two.
//   3. What was saved must come back as PROMPT TEXT: after a reload wipes all
//      in-memory state, the next outbound generation prompt must carry the
//      scored member's emotion and posture — map → load → injection, the
//      whole dance, observed from outside the process boundary.
//
// Boot/sandbox contract is identical to app_smoke_test.dart; see its header.

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
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kReplyPieces = ['Wired for sound, ', 'both of us.'];

/// Every key the save writers put into a member's slot unconditionally once a
/// turn has been scored. Sources, so a future rename knows where to look:
/// RelationshipService.saveRelationshipScalarsToGroup (8 scalars + 2 counters),
/// applyShortTermDecay ('turnsSinceDecayCheck'), NsfwService
/// .saveNsfwScalarsToGroup (5, note the historical 'arousal' key; since
/// 2026-10-06 the refractory is three minute keys, not two turn keys),
/// _saveScalarsIntoGroupRealism (emotion pair + 'needs'), and
/// ensureInterCharacterRelationshipsSeeded ('relationships').
const _requiredMemberKeys = {
  'affection',
  'longTermScore',
  'trust',
  'fixation',
  'fixationLifespan',
  'spatialStance',
  'relationshipTier',
  'longTermTier',
  'turnsSinceLongTermCheck',
  'shortTermDeltasSummary',
  'turnsSinceDecayCheck',
  'arousal',
  'nsfwCooldownEnabled',
  'refractoryMinutesRemaining',
  'refractoryMinutesTotal',
  'refractoryOpened',
  'emotion',
  'emotionIntensity',
  'needs',
  'relationships',
};

CharacterCard _member(String name) => CharacterCard(
  name: name,
  description: '$name exists only inside the wiring E2E.',
  firstMessage: '$name takes a seat.',
  frontPorchExtensions: FrontPorchExtensions(
    realismEnabled: true,
    needsSimEnabled: true,
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('group realism wiring: full field set persists and re-injects', (
    tester,
  ) async {
    try {
      final probe = await Socket.connect(
        InternetAddress.loopbackIPv4,
        5001,
        timeout: const Duration(milliseconds: 500),
      );
      probe.destroy();
      fail('Something is listening on 127.0.0.1:5001 — close it first.');
    } on SocketException {
      // Safe.
    }

    final sandbox = Directory.systemTemp.createTempSync('fpai_wiring_');
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

    // ── Seed a two-member group exactly the way group_smoke does ────────
    final groupId = 'group_e2e_wiring';
    final cast = [_member('Ada'), _member('Bex')];
    final blobs = buildGroupRealismBlobs(
      seeds: {
        for (var i = 0; i < cast.length; i++)
          'member_$i': defaultGroupMemberRealismSeed(),
      },
      needsEnabled: true,
      timeOfDay: 'morning',
      dayCount: 1,
    );
    // Members are resolved with an imagePath ONLY when their avatar file
    // exists on disk, and the runtime member id IS that filename's basename
    // (stableGroupId). Without it the id falls back to the display name and
    // the id-keyed seeds are never read — so seed real avatar files, exactly
    // like the wizard does.
    final storage = Provider.of<StorageService>(ctx, listen: false);
    final avatarsDir = Directory('${storage.groupsDir.path}/$groupId/avatars')
      ..createSync(recursive: true);
    final onePixelPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQ'
      'DwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    for (var i = 0; i < cast.length; i++) {
      File('${avatarsDir.path}/member_$i.png').writeAsBytesSync(onePixelPng);
    }

    await groupRepo.save(
      GroupChat(
        id: groupId,
        name: 'Wiring Duet',
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
          avatarFilename: Value('member_$i.png'),
          frontPorchExtensions: Value(
            jsonEncode(c.frontPorchExtensions!.toJson()),
          ),
        ),
      );
    }
    await groupRepo.reload();
    final group = groupRepo.groups.firstWhere((g) => g.id == groupId);
    await chatService.setActiveGroup(group, groupRepo: groupRepo);

    // ignore: use_build_context_synchronously — ctx is the root element.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));

    final d = ChatDriver(tester, chatService, backend);
    await d.waitForWidget(d.input);
    await d.waitFor(
      () => chatService.groupCharacters.length == 2,
      () => 'both members to load',
    );
    final ada = chatService.groupCharacters.firstWhere((c) => c.name == 'Ada');
    final bex = chatService.groupCharacters.firstWhere((c) => c.name == 'Bex');

    // ── Three scored round-robin turns so BOTH members get evaluated ────
    // (Evals are pre-generation: turn N scores exchange N-1 for speaker N.)
    for (var turn = 1; turn <= 3; turn++) {
      await d.sendMessage('Porch check-in number $turn, both of you.');
      await d.waitFor(
        () => backend.chatRequests >= turn,
        () => 'group turn $turn (chat=${backend.chatRequests})',
        timeout: const Duration(seconds: 120),
      );
      await d.waitSendable();
    }

    // ── 1. The persisted JSON carries the full inventory, per member ────
    final sessionId = chatService.currentSessionId;
    expect(sessionId, isNotNull);
    Future<Map<String, dynamic>> readColumn() async {
      final row = await (db.select(
        db.sessions,
      )..where((s) => s.id.equals(sessionId!))).getSingle();
      final wrapper = jsonDecode(row.groupRealismState) as Map<String, dynamic>;
      // The column is a wrapper; member slots live under perChar. The other
      // wrapper keys (decay rates, author notes, objectives, sceneGuests,
      // savedAt) are out of scope here.
      return (wrapper['perChar'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
    }

    // The turn's post-generation bookkeeping persists asynchronously; poll
    // until both members' slots are scored rather than racing it (the exact
    // sampling-too-early trap the Windows group_smoke flake fell into).
    late Map<String, dynamic> persisted;
    for (var attempt = 0; attempt < 40; attempt++) {
      persisted = await readColumn();
      final scored = ['member_0', 'member_1']
          .map((m) => persisted[m])
          .whereType<Map>()
          .where((m) => ((m['emotion'] as String?) ?? '').isNotEmpty)
          .length;
      if (scored == 2) break;
      await tester.pump(const Duration(milliseconds: 500));
    }

    debugPrint('[wiring] column top-level keys: ${persisted.keys.toList()}');
    for (final e in persisted.entries) {
      if (e.value is Map) {
        debugPrint(
          '[wiring] ${e.key}: ${((e.value as Map).keys.toList()..sort()).join(',')}',
        );
      } else {
        debugPrint('[wiring] ${e.key}: ${e.value.runtimeType} = ${e.value}');
      }
    }
    for (final memberId in ['member_0', 'member_1']) {
      final slot = persisted[memberId];
      expect(
        slot,
        isA<Map<String, dynamic>>(),
        reason: '$memberId has no slot in group_realism_state at all',
      );
      final map = slot as Map<String, dynamic>;
      final missing = _requiredMemberKeys.difference(map.keys.toSet());
      expect(
        missing,
        isEmpty,
        reason:
            '$memberId is missing ${missing.join(', ')} from the persisted '
            'map. Either a save writer stopped writing it, or — if this is '
            'the U7 branch — the typed class forgot to serialize it. Keys '
            'present: ${(map.keys.toList()..sort()).join(', ')}',
      );
      // Types, for the keys a retype is most likely to mangle.
      expect(map['affection'], isA<num>(), reason: '$memberId affection');
      expect(map['trust'], isA<num>(), reason: '$memberId trust');
      expect(
        map['emotion'],
        'happy',
        reason: '$memberId emotion must be the canned eval value',
      );
      expect(map['emotionIntensity'], 'moderate', reason: memberId);
      expect(
        map['spatialStance'],
        'standing',
        reason: '$memberId posture must be the canned eval value',
      );
      expect(map['needs'], isA<Map<String, dynamic>>(), reason: memberId);
      expect(
        map['relationships'],
        isA<Map<String, dynamic>>(),
        reason:
            '$memberId inter-character map must be seeded (2 members '
            '<= the 4-cap)',
      );
      expect(
        (map['relationships'] as Map).containsKey(memberId),
        isFalse,
        reason: '$memberId must not have feelings about ITSELF',
      );
    }

    // ── 2. Column and public getters agree — one state, not two ─────────
    final m0 = persisted['member_0'] as Map<String, dynamic>;
    final m1 = persisted['member_1'] as Map<String, dynamic>;
    expect(
      chatService.getAffectionForGroupCharacter(ada),
      (m0['affection'] as num).toInt(),
      reason: 'Ada\'s sidebar bond and her persisted slot disagree',
    );
    expect(
      chatService.getAffectionForGroupCharacter(bex),
      (m1['affection'] as num).toInt(),
      reason: 'Bex\'s sidebar bond and her persisted slot disagree',
    );

    // ── 3. Reload from disk, then the next prompt must carry the state ──
    await chatService.loadSession(sessionId!);
    await d.waitFor(
      () => chatService.groupCharacters.length == 2,
      () => 'the group to come back after reload',
    );
    // Drive up to two post-reload turns and require the state markers in an
    // outbound prompt. Two, because the first CI runs (linux + macos) showed a
    // single-prompt observation is racy on slow runners: the round-robin
    // pointer, the settle timing and the body-capture order can all shift
    // WHICH prompt first carries the injection. The property under test —
    // load → injection wiring — is proven by ANY post-reload prompt carrying
    // the stored state; sampling two turns removes the race without weakening
    // what is asserted. (Persistence itself is already proven above by the
    // column inventory + getter agreement, which passed on those same CI
    // runs.)
    var sawEmotion = false;
    var sawPosture = false;
    for (
      var attempt = 1;
      attempt <= 2 && !(sawEmotion && sawPosture);
      attempt++
    ) {
      final beforeChat = backend.chatRequests;
      await d.sendMessage('Post-reload check line $attempt.');
      await d.waitFor(
        () => backend.chatRequests > beforeChat,
        () => 'post-reload turn $attempt',
        timeout: const Duration(seconds: 120),
      );
      await d.waitSendable();
      final prompt = backend.lastChatBody;
      sawEmotion = sawEmotion || prompt.contains('happy');
      sawPosture = sawPosture || prompt.contains('standing');
      debugPrint(
        '[wiring] post-reload turn $attempt: emotion=$sawEmotion '
        'posture=$sawPosture',
      );
    }
    expect(
      sawEmotion,
      isTrue,
      reason:
          'after a reload, no outbound prompt carried the stored emotion '
          'across two turns — map → load → injection broke somewhere',
    );
    expect(
      sawPosture,
      isTrue,
      reason:
          'after a reload, no outbound prompt carried the stored posture '
          'across two turns',
    );
  });
}
