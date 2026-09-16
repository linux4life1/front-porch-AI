// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Source-site pins for v1 web_search. Production-path behavior for direct,
// group-follow-up, guest, regen, Continue, and idle turns lives in the
// neighboring web_search_*_test.dart suites.

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/storage/storage.dart';

void main() {
  test('web search default is off', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final s = WebSearchSettings();
    s.initializeBase(null, () {});
    await s.load();
    expect(s.webSearchDefault, isFalse);
    expect(s.searchApiKey, isEmpty);
  });

  test('entry paths do not seed a per-chat web-search flag', () {
    const sites = {
      'lib/services/chat/chat_service_chat_entry.dart': 'opening a 1:1 chat',
      'lib/services/chat/chat_service_session_manage.dart': 'a fresh session',
      'lib/services/chat/chat_service_group_entry.dart': 'entering a group',
      'lib/services/chat/chat_service_import_seed.dart': 'import seed',
    };

    for (final e in sites.entries) {
      final src = File(e.key).readAsStringSync();
      expect(
        src,
        isNot(contains('seedEnabled')),
        reason:
            '${e.key} must not copy the Porch Life global into a persist '
            'flag — that sticks search on after the global is turned off '
            '("${e.value}")',
      );
    }
  });

  test('Continue does not call search', () {
    final request = File(
      'lib/services/chat/chat_service_generation_request.dart',
    ).readAsStringSync();
    expect(
      request,
      contains('GenerationMode.continue_'),
      reason: 'the tools round-trip must see Continue and skip search',
    );
    expect(
      request,
      contains('shouldAdvertiseWebSearch'),
      reason: 'Continue is gated by shouldAdvertiseWebSearch(continueMode: …)',
    );
    expect(
      request,
      contains('continueMode: t.mode == GenerationMode.continue_'),
    );
    expect(
      request,
      contains('webSearchDefault'),
      reason: 'the tools gate must read the Porch Life default at check time',
    );
    expect(
      request,
      isNot(contains('perChatEnabled')),
      reason: 'there is no per-chat web-search flag',
    );
    final persist = File(
      'lib/services/chat/chat_service_session_state.dart',
    ).readAsStringSync();
    expect(
      persist,
      isNot(contains('perChatEnabled')),
      reason:
          'save must not store a per-chat search flag — that sticks '
          'search on after Porch Life is turned off',
    );
    expect(persist, isNot(contains('web_search_enabled')));
  });

  test('WebSearchService reads the Porch Life default live, not at seed', () {
    final builder = File(
      'lib/services/chat/chat_service_web_search.dart',
    ).readAsStringSync();
    expect(
      builder,
      contains('getGlobalDefault'),
      reason:
          'isActive is the live Porch Life global; the callback must be wired',
    );
    expect(builder, contains('webSearchDefault'));
    expect(
      builder,
      isNot(contains('seedEnabled')),
      reason: 'no per-chat persist flag to hydrate',
    );

    final service = File(
      'lib/services/chat/web_search_service.dart',
    ).readAsStringSync();
    expect(service, contains('getGlobalDefault?.call()'));
    expect(service, isNot(contains('perChatEnabled')));
    expect(
      service,
      allOf(contains('globalDefault &&'), contains('directUserSend &&')),
      reason:
          'the Porch Life global is necessary, but only a direct user send '
          'may advertise the tool',
    );
  });

  test('no per-chat web-search sidebar or tools toggle remains', () {
    expect(
      File(
        'lib/ui/chat_components/sidebar/story_tools/story_tools_group.dart',
      ).readAsStringSync(),
      isNot(contains('WebSearchPanel')),
    );
    expect(
      File(
        'lib/ui/chat_components/sidebar/story_tools/story_tools.dart',
      ).readAsStringSync(),
      isNot(contains('web_search_panel')),
    );
    expect(
      File('lib/services/web/routes/chat_tools_routes.dart').readAsStringSync(),
      isNot(contains("'webSearch'")),
    );
    expect(
      File('web_ui/src/components/ChatTools.tsx').readAsStringSync(),
      isNot(contains('webSearch')),
    );
  });

  test(
    'tools round-trip uses the character prompt, not a silent lookup cue',
    () {
      final request = File(
        'lib/services/chat/chat_service_generation_request.dart',
      ).readAsStringSync();
      expect(
        request,
        isNot(contains('webSearchDecisionPrompt')),
        reason: 'search-only must not wrap the prompt in a silent lookup cue',
      );
      expect(request, isNot(contains('webSearchDecisionSystemPrompt')));
      expect(request, isNot(contains('catalogDecisionPrompt')));
      expect(
        request,
        contains('params: genParams'),
        reason: 'generateWithTools sees the same character prompt as the mouth',
      );
      expect(
        request,
        contains('runCatalogRound'),
        reason: 'one catalog round still dispatches in-process web_search',
      );
      expect(
        request,
        isNot(contains('spokenText')),
        reason:
            'doorbell speech is discarded; the mouth always streams with '
            'full character GenerationParams',
      );
      expect(
        request,
        contains('generateStream(genParams)'),
        reason: 'after the catalog round the mouth stream is unconditional',
      );
    },
  );

  test('no slash-command parser / /search route exists', () {
    expect(
      ChatCommandHandler.commands.map((c) => c.command),
      isNot(contains('search')),
    );
    final handler = File(
      'lib/services/chat/chat_command_handler.dart',
    ).readAsStringSync();
    expect(handler, isNot(contains("case 'search'")));
    expect(handler, isNot(contains("command == 'search'")));

    for (final path in [
      'lib/services/web/routes/chat_tools_routes.dart',
      'lib/services/web/routes/chat_routes.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(
        src.contains("/api/chat/search") || src.contains("'/search'"),
        isFalse,
        reason: '$path must not grow a /search route',
      );
    }
  });
}
