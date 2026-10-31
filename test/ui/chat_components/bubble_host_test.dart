// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A group has no host. Mid-turn its passes lend the active character to the
// member who is speaking; your bubbles took that member's text colour and
// font, and the chat showed their expression picture, until the pass ended.
// The chat page and the bubbles read the host through bubbleHost, which a
// group answers with nobody.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:front_porch_ai/ui/pages/chat_page_overlays.dart';
import 'package:front_porch_ai/ui/pages/home_page.dart';

import '../../golden/support/fakes.dart';
import '../pages/home/home_page_harness.dart';

/// A group mid-turn: a pass has lent the active character to [speaker].
class _GroupMidTurn extends FakeChatService {
  _GroupMidTurn(CharacterCard speaker) : super(activeCharacter: speaker);

  @override
  bool get isGroupMode => true;
}

/// Answers the reply at once and holds the story clock's call after it, so
/// the post-reply pass keeps its loan of the active character open while the
/// test looks at the page.
class _HeldClockLlm extends LLMService {
  final release = Completer<void>();
  bool clockAsked = false;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (p.contains('minutes_elapsed')) {
      clockAsked = true;
      await release.future;
      yield '{"minutes_elapsed": 5, "new_day": false}';
      return;
    }
    if (params.systemPrompt != null) {
      yield '*She leans on the porch rail.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'HeldClock';
}

const _zinnaInk = Color(0xFFE53935);

/// The style [text] is drawn in, as its spans resolve it.
TextStyle? _drawnStyle(WidgetTester tester, Finder where, String text) {
  TextStyle? drawn;
  void walk(InlineSpan span, TextStyle? outer) {
    final style = outer?.merge(span.style) ?? span.style;
    if (span is! TextSpan) return;
    if ((span.text ?? '').contains(text)) drawn ??= style;
    for (final child in span.children ?? const <InlineSpan>[]) {
      walk(child, style);
    }
  }

  final rich = find.descendant(
    of: where,
    matching: find.textContaining(text, findRichText: true),
  );
  walk(tester.widget<RichText>(rich.first).text, null);
  return drawn;
}

CharacterCard _zinna() => CharacterCard(
  name: 'Zinna',
  frontPorchExtensions: FrontPorchExtensions(
    userTextColor: _zinnaInk,
    chatFontFamily: 'Zinna Hand',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a group has no host while a pass lends the pointer', () {
    final zinna = _zinna();
    expect(bubbleHost(_GroupMidTurn(zinna)), isNull);
    expect(
      bubbleHost(FakeChatService(activeCharacter: zinna)),
      same(zinna),
      reason: '1:1 keeps its host',
    );
  });

  testWidgets('your bubble keeps your colour and font mid-turn', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    final chat = _GroupMidTurn(_zinna());
    addTearDown(chat.dispose);
    final yours = ChatMessage(
      text: 'Evening, both of you.',
      sender: 'User',
      isUser: true,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<TtsService>.value(value: FakeTtsService()),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<UserPersonaService>.value(
            value: FakeUserPersonaService(),
          ),
        ],
        // The transcript hands a user bubble its page's host: none in a
        // group, so the bubble falls back to bubbleHost.
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: yours, index: 0, chatService: chat),
          ),
        ),
      ),
    );

    final drawn = _drawnStyle(
      tester,
      find.byType(MessageBubble),
      'Evening, both of you.',
    );
    expect(drawn?.color, storage.uiSettings.getUserTextColor(null));
    expect(drawn?.color, isNot(_zinnaInk));
    expect(drawn?.fontFamily, isNot('Zinna Hand'));
  });

  testWidgets('the chat page dresses your bubbles in no member mid-reply', (
    tester,
  ) async {
    final rig = await HomeRig.build(
      tester,
      seed: (db) async {
        await db.insertGroup(
          GroupsCompanion.insert(id: 'grp-host', name: 'Porch'),
        );
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: 'mem-zinna',
            groupId: 'grp-host',
            name: 'Zinna',
            avatarFilename: const Value('mem-zinna.png'),
            frontPorchExtensions: Value(
              jsonEncode(_zinna().frontPorchExtensions!.toJson()),
            ),
          ),
        );
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: 'mem-senju',
            groupId: 'grp-host',
            name: 'Senjumaru',
            avatarFilename: const Value('mem-senju.png'),
          ),
        );
      },
    );
    final llm = _HeldClockLlm();
    rig.chat.testLlmServiceOverride = llm;
    Future<void> realWait(int ms) async {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: ms)),
      );
      await tester.pump();
    }

    await tester.runAsync(
      () => rig.chat.setActiveGroup(
        GroupChat(id: 'grp-host', name: 'Porch'),
        groupRepo: rig.groups,
      ),
    );
    await rig.pump(tester);
    unawaited(
      Navigator.of(
        tester.element(find.byType(HomePage)),
      ).push(MaterialPageRoute<void>(builder: (_) => const ChatPage())),
    );
    for (
      var i = 0;
      i < 100 && find.byType(ChatSurface).evaluate().isEmpty;
      i++
    ) {
      await realWait(20);
    }

    late Future<void> sending;
    await tester.runAsync(() async {
      sending = rig.chat.sendMessage('Hello there, both of you.');
    });
    for (
      var i = 0;
      i < 500 && !(llm.clockAsked && rig.chat.activeCharacter != null);
      i++
    ) {
      await realWait(10);
    }
    expect(
      rig.chat.activeCharacter?.name,
      'Zinna',
      reason: 'the reply is settling with its pass holding the loan',
    );
    await tester.pump();

    expect(
      tester.widget<ChatSurface>(find.byType(ChatSurface)).character,
      isNull,
    );
    final drawn = _drawnStyle(
      tester,
      find.byType(MessageBubble),
      'Hello there, both of you.',
    );
    expect(drawn?.color, rig.storage.uiSettings.getUserTextColor(null));
    expect(drawn?.color, isNot(_zinnaInk));

    llm.release.complete();
    await tester.runAsync(() => sending);
    await realWait(50);
    expect(rig.chat.activeCharacter, isNull);
  });
}
