// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E smoke test for GROUP chat — the half app_smoke_test.dart never touched.
//
// Why this file exists: CLAUDE.md calls 1:1-vs-group Realism/Needs parity the
// project's most safety-critical invariant, and until now it had zero
// integration coverage. Every group bug had to be caught by a human noticing
// that a character's bond looked wrong. That does not scale past one pair of
// eyes, and the orchestration it guards is genuinely hairy: sending a message
// in a group runs a per-speaker impersonation dance
//
//     prePostActiveChar = _activeCharacter;
//     _activeCharacter  = speakingCharacter;
//     _loadGroupRealismIntoScalars(sid);      // map  -> scalars
//     ...evals mutate the scalars...
//     _saveScalarsIntoGroupRealism(sid);      // scalars -> map
//
// where a single wrong `sid` silently credits the WRONG member and a missing
// save silently drops the turn. Both failures are invisible in the UI until
// someone reads a bond number and thinks "that's not right."
//
// The assertions below are deliberately about ISOLATION and PERSISTENCE rather
// than exact eval values: that a speaker's deltas land in that speaker's slot,
// that a silent member is untouched, and that both survive a reload. Those are
// the properties the impersonation dance can actually break.
//
// Boot/sandbox/isolation contract is identical to app_smoke_test.dart — see
// that file's header for why each seam exists. Do not weaken them here either.

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

const _kReplyPieces = ['Two voices on the porch ', 'answering in turn.'];

