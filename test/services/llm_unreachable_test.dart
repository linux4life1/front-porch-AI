// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for looksLikeBackendUnreachable — the shared "did we fail to reach the
// LLM backend at all?" matcher — isToolTransportFailure (its superset for the
// tools transport: adds timeouts, busy/5xx servers, and the closed-client
// race), and LlmUnavailableException's user-facing toString. The matcher must
// recognize the same failure across platforms: Windows words
// connection-refused as "The remote computer refused the network connection"
// (errno 1225), macOS as "Connection refused" (errno 61), Linux as errno 111.
// Story pages and the web client surface these errors verbatim.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/llm_service.dart';

void main() {
  group('looksLikeBackendUnreachable', () {
    test('matches Windows connection-refused wording (errno 1225)', () {
      const msg =
          'SocketException: OS Error: The remote computer refused the '
          'network connection., errno = 1225, address = 127.0.0.1, '
          'port = 5001';
      expect(looksLikeBackendUnreachable(Exception(msg)), isTrue);
    });

    test('matches macOS connection-refused wording (errno 61)', () {
      const msg =
          'SocketException: Connection refused (OS Error: Connection '
          'refused, errno = 61), address = 127.0.0.1, port = 5001';
      expect(looksLikeBackendUnreachable(Exception(msg)), isTrue);
    });

    test('matches Linux connection-refused wording (errno 111)', () {
      const msg =
          'SocketException: Connection refused (OS Error: Connection '
          'refused, errno = 111), address = 127.0.0.1, port = 5001';
      expect(looksLikeBackendUnreachable(Exception(msg)), isTrue);
    });

    test('matches http package mid-stream client close', () {
      expect(
        looksLikeBackendUnreachable(
          Exception('Connection closed before full header was received'),
        ),
        isTrue,
      );
      expect(
        looksLikeBackendUnreachable(
          Exception('ClientException: Client is already closed'),
        ),
        isTrue,
      );
    });

    test('does not match unrelated errors', () {
      expect(
        looksLikeBackendUnreachable(
          const FormatException('Unexpected character'),
        ),
        isFalse,
      );
      expect(
        looksLikeBackendUnreachable(Exception('HTTP 500: internal error')),
        isFalse,
      );
    });
  });

  group('isToolTransportFailure', () {
    test('classifies every transport-level failure of a tools call', () {
      // Whole-call timeout (the eval deadline in _fireToolEval throws).
      expect(isToolTransportFailure(TimeoutException('eval deadline')), isTrue);
      // Busy/5xx server (the doors throw this for 429/>=500).
      expect(
        isToolTransportFailure(LlmToolTransportException('tool call HTTP 503')),
        isTrue,
      );
      // Everything looksLikeBackendUnreachable matches.
      expect(
        isToolTransportFailure(
          Exception('SocketException: Connection refused, errno = 61'),
        ),
        isTrue,
      );
      // abortGeneration closing the client before post() — a raw StateError,
      // not a ClientException.
      expect(
        isToolTransportFailure(StateError('Client is already closed')),
        isTrue,
      );
    });

    test('does not classify capability-shaped errors as transport', () {
      expect(
        isToolTransportFailure(const FormatException('Unexpected character')),
        isFalse,
      );
      expect(
        isToolTransportFailure(Exception('model produced no tool calls')),
        isFalse,
      );
    });
  });

  group('LlmUnavailableException', () {
    test('toString is the plain message with no Exception prefix', () {
      final e = LlmUnavailableException('Backend is not running.');
      expect(e.toString(), 'Backend is not running.');
      // Pages render errors as 'Error: $e' — the result must stay readable.
      expect('Error: $e', 'Error: Backend is not running.');
    });
  });
}
