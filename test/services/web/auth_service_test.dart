// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:otp/otp.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/auth/totp_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService', () {
    late AppDatabase db;
    const fixedMs = 1700000000000;

    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    AuthService make() =>
        AuthService(db, totpService: TotpService(nowMs: () => fixedMs));

    test('first run requires setup, then does not', () async {
      final auth = make();
      expect(await auth.isSetupRequired(), isTrue);
      expect(await auth.setupAccount('admin', 'password123'), isTrue);
      expect(await auth.isSetupRequired(), isFalse);
      // A second setup is refused.
      expect(await auth.setupAccount('other', 'password123'), isFalse);
    });

    test('rejects a too-short password at setup', () async {
      final auth = make();
      expect(await auth.setupAccount('admin', 'short'), isFalse);
      expect(await auth.isSetupRequired(), isTrue);
    });

    test('login succeeds with correct creds, fails otherwise', () async {
      final auth = make();
      await auth.setupAccount('admin', 'password123');

      final ok = await auth.login('admin', 'password123');
      expect(ok.status, LoginStatus.success);
      expect(ok.token, isNotNull);

      final bad = await auth.login('admin', 'wrong');
      expect(bad.status, LoginStatus.invalidCredentials);

      final badUser = await auth.login('nobody', 'password123');
      expect(badUser.status, LoginStatus.invalidCredentials);
    });

    test('locks out after repeated failures', () async {
      final auth = make();
      await auth.setupAccount('admin', 'password123');
      for (var i = 0; i < 5; i++) {
        await auth.login('admin', 'wrong', ip: '5.5.5.5');
      }
      final locked = await auth.login('admin', 'password123', ip: '5.5.5.5');
      expect(locked.status, LoginStatus.lockedOut);
      expect(locked.retryAfterSeconds, greaterThan(0));
    });

    test('TOTP enrollment then login requires and accepts the code', () async {
      final auth = make();
      await auth.setupAccount('admin', 'password123');

      final enrollment = await auth.beginTotpEnrollment();
      expect(enrollment, isNotNull);
      final code = OTP.generateTOTPCodeString(
        enrollment!.secret,
        fixedMs,
        length: 6,
        interval: 30,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
      final recovery = await auth.confirmTotpEnrollment(code);
      expect(recovery, isNotNull);
      expect(recovery!.length, 10);

      // Password alone now demands a second factor.
      final needsTotp = await auth.login('admin', 'password123');
      expect(needsTotp.status, LoginStatus.totpRequired);

      // Password + valid code succeeds.
      final full = await auth.login('admin', 'password123', totpCode: code);
      expect(full.status, LoginStatus.success);

      // A recovery code is accepted once, then consumed.
      final viaRecovery = await auth.login(
        'admin',
        'password123',
        totpCode: recovery[0],
      );
      expect(viaRecovery.status, LoginStatus.success);
      final reuse = await auth.login(
        'admin',
        'password123',
        totpCode: recovery[0],
      );
      expect(reuse.status, LoginStatus.totpRequired);
    });
  });
}
