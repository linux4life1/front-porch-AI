// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Is this URL local?" has one answer in the app: isLocalRemoteUrl. A Custom
// URL at 127.0.0.1 is a model on this machine (a loopback is local), so it
// needs no API key and One-Shot Auto treats it like any local backend. The
// old checks knew only the literal 127.0.0.1, so 127.1.2.3 counted as remote.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

void main() {
  const table = <String, bool>{
    'http://127.0.0.1:5001/v1': true,
    'http://localhost:1234/v1': true,
    'http://LOCALHOST:1234/v1': true,
    'http://[::1]:5001/v1': true,
    'http://127.1.2.3:5001/v1': true,
    'http://0.0.0.0:5001/v1': true,
    'https://example.com/v1': false,
    'https://api.openrouter.ai/api/v1': false,
    'https://openrouter.ai/api/v1': false,
    'https://127.0.0.1.example.com/v1': false,
    '': false,
  };

  for (final entry in table.entries) {
    test('${entry.key.isEmpty ? '(empty)' : entry.key} is '
        '${entry.value ? 'local' : 'not local'}', () {
      expect(isLocalRemoteUrl(entry.key), entry.value);
    });
  }

  test('a Custom backend at a loopback URL is a local lane', () {
    expect(
      backendLaneIsLocal('openRouter', 'http://127.0.0.1:5001/v1'),
      isTrue,
    );
    expect(
      backendLaneIsLocal('openRouter', 'http://127.1.2.3:5001/v1'),
      isTrue,
    );
    expect(
      backendLaneIsLocal('openRouter', 'https://openrouter.ai/api/v1'),
      isFalse,
    );
  });
}
