// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The buried-host regen over the wire (drift ledger #15a): the chat snapshot
// carries `regenerableHostBelowGuests` (the desktop helper's index rule,
// null outside 1:1), and POST /api/chat/regenerate dispatches on `target`:
//   absent          → the normal last-reply regen (body contract unchanged)
//   mainCharacter   → ChatService.regenerateMainCharacter: the stale Scene
//                     Guest tail is popped, the host regrows as a new swipe,
//                     the chime gate re-runs
//   anything else   → 400, nothing runs — the two regens are not
//                     interchangeable, so a bad word must not quietly
//                     become the other action.
// The completion `chat_updated` (not just the immediate one) is what stops a
// quiet browser from keeping the popped guest rows.
// Real WebChatRoutes → ChatFacade → ChatService (pattern:
// test/services/web/placeholder_portrait_relay_test.dart).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/routes/chat_routes.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

import '../../helpers/reprocess_needs_harness.dart';
import '../../helpers/refractory_judges.dart';

class _RecordingHub extends StreamHub {
  _RecordingHub() : super(const Stream<String>.empty(), () => false);

  final pushed = <Map<String, dynamic>>[];

  @override
  void broadcast(Map<String, dynamic> event) => pushed.add(event);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  late _RecordingHub hub;
  late ChatFacade facade;
  late Router router;
  late CharacterCard host;
  late CharacterCard guest;

  Future<void> settle() async {
    await h.settleTurn();
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> waitIdle() async {
    for (
      var i = 0;
      i < 500 &&
          (h.chat.isGenerating || h.chat.isSettlingTurn || h.chat.isGuestBusy);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await settle();
  }

  setUp(() async {
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = previous);
    h = ReprocessHarness();
    await h.boot();
    h.chat.testLlmServiceOverride = RefractoryJudges();
    hub = _RecordingHub();
    facade = ChatFacade(h.chat, h.repo, null, hub, null);
    router = Router();
    WebChatRoutes(facade, router);
    host = CharacterCard(
      name: 'Flora',
      firstMessage: 'Evening.',
      imagePath: 'gm-flora.png',
    );
    guest = CharacterCard(
      name: 'Riley',
      firstMessage: 'Hi.',
      imagePath: 'gm-riley.png',
      frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
    );
    await h.repo.addCharacter(host);
    await h.repo.addCharacter(guest);
    await h.chat.setActiveCharacter(host);
    await settle();
    await h.chat.joinSceneGuest(guest);
    await settle();
  });

  tearDown(() => h.dispose());

  Future<shelf.Response> postRegenerate(Map<String, dynamic> body) =>
      router.call(
        shelf.Request(
          'POST',
          Uri.parse('http://localhost/api/chat/regenerate'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode(body),
        ),
      );

  int chatUpdates() => hub.pushed
      .where((e) => e['event'] == 'chat_updated' || e['type'] == 'chat_updated')
      .length;

  /// The fire-and-forget regen answers the HTTP call immediately; the state
  /// lands across a pre-busy gap the busy flags do not cover (the guest tail
  /// pops before the nested regen raises `isPostGenerating`, and the
  /// realism replay runs on real timers). The completion `whenComplete`
  /// notify is the honest finish line — the second `chat_updated`.
  Future<void> waitForRegenCompletion() async {
    for (var i = 0; i < 500 && chatUpdates() < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await settle();
    expect(
      chatUpdates(),
      greaterThanOrEqualTo(2),
      reason: 'the fire-and-forget regen never reached whenComplete',
    );
  }

  int? snapshotIndex() => facade.state()['regenerableHostBelowGuests'] as int?;

  int hostIndex() => h.chat.messages.lastIndexWhere((m) => m.sender == 'Flora');

  int guestsAfterHost() => h.chat.messages
      .skip(hostIndex() + 1)
      .where((m) => m.sender == 'Riley')
      .length;

  /// User line + host reply, then an explicit guest chime so the tail is
  /// deterministic: no mention of Riley, so the chime gate never adds one.
  Future<void> buryHost() async {
    await h.chat.sendMessage('How did the market go?');
    await waitIdle();
    if (h.chat.messages.last.sender != 'Riley') {
      await h.chat.speakGuestNow(
        h.chat.sceneGuestCards.firstWhere((c) => c.name == 'Riley'),
      );
      await waitIdle();
    }
  }

  test('the snapshot carries the buried host index, and null when the host '
      'speaks last', () async {
    await buryHost();
    expect(h.chat.messages.last.sender, 'Riley');
    final idx = hostIndex();
    expect(idx, greaterThanOrEqualTo(0));
    expect(snapshotIndex(), idx);

    // Drop the guest tail: the host is last, so the normal regen reaches it
    // and the buried-host offer must vanish.
    while (h.chat.messages.last.sender == 'Riley') {
      h.chat.deleteMessage(h.chat.messages.length - 1);
    }
    await settle();
    expect(snapshotIndex(), isNull);
  });

  test('target mainCharacter pops the guest tail and regrows the host as a '
      'new swipe', () async {
    await buryHost();
    final idx = hostIndex();
    final before = h.chat.messages.length;
    expect(h.chat.messages[idx].swipes.length, 1);
    expect(guestsAfterHost(), greaterThan(0));
    hub.pushed.clear();

    final res = await postRegenerate({'target': 'mainCharacter'});
    expect(res.statusCode, 200);
    await waitForRegenCompletion();

    expect(h.chat.messages[idx].sender, 'Flora');
    expect(
      h.chat.messages[idx].swipes.length,
      greaterThan(1),
      reason: 'the host reply came back as a new swipe, like the desktop',
    );
    expect(guestsAfterHost(), 0, reason: 'the stale guest tail was removed');
    expect(h.chat.messages.length, lessThan(before));
    // Both the immediate and the completion notify ride the hub: a browser
    // that missed the splice still learns the tail is gone.
    final updates = hub.pushed
        .where(
          (e) => e['event'] == 'chat_updated' || e['type'] == 'chat_updated',
        )
        .length;
    expect(updates, greaterThanOrEqualTo(2));
  });

  test('an omitted target still regenerates the last reply — the guest here, '
      'tail intact', () async {
    await buryHost();
    final idx = hostIndex();
    final before = h.chat.messages.length;
    hub.pushed.clear();

    final res = await postRegenerate({});
    expect(res.statusCode, 200);
    await waitForRegenCompletion();

    expect(h.chat.messages.length, before);
    expect(h.chat.messages.last.sender, 'Riley');
    expect(h.chat.messages.last.swipes.length, greaterThan(1));
    expect(h.chat.messages[idx].swipes.length, 1);
  });

  test('an unknown target is a 400 and runs nothing', () async {
    await buryHost();
    final idx = hostIndex();
    final before = h.chat.messages.length;
    final hostSwipes = h.chat.messages[idx].swipes.length;

    final res = await postRegenerate({'target': 'guest'});
    expect(res.statusCode, 400);
    await settle();

    expect(h.chat.isGenerating, isFalse);
    expect(h.chat.messages.length, before);
    expect(h.chat.messages[idx].swipes.length, hostSwipes);
  });

  test('in a group the offer is null — the rule is 1:1-only, whatever the '
      'ledger said', () async {
    await buryHost();
    expect(snapshotIndex(), isNotNull);
    await h.chat.setActiveGroup(
      GroupChat(id: 'gm-grp', name: 'Porch'),
      groupRepo: GroupChatRepository(h.storage, h.db),
    );
    await settle();
    expect(snapshotIndex(), isNull);
  });
}
