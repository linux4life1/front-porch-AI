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

  test('no slash-command parser /search exists', () {
    expect(
      ChatCommandHandler.commands.map((c) => c.command),
      isNot(contains('search')),
    );
  });
}
