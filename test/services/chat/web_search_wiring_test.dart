// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Source-site pins for v1 web_search. Production-path behavior for direct,
// group-follow-up, guest, regen, Continue, and idle turns lives in the
// neighboring web_search_*_test.dart suites.

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

  // The doorbell used to be the only lookup, so this file pinned that no
  // /search command existed. Named lookups are commands now. The words
  // after -- are the query. The model does not invent one.
  test('/search and /wiki are advertised named-lookup commands', () {
    final names = ChatCommandHandler.commands.map((c) => c.command);
    expect(names, contains('search'));
    expect(names, contains('wiki'));
  });
}
