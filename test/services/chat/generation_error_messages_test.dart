// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the generation-failure error message mapper, extracted verbatim
// from ChatService._generateResponse's catch block during the god-file split
// (docs/design/god-file-elimination.md). Pins the four known-failure
// mappings plus passthrough so a future edit can't silently drop one.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/generation_error_messages.dart';

void main() {
  test('strips the Dart "Exception: " prefix', () {
    expect(
      friendlyGenerationError('Exception: something odd happened'),
      'something odd happened',
    );
  });

  test('maps STREAMING_NOT_SUPPORTED / HTTP 405 to a settings hint', () {
    final msg = friendlyGenerationError(
      'Exception: HTTP 405 Method Not Allowed',
    );
    expect(msg, contains('HTTP 405'));
    expect(msg, contains('Settings > Generation Settings'));
  });

  test('maps a crashed backend to a VRAM hint', () {
    final msg = friendlyGenerationError('Backend process crashed unexpectedly');
    expect(msg, contains('crashed (likely out of VRAM)'));
  });

  test('maps a timeout to a size/speed hint', () {
    final msg = friendlyGenerationError(
      'TimeoutException after 0:02:00.000000',
    );
    expect(
      msg,
      'Request timed out. The model may be too large or the server too slow.',
    );
  });

  test('maps a mid-stream connection close to a loading hint', () {
    final msg = friendlyGenerationError(
      'ClientException: Connection closed before full header was received',
    );
    expect(msg, contains('closed unexpectedly'));
    expect(msg, contains('green ready indicator'));
  });

  test('empty assistant after PRE-GEN attach is a speech failure', () {
    expect(emptySpeechAfterPregen(accumulated: '', isContinue: false), isTrue);
    expect(
      emptySpeechAfterPregen(accumulated: '\n', isContinue: false),
      isTrue,
    );
    expect(
      emptySpeechAfterPregen(accumulated: 'Hi', isContinue: false),
      isFalse,
    );
    expect(emptySpeechAfterPregen(accumulated: '', isContinue: true), isFalse);
    expect(kEmptySpeechAfterPregenNotice, contains('empty'));
  });

  test('leaves an unrecognized error message unchanged (minus the prefix)', () {
    expect(
      friendlyGenerationError('Exception: some totally novel failure'),
      'some totally novel failure',
    );
  });
}
