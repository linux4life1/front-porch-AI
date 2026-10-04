// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// What the chat says when a model swap goes wrong. One message used to
// cover every case and always ended "Chat speech was put back", which was
// not true when the engine had been restarted and was still loading.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/generation_error_messages.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

void main() {
  test('a model still loading when the wait ended is said to be loading, '
      'and nothing is claimed about chat being put back', () {
    for (final error in [
      StateError('Kobold was not generation-ready after GPU swap restore'),
      const KoboldSwapTimeout(restarted: true, waited: Duration(seconds: 92)),
    ]) {
      final message = friendlyGenerationError(error.toString());
      expect(message, contains('still loading'), reason: '$error');
      expect(message, isNot(contains('put back')), reason: '$error');
    }
  });

  test('an engine that ignored the request is said to have not switched', () {
    final message = friendlyGenerationError(
      const KoboldSwapTimeout(
        restarted: false,
        waited: Duration(seconds: 60),
      ).toString(),
    );
    expect(message, contains('did not switch models'));
    expect(message, isNot(contains('put back')));
  });

  test('a request that never got through leaves chat in charge, and the '
      'message says so', () {
    final message = friendlyGenerationError(
      TimeoutException('Kobold admin reload_config timed out').toString(),
    );
    expect(message, contains('did not answer'));
    expect(message, contains('Chat speech was put back'));
  });
}
