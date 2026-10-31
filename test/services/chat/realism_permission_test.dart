// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Porch Life's Realism permission, the first of Realism's three layers.
// Realism runs while Porch Life allows it AND the chat's own switch is on,
// both read live: off stops it in the open chat on its next read, 1:1 and
// group, while the chat's own switch stays what the chat chose, in memory
// and in its saved row. Back on, a chat whose Realism never ran scores its
// starting point once, the way turning its own switch on does: the open
// chat at once, a chat saved while blocked when it is next opened. A
// missing pref reads as allowed, so an upgrade changes nothing.
//
// The scripted model only feeds the gate under test: these tests count
// which calls are made, never what a reply or a score says.

import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/services/web/facade/chat_realism_read.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools_facade.dart';
import 'package:front_porch_ai/services/web/facade/settings_facade.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_realism_gate_').path;
        }
        return null;
      });
}

/// Records which kind of call each request is. Its answers only keep the
/// turn moving; nothing here asserts them back.
class _CountingLlm extends LLMService {
  final calls = <String>[];

  /// Every call the Realism Engine makes, one-shot or one per judge.
  Iterable<String> get realismCalls => calls.where(
    (c) =>
        c != 'chat' &&
        c != 'time' &&
        c != 'with_user' &&
        // The backend's tool-support probe, not an eval.
        c != 'tools:report_ping' &&
        c != 'tools:report_scene_time',
  );

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    final names = [
      for (final tool in tools) (tool['function'] as Map?)?['name'] as String?,
    ];
    calls.add('tools:${names.join(',')}');
    return null;
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      calls.add('chat');
      yield '*She leans on the rail.*';
      return;
    }
    final p = params.prompt;
    if (p.contains('relationship_delta')) {
      calls.add('relationship');
      yield '{"relationship_delta":2,"trust_delta":1,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      calls.add('with_user');
      yield '{"with_user": true}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      calls.add('emotion');
      yield '{"emotion":"calm","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      calls.add('time');
      yield '{"minutes_elapsed": 10, "new_day": false}';
      return;
    }
    calls.add('other');
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'CountingRealismGate';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  CharacterRepository? repo;
  ChatService? chat;
  late _CountingLlm llm;

  RealismSettings rs() => storage!.realismSettings;

  Future<void> drain() async {
    for (
      var i = 0;
      i < 400 &&
          (chat!.isGenerating ||
              chat!.isSettlingTurn ||
              chat!.isProcessingGreeting);
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
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    repo = CharacterRepository(db!, storage!);
    llm = _CountingLlm();
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
    // The clock and Needs stay out of the count: only Realism's calls are.
    await rs().setPassageOfTimeDefault(false);
    await rs().setNeedsSimDefault(false);
  }

  Future<CharacterCard> card(String name, {required bool realism}) async {
    final c = CharacterCard(
      name: name,
      firstMessage: 'Evening.',
      imagePath: '/tmp/${name.toLowerCase()}-realism-gate.png',
      frontPorchExtensions: FrontPorchExtensions(realismEnabled: realism),
    );
    await repo!.addCharacter(c);
    return c;
  }

  Future<bool> storedSwitch(String sessionId) async {
    await chat!.flushPendingSaves();
    final row = await db!
        .customSelect(
          'SELECT realism_enabled AS r FROM sessions WHERE id = ?',
          variables: [Variable(sessionId)],
        )
        .getSingle();
    return row.read<bool>('r');
  }

  Future<void> send(String text) async {
    await chat!.sendMessage(text);
    await drain();
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test(
    "Porch Life off stops Realism in an open 1:1 chat at once, the chat's "
    'own switch kept in memory and in its saved row; on again resumes it',
    () async {
      await boot();
      await chat!.setActiveCharacter(await card('Mara', realism: true));
      final id = chat!.currentSessionId!;
      expect(chat!.realismEnabled, isTrue);

      await send('Hello there.');
      expect(
        llm.realismCalls,
        isNotEmpty,
        reason: 'Realism runs while allowed',
      );

      await rs().setRealismAllowed(false);
      expect(chat!.realismEnabled, isFalse, reason: 'the gate, read live');
      expect(chat!.realismChatSwitch, isTrue, reason: "the chat's own choice");
      llm.calls.clear();
      await send('Still here.');
      expect(llm.calls, contains('chat'));
      expect(llm.realismCalls, isEmpty, reason: 'no chat runs Realism');
      expect(
        await storedSwitch(id),
        isTrue,
        reason: "the save writes the chat's own switch, never the gate",
      );

      await rs().setRealismAllowed(true);
      expect(chat!.realismEnabled, isTrue);
      llm.calls.clear();
      await send('Back again.');
      expect(llm.realismCalls, isNotEmpty, reason: 'its own choice, resumed');
    },
  );

  test("while blocked, the chat's own switch still saves as the chat sets "
      'it', () async {
    await boot();
    await rs().setRealismAllowed(false);
    await chat!.setActiveCharacter(await card('Ivy', realism: true));
    final id = chat!.currentSessionId!;
    expect(await storedSwitch(id), isTrue, reason: 'the card seeded it on');
    await chat!.setRealismEnabled(false);
    expect(await storedSwitch(id), isFalse);
    expect(llm.realismCalls, isEmpty);
    await chat!.setRealismEnabled(true);
    expect(await storedSwitch(id), isTrue);
    expect(chat!.realismEnabled, isFalse, reason: 'Porch Life still blocks');
    await drain();
    expect(llm.realismCalls, isEmpty, reason: 'no scan while blocked');
  });

  test('a 1:1 chat started while Realism was blocked scores its starting '
      'point once, the moment Porch Life allows it again', () async {
    await boot();
    await rs().setRealismAllowed(false);
    await chat!.setActiveCharacter(await card('Nell', realism: true));
    await send('We have been talking a while.');
    expect(llm.realismCalls, isEmpty, reason: 'blocked: nothing scored');

    llm.calls.clear();
    await rs().setRealismAllowed(true);
    await drain();
    expect(
      llm.realismCalls,
      isNotEmpty,
      reason: 'the retroactive baseline scan, as turning its switch on does',
    );
    final scan = llm.realismCalls.length;
    expect(llm.calls, isNot(contains('chat')), reason: 'a scan, not a reply');

    // Another Porch Life change, and the permission set again: no second scan.
    await rs().setWeatherEnabled(false);
    await rs().setRealismAllowed(true);
    await drain();
    expect(llm.realismCalls.length, scan, reason: 'once per chat');
  });

  test('a 1:1 chat saved while Realism was blocked scores its starting point '
      'once, when it is next opened', () async {
    await boot();
    await rs().setRealismAllowed(false);
    final nell = await card('Nell', realism: true);
    final other = await card('Otto', realism: false);
    await chat!.setActiveCharacter(nell);
    await send('A long talk, all of it before Realism could run.');
    final id = chat!.currentSessionId!;
    await chat!.setActiveCharacter(other);
    await chat!.flushPendingSaves();
    // Saved an hour before Porch Life allowed Realism again.
    await db!.customUpdate(
      'UPDATE sessions SET updated_at = ? WHERE id = ?',
      variables: [
        Variable<DateTime>(DateTime.now().subtract(const Duration(hours: 1))),
        Variable(id),
      ],
    );

    await rs().setRealismAllowed(true);
    await drain();
    expect(llm.realismCalls, isEmpty, reason: 'the open chat has it off');

    await chat!.setActiveCharacter(nell);
    expect(chat!.currentSessionId, id);
    await drain();
    expect(llm.realismCalls, isNotEmpty, reason: 'scored on its first open');
    final scan = llm.realismCalls.length;

    await chat!.setActiveCharacter(other);
    await chat!.setActiveCharacter(nell);
    await drain();
    expect(llm.realismCalls.length, scan, reason: 'one eval per chat opened');
  });

  test('upgrading: no pref reads as allowed, new chats seed as before, and '
      'opening a chat never scores it', () async {
    await boot();
    expect(rs().realismAllowed, isTrue);
    expect(rs().realismAllowedSince, isNull);

    final on = await card('Ada', realism: true);
    final off = await card('Bo', realism: false);
    await chat!.setActiveCharacter(on);
    expect(chat!.realismEnabled, isTrue);
    expect(chat!.realismChatSwitch, isTrue);
    await chat!.setActiveCharacter(off);
    expect(chat!.realismEnabled, isFalse, reason: 'the card says off');
    await send('Talking with Realism off.');
    final id = chat!.currentSessionId!;

    // A chat whose Realism is on and never ran, as an old row can be.
    await chat!.setActiveCharacter(on);
    await db!.customUpdate(
      'UPDATE sessions SET realism_enabled = 1, '
      'updated_at = ? WHERE id = ?',
      variables: [
        Variable<DateTime>(DateTime.now().subtract(const Duration(days: 30))),
        Variable(id),
      ],
    );
    llm.calls.clear();
    await chat!.setActiveCharacter(off);
    expect(chat!.currentSessionId, id);
    expect(chat!.realismEnabled, isTrue);
    await drain();
    expect(llm.realismCalls, isEmpty, reason: 'no scan on open, as today');

    // "Start every new chat with Realism" still ORs into a new chat's seed.
    await rs().setRealismDefault(true);
    await chat!.startNewChat();
    expect(chat!.realismChatSwitch, isTrue);
  });

  test('a chat started while Realism is blocked keeps its card\'s choices: '
      "Realism on, and a silent card's Needs with it", () async {
    await boot();
    await rs().setNeedsSimDefault(true);
    await rs().setRealismAllowed(false);
    await chat!.setActiveCharacter(await card('Tess', realism: true));
    expect(chat!.realismChatSwitch, isTrue);
    expect(
      chat!.needsSimEnabled,
      isTrue,
      reason: "a silent card's Needs follow the chat's own Realism",
    );
    expect(chat!.needsActive, isFalse, reason: 'Porch Life vetoes it live');
    await rs().setRealismAllowed(true);
    expect(chat!.needsActive, isTrue);
  });

  test("the phone's settings carry the permission and set it, and its chat "
      "tools carry the chat's own switch beside the gate", () async {
    await boot();
    await chat!.setActiveCharacter(await card('Pia', realism: true));
    final engine = BackendManager(storage!, onMac: false, onLinux: false);
    final kobold = KoboldService(storage!);
    final llmProvider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage!,
      engine,
    );
    addTearDown(() {
      llmProvider.dispose();
      kobold.dispose();
      engine.dispose();
    });
    final settings = SettingsFacade(storage!, llmProvider);
    final tools = ChatToolsFacade(chat!, storage!, null);
    Map<String, dynamic> realism() =>
        settings.read()['realism'] as Map<String, dynamic>;
    expect(realism()['realismAllowed'], isTrue, reason: 'missing reads on');
    expect(tools.state(), containsPair('realismAllowed', true));
    expect(tools.state(), containsPair('realismSwitch', true));

    await settings.update({
      'realism': {'realismAllowed': false},
    });
    expect(rs().realismAllowed, isFalse);
    expect(realism()['realismAllowed'], isFalse);
    expect(realism()['realismDefault'], isFalse, reason: 'its own key');
    final blocked = tools.state();
    expect(blocked['realismEnabled'], isFalse, reason: 'the gate');
    expect(blocked['realismAllowed'], isFalse);
    expect(blocked['realismSwitch'], isTrue, reason: "the chat's own");
  });

  test(
    'Standing Mood reads the Needs gate, not the stored Needs switch',
    () async {
      await boot();
      await rs().setNeedsSimDefault(true);
      await rs().setStandingMoodEnabled(true);
      await chat!.setActiveCharacter(await card('Wren', realism: true));
      await chat!.setNeedsSimEnabled(true);
      chat!.needsSimulation.restoreFromSnapshot({
        'vector': {
          'hunger': 80,
          'bladder': 80,
          'energy': 10,
          'social': 80,
          'fun': 80,
          'hygiene': 80,
          'comfort': 80,
        },
      });
      expect(chat!.standingMoodSummary, contains('exhausted'));

      await rs().setNeedsSimDefault(false);
      expect(chat!.needsSimEnabled, isTrue, reason: 'the stored switch');
      expect(
        chat!.standingMoodSummary,
        isEmpty,
        reason: 'Needs off in Porch Life: frozen bars are nobody\'s day',
      );

      await rs().setNeedsSimDefault(true);
      await rs().setRealismAllowed(false);
      expect(chat!.standingMoodSummary, isEmpty, reason: 'Realism blocked');
      await rs().setRealismAllowed(true);
      expect(chat!.standingMoodSummary, contains('exhausted'));
    },
  );

  test("Porch Life off stops Realism in an open group chat, the group chat's "
      'own switch kept in its saved row', () async {
    await boot();
    final blobs = buildGroupRealismBlobs(
      seeds: {
        'mem-ana': defaultGroupMemberRealismSeed(),
        'mem-bea': defaultGroupMemberRealismSeed(),
      },
      needsEnabled: false,
      timeOfDay: 'evening',
      dayCount: 1,
    );
    await db!.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-gate',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    for (final m in [('mem-ana', 'Ana'), ('mem-bea', 'Bea')]) {
      await db!.insertGroupMember(
        GroupMembersCompanion.insert(
          id: m.$1,
          groupId: 'grp-gate',
          name: m.$2,
          firstMessage: const Value('Evening.'),
        ),
      );
    }
    await chat!.setActiveGroup(
      GroupChat(
        id: 'grp-gate',
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage!, db!),
    );
    await chat!.setRealismEnabled(true);
    final id = chat!.currentSessionId!;
    expect(chat!.isGroupRealismActive, isTrue);

    Map<String, dynamic> phone() => ChatRealismRead(
      chat!,
    ).participantRealism(chat!.cast.firstWhere((p) => !p.isHost).id)!;
    expect(phone()['realismEnabled'], isTrue);

    await rs().setRealismAllowed(false);
    expect(chat!.isGroupRealismActive, isFalse, reason: 'read live');
    expect(chat!.realismChatSwitch, isTrue);
    expect(await storedSwitch(id), isTrue);
    expect(phone(), {
      'realismEnabled': false,
      'realismAllowed': false,
    }, reason: "the phone's member panel, as the desktop member card");
    llm.calls.clear();
    await send('Evening, both of you.');
    expect(llm.calls, contains('chat'), reason: 'the group still answers');
    expect(llm.realismCalls, isEmpty, reason: 'no member is scored');

    await rs().setRealismAllowed(true);
    expect(chat!.isGroupRealismActive, isTrue, reason: 'its own choice back');
    llm.calls.clear();
    await send('Still here.');
    expect(llm.realismCalls, isNotEmpty);
  });
}
