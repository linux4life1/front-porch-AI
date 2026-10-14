// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The creator never re-asks a backend that refused the request (auth,
// billing, permission), and never mistakes a dead connection for one.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/character_gen/character_gen.dart';

void main() {
  test('auth, billing and permission answers are refusals', () {
    for (final said in [
      'API error: This API key is set to subscription-only billing and '
          'cannot spend from your balance (requested model: x)',
      'API error: Invalid API key provided',
      'API error: Insufficient credits',
      'API error: You exceeded your current quota',
      'API error: HTTP 401',
      'API error: HTTP 402',
      'API error: HTTP 403',
    ]) {
      expect(isBackendRefusal(Exception(said)), isTrue, reason: said);
    }
  });

  test('transient and local failures are not', () {
    for (final said in [
      'SocketException: Connection refused (OS Error: errno = 61)',
      'API error: HTTP 429',
      'API error: HTTP 503',
      'API error: The model is overloaded, try again',
      'ClientException: Connection closed before full header was received',
    ]) {
      expect(isBackendRefusal(Exception(said)), isFalse, reason: said);
    }
  });

  test('the message is the provider\'s own words', () {
    expect(
      refusalMessage(Exception('API error: Insufficient credits')),
      'Insufficient credits',
    );
  });
}
