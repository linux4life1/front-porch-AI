// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// P0 #3 web HOLD: Journal off = recap off. Desktop hides Edit/Regen. The
// web Recap UI and POST /api/chat/tools/summary still wrote. These pins
// refuse the API write and the journal-card sibling.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';

import '../../golden/support/fakes.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_journal_gate_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late Router router;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storage = StorageService();
    chat = ChatService(
      KoboldService(storage),
      UserPersonaService(db),
      storage,
      WorldRepository(storage, db),
    )..setDatabase(db);
    router = Router();
    WebChatToolsRoutes(ChatToolsFacade(chat, storage, null), router);
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<shelf.Response> post(String path, Map<String, dynamic> body) {
    return router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost$path'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
  }

  test(
    'POST /api/chat/tools/summary text is refused when Journal is off',
    () async {
      chat.setSummary('They met on the porch.');
      await storage.memorySettings.setJournalEnabled(false);

      final res = await post('/api/chat/tools/summary', {'text': 'HACKED'});
      final body = jsonDecode(await res.readAsString()) as Map;

      expect(res.statusCode, 409);
      expect(body['error'].toString(), contains('Journal'));
      expect(
        chat.summary,
        'They met on the porch.',
        reason: 'Journal-off must not write the recap via the web API',
      );
    },
  );

  test(
    'POST /api/chat/tools/summary regenerate is refused when Journal is off',
    () async {
      chat.setSummary('They met on the porch.');
      await storage.memorySettings.setJournalEnabled(false);

      final res = await post('/api/chat/tools/summary', {
        'action': 'regenerate',
      });
      final body = jsonDecode(await res.readAsString()) as Map;

      expect(res.statusCode, 409);
      expect(body['error'].toString(), contains('Journal'));
      expect(chat.summary, 'They met on the porch.');
      expect(chat.isSummaryGenerating, isFalse);
    },
  );

  test(
    'POST /api/chat/tools/summary text still writes when Journal is on',
    () async {
      chat.setSummary('They met on the porch.');
      expect(storage.memorySettings.journalEnabled, isTrue);

      final res = await post('/api/chat/tools/summary', {
        'text': 'They sat on the steps.',
      });

      expect(res.statusCode, 200);
      expect(chat.summary, 'They sat on the steps.');
    },
  );

  test(
    'POST /api/chat/tools/journal plant is refused when Journal is off',
    () async {
      await storage.memorySettings.setJournalEnabled(false);

      final res = await post('/api/chat/tools/journal', {
        'action': 'plant',
        'text': 'should not land',
      });
      final body = jsonDecode(await res.readAsString()) as Map;

      expect(res.statusCode, 409);
      expect(body['error'].toString(), contains('Journal'));
    },
  );

  test('_summary and journal write routes check journalEnabled first', () {
    final src = File(
      'lib/services/web/routes/chat_tools_routes.dart',
    ).readAsStringSync();

    String slice(String startNeedle, String endNeedle) {
      final start = src.indexOf(startNeedle);
      final end = src.indexOf(endNeedle, start + 1);
      expect(start, greaterThanOrEqualTo(0), reason: startNeedle);
      expect(end, greaterThan(start), reason: endNeedle);
      return src.substring(start, end);
    }

    final summary = slice(
      'Future<shelf.Response> _summary',
      'Future<shelf.Response> _objective',
    );
    expect(summary.contains('journalEnabled'), isTrue);
    expect(
      summary.indexOf('journalEnabled'),
      lessThan(summary.indexOf('regenerateSummary')),
    );
    expect(
      summary.indexOf('journalEnabled'),
      lessThan(summary.indexOf('setSummaryText')),
    );

    final journalPost = slice(
      'Future<shelf.Response> _journalPost',
      'shelf.Response _journalReviewGet',
    );
    expect(journalPost.contains('journalEnabled'), isTrue);
    expect(
      journalPost.indexOf('journalEnabled'),
      lessThan(journalPost.indexOf('journalWeb.action')),
    );

    final journalReview = slice(
      'Future<shelf.Response> _journalReviewPost',
      'Future<Map<String, dynamic>> _json',
    );
    expect(journalReview.contains('journalEnabled'), isTrue);
    expect(
      journalReview.indexOf('journalEnabled'),
      lessThan(journalReview.indexOf('settleReview')),
    );
  });

  test('JournalWebSurface plant is a no-op when Journal is off', () async {
    await storage.memorySettings.setJournalEnabled(false);
    final store = JournalStore(getDb: () => db);
    final owner = ChatParticipant(
      card: CharacterCard(name: 'Mara', imagePath: '/tmp/mara.png'),
      isHost: true,
    );
    final surface = JournalWebSurface(
      chat: _JournalChat(store: store),
      storage: storage,
      notify: () {},
      resolveOwner: (_) => owner,
    );

    await surface.action(owner.id, 'plant', {'text': 'should not land'});
    expect(await store.cardsFor('s1', owner.id), isEmpty);
  });
}

class _JournalChat extends FakeChatService {
  _JournalChat({required this.store}) {
    journalReview = JournalReview(
      store: store,
      getSessionId: () => 's1',
      setRecap: (_) {},
      setCursor: (_) {},
      onSaveChat: () async {},
      onNotify: () {},
      getMaxCards: () => 200,
    );
  }

  final JournalStore store;

  @override
  late final JournalReview journalReview;

  @override
  JournalStore get journalStore => store;

  @override
  String? get currentSessionId => 's1';
}