/// A member card that carries realism + needs, since the seeding only runs for
/// cards that actually have a FrontPorchExtensions block.
CharacterCard _member(String name) => CharacterCard(
  name: name,
  description: '$name exists only inside the group E2E smoke test.',
  firstMessage: '$name settles onto the porch.',
  frontPorchExtensions: FrontPorchExtensions(
    realismEnabled: true,
    needsSimEnabled: true,
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('group chat: per-speaker realism isolation + persistence', (
    tester,
  ) async {
    // Same pre-flight as the 1:1 suite: never risk the operator's real
    // KoboldCpp, whose zombie cleanup pkills servers it did not spawn.
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
      // Nothing there — safe.
    }

    final sandbox = Directory.systemTemp.createTempSync('fpai_group_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'realism_default': true,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
    });

    // ── Boot ────────────────────────────────────────────────────────────
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

    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains(
        'unexpectedly has a HitTestResult',
      )) {
        return;
      }
      (previousOnError ?? FlutterError.presentError)(details);
    };

    final ctx = tester.element(find.byType(MainLayout));
    final db = Provider.of<AppDatabase>(ctx, listen: false);
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    final storage = Provider.of<StorageService>(ctx, listen: false);
    final groupRepo = Provider.of<GroupChatRepository>(ctx, listen: false);

    // ── Build a two-member cast the way the wizard does ─────────────────
    // Membership lives exclusively in group_members (UUID keys); the group row
    // itself carries no character ids.
    final groupId = 'group_e2e_smoke';
    final cast = [_member('Ada'), _member('Bex')];

    // Realism/needs for a GROUP is switched on by the group DEFINITION, not by
    // the member cards: setActiveGroup only promotes the master flag when
    // defaultMemberRealismState seeds a non-empty _groupRealism ("the creator
    // expresses realism-on by writing defaultMemberRealismState"). A group
    // saved with the default '{}' silently runs with realism off no matter
    // what the member extensions or realism_default say — which is exactly
    // what this test hit on its first run. Build the blobs through the same
    // helper the creation wizard uses so the seed can never drift from the
    // real path. Keys are the RUNTIME member ids, which is what
    // _getCharacterIdFromCard resolves to (avatarFilename '<mid>.png').
    final blobs = buildGroupRealismBlobs(
      seeds: {
        for (var i = 0; i < cast.length; i++)
          'member_$i': defaultGroupMemberRealismSeed(),
      },
      needsEnabled: true,
      timeOfDay: 'morning',
      dayCount: 1,
    );
    // Runtime member id is the avatar filename basename (stableGroupId).
    // Without a real file the id falls back to the display name and the
    // id-keyed seeds are never read — Ada's needs vector stays {}.
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
        name: 'Porch Duet',
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

    // ignore: use_build_context_synchronously — ctx is the root MainLayout element.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));

    final d = ChatDriver(tester, chatService, backend);
    await d.waitForWidget(d.input);
    await d.waitFor(
      () => chatService.groupCharacters.length == 2,
      () =>
          'both members to load into the group '
          '(${chatService.groupCharacters.map((c) => c.name).toList()})',
    );

    final ada = chatService.groupCharacters.firstWhere((c) => c.name == 'Ada');
    final bex = chatService.groupCharacters.firstWhere((c) => c.name == 'Bex');

    // ── Turn 1: exactly one member speaks ───────────────────────────────
    await d.sendMessage('Hello you two, how is the porch this evening?');
    await d.waitFor(
      () => backend.chatRequests >= 1,
      () => 'the first group turn to generate (chat=${backend.chatRequests})',
      timeout: const Duration(seconds: 120),
    );
    await d.waitForWidget(
      find.textContaining(_kReplyPieces.join(), findRichText: true),
    );

    // ── Turn 2: realism evals are PRE-GEN, so a second turn is what scores
    //    the first one and writes per-speaker deltas into _groupRealism.
    await d.sendMessage('And what does the other one think?');
    await d.waitFor(
      () => backend.chatRequests >= 2,
      () =>
          'the second group turn to generate '
          '(chat=${backend.chatRequests}, eval=${backend.evalRequests})',
      timeout: const Duration(seconds: 120),
    );

    // ── The isolation assertion ─────────────────────────────────────────
    // The canned relationship eval pays +13 bond to whoever is being scored.
    // Whichever member actually spoke must own that delta in THEIR slot. A
    // wrong `sid` in the impersonation dance shows up here as both members
    // moving together, or as the wrong one moving.
    await d.waitFor(
      () =>
          chatService.getAffectionForGroupCharacter(ada) != 0 ||
          chatService.getAffectionForGroupCharacter(bex) != 0,
      () =>
          'per-speaker bond to land in _groupRealism '
          '(Ada=${chatService.getAffectionForGroupCharacter(ada)}, '
          'Bex=${chatService.getAffectionForGroupCharacter(bex)})',
    );

    // After two round-robin turns each member has spoken once and earned the
    // same canned +13, so equal values here prove nothing either way. The
    // discriminating test is a THIRD turn: round-robin scores exactly one
    // member again, so exactly ONE bond may move. If the per-member map were
    // really one shared scalar read twice — the failure mode the whole
    // impersonation dance risks — both would move together.
    final adaBefore = chatService.getAffectionForGroupCharacter(ada);
    final bexBefore = chatService.getAffectionForGroupCharacter(bex);

    await d.sendMessage('One more thought before the light goes.');
    await d.waitFor(
      () => backend.chatRequests >= 3,
      () => 'the third group turn (chat=${backend.chatRequests})',
      timeout: const Duration(seconds: 120),
    );
    await d.waitFor(
      () =>
          chatService.getAffectionForGroupCharacter(ada) != adaBefore ||
          chatService.getAffectionForGroupCharacter(bex) != bexBefore,
      () =>
          'the third turn to score somebody '
          '(Ada $adaBefore->${chatService.getAffectionForGroupCharacter(ada)}, '
          'Bex $bexBefore->${chatService.getAffectionForGroupCharacter(bex)})',
    );

    // The bond moves in memory during turn 3's PRE-GEN eval, long before the
    // turn is over: generation, the post-gen checks, and the settling section
    // — which is what PERSISTS _groupRealism to the DB — are all still
    // running at this point. Capturing and reloading without this barrier
    // raced that persist, and on slower Windows runners the reload read the
    // previous turn's numbers (the "expected 26, got 13" CI flake that fired
    // on two consecutive days, including on a docs-only commit). waitSendable
    // insists the whole turn — isSettlingTurn included — is finished before
    // any state below is trusted.
    await d.waitSendable();

    final adaBond = chatService.getAffectionForGroupCharacter(ada);
    final bexBond = chatService.getAffectionForGroupCharacter(bex);
    final adaMoved = adaBond != adaBefore;
    final bexMoved = bexBond != bexBefore;

    expect(
      adaMoved && bexMoved,
      isFalse,
      reason:
          'only the member who spoke may be scored, but BOTH moved on one '
          'turn (Ada $adaBefore->$adaBond, Bex $bexBefore->$bexBond) — that '
          'is per-member realism bleeding through a shared scalar',
    );
    expect(
      adaBond,
      isNot(bexBond),
      reason:
          'after an odd number of scored turns the two members must hold '
          'different bond values (Ada=$adaBond Bex=$bexBond); identical '
          'values mean both slots are backed by the same storage',
    );

    final adaTrust = chatService.getTrustForGroupCharacter(ada);
    final bexTrust = chatService.getTrustForGroupCharacter(bex);

    // Needs are per-member too, and every member must have a live vector
    // (decay ticks for the whole cast, not just the speaker).
    for (final c in [ada, bex]) {
      final needs = chatService.getNeedsForGroupCharacter(c);
      expect(
        needs,
        isNotEmpty,
        reason: '${c.name} must have a live needs vector in the group',
      );
      for (final entry in needs.entries) {
        expect(
          entry.value,
          inInclusiveRange(0, 100),
          reason: '${c.name} needs "${entry.key}" out of range',
        );
      }
    }

    // THE BARRIER (added 2026-08-03, maintainer-approved): the turn is not
    // over when the bond moves in memory. The pre-generation eval moves the
    // scalar and fires a fire-and-forget save; the AWAITED save runs at the
    // end of the turn's post-generation bookkeeping. Reloading before that
    // settles reads the previous save — which is exactly what happened on the
    // Windows CI runner ("Ada's bond must survive a group session reload:
    // Expected 26, Actual 13" — one turn's worth, half the total): fast Macs
    // won the race, slow runners lost it. waitSendable() blocks on
    // !isSettlingTurn, the same barrier realism_off_test documents, so the
    // reload below samples a genuinely finished turn instead of racing the
    // very persistence it exists to prove. Tightens the test; changes no
    // assertion.
    await d.waitSendable();

    // ── Persistence: the group map must reach SQLite ─────────────────────
    // _saveScalarsIntoGroupRealism is the critical persist; if it is skipped
    // on any path the numbers look right in memory and vanish on reload.
    final sessionId = chatService.currentSessionId;
    expect(sessionId, isNotNull);
    await chatService.loadSession(sessionId!);
    await d.waitFor(
      () => chatService.groupCharacters.length == 2,
      () => 'the group to come back after a reload',
    );

    final adaAfter = chatService.groupCharacters.firstWhere(
      (c) => c.name == 'Ada',
    );
    final bexAfter = chatService.groupCharacters.firstWhere(
      (c) => c.name == 'Bex',
    );
    expect(
      chatService.getAffectionForGroupCharacter(adaAfter),
      adaBond,
      reason: 'Ada\'s bond must survive a group session reload',
    );
    expect(
      chatService.getAffectionForGroupCharacter(bexAfter),
      bexBond,
      reason: 'Bex\'s bond must survive a group session reload',
    );
    expect(chatService.getTrustForGroupCharacter(adaAfter), adaTrust);
    expect(chatService.getTrustForGroupCharacter(bexAfter), bexTrust);

    // Any endpoint the fake does not model would have 404'd and skewed
    // behaviour silently.
    expect(backend.unexpectedPaths, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    await backend.close();
    try {
      sandbox.deleteSync(recursive: true);
    } on FileSystemException {
      // A straggler may still be writing; not a failure.
    }
  });
}
