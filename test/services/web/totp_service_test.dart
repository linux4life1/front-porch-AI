// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:otp/otp.dart';
import 'package:front_porch_ai/services/web/auth/totp_service.dart';

void main() {
  group('TotpService', () {
    // Fixed clock so the generated code is deterministic.
    const fixedMs = 1700000000000;
    final svc = TotpService(nowMs: () => fixedMs);

    String codeAt(String secret, int ms) => OTP.generateTOTPCodeString(
          secret,
          ms,
          length: 6,
          interval: 30,
          algorithm: Algorithm.SHA1,
          isGoogle: true,
        );

    test('generateSecret returns a non-empty base32 secret', () {
      expect(svc.generateSecret(), isNotEmpty);
    });

    test('provisioningUri is a valid otpauth URI with the secret', () {
      final uri = svc.provisioningUri('alice', 'JBSWY3DPEHPK3PXP');
      expect(uri, startsWith('otpauth://totp/'));
      expect(uri, contains('secret=JBSWY3DPEHPK3PXP'));
      expect(uri, contains('algorithm=SHA1'));
    });

    test('verifies the current code and rejects a wrong one', () {
      final secret = svc.generateSecret();
      expect(svc.verify(secret, codeAt(secret, fixedMs)), isTrue);
      final wrong = codeAt(secret, fixedMs) == '000000' ? '111111' : '000000';
      expect(svc.verify(secret, wrong), isFalse);
    });

    test('accepts a code from the adjacent time step (±1 window)', () {
      final secret = svc.generateSecret();
      final prevStep = codeAt(secret, fixedMs - 30 * 1000);
      expect(svc.verify(secret, prevStep), isTrue);
    });

    test('rejects non-6-digit input', () {
      final secret = svc.generateSecret();
      expect(svc.verify(secret, '12345'), isFalse);
      expect(svc.verify(secret, 'abcdef'), isFalse);
    });
  });
}
