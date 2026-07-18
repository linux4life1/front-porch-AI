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

    test('changeCredentials demands the current password', () async {
      final auth = make();
      await auth.setupAccount('admin', 'password123');

      final denied = await auth.changeCredentials(
        currentPassword: 'wrong',
        newPassword: 'newpassword1',
      );
      expect(denied, CredentialChangeStatus.invalidCurrentPassword);
      // The old credentials are untouched.
      expect(
        (await auth.login('admin', 'password123')).status,
        LoginStatus.success,
      );
    });

    test('changeCredentials rotates username and password', () async {
      final auth = make();
      await auth.setupAccount('admin', 'password123');

      final ok = await auth.changeCredentials(
        currentPassword: 'password123',
        newUsername: 'porchkeeper',
        newPassword: 'newpassword1',
      );
      expect(ok, CredentialChangeStatus.success);
      expect((await auth.accountInfo())?.username, 'porchkeeper');

      // Old credentials are dead; the new pair signs in.
      expect(
        (await auth.login('admin', 'password123')).status,
        LoginStatus.invalidCredentials,
      );
      expect(
        (await auth.login('porchkeeper', 'newpassword1')).status,
        LoginStatus.success,
      );
    });

    test('changeCredentials validates input and requires a change', () async {
      final auth = make();
      await auth.setupAccount('admin', 'password123');

      expect(
        await auth.changeCredentials(currentPassword: 'password123'),
        CredentialChangeStatus.invalidInput,
      );
      expect(
        await auth.changeCredentials(
          currentPassword: 'password123',
          newPassword: 'short',
        ),
        CredentialChangeStatus.invalidInput,
      );
    });

    test('with 2FA on, credential changes demand a current code', () async {
      final auth = make();
      await auth.setupAccount('admin', 'password123');
      final enrollment = await auth.beginTotpEnrollment();
      final code = OTP.generateTOTPCodeString(
        enrollment!.secret,
        fixedMs,
        length: 6,
        interval: 30,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
      await auth.confirmTotpEnrollment(code);

      expect(
        await auth.changeCredentials(
          currentPassword: 'password123',
          newPassword: 'newpassword1',
        ),
        CredentialChangeStatus.totpRequired,
      );
      expect(
        await auth.changeCredentials(
          currentPassword: 'password123',
          totpCode: code,
          newPassword: 'newpassword1',
        ),
        CredentialChangeStatus.success,
      );
    });

    test('disabling 2FA requires the password and a current code', () async {
      final auth = make();
      await auth.setupAccount('admin', 'password123');
      final enrollment = await auth.beginTotpEnrollment();
      final code = OTP.generateTOTPCodeString(
        enrollment!.secret,
        fixedMs,
        length: 6,
        interval: 30,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
      await auth.confirmTotpEnrollment(code);

      expect(
        await auth.disableTotp(currentPassword: 'wrong', totpCode: code),
        CredentialChangeStatus.invalidCurrentPassword,
      );
      expect(
        await auth.disableTotp(currentPassword: 'password123'),
        CredentialChangeStatus.totpRequired,
      );
      expect(
        await auth.disableTotp(currentPassword: 'password123', totpCode: code),
        CredentialChangeStatus.success,
      );
      // Password alone signs in again.
      expect(
        (await auth.login('admin', 'password123')).status,
        LoginStatus.success,
      );
    });

    test('resetAccount returns to setup mode and kills sessions', () async {
      final auth = make();
      await auth.setupAccount('admin', 'password123');
      final session = await auth.login('admin', 'password123');
      expect(await auth.sessions.validate(session.token!), isNotNull);

      await auth.resetAccount();
      expect(await auth.isSetupRequired(), isTrue);
      expect(await auth.accountInfo(), isNull);
      expect(await auth.sessions.validate(session.token!), isNull);
      // A fresh setup works after the wipe.
      expect(await auth.setupAccount('fresh', 'password456'), isTrue);
    });

    test('repeated wrong current passwords lock credential changes', () async {
      final auth = make();
      await auth.setupAccount('admin', 'password123');
      for (var i = 0; i < 5; i++) {
        await auth.changeCredentials(
          currentPassword: 'wrong',
          newPassword: 'newpassword1',
          ip: '6.6.6.6',
        );
      }
      expect(
        await auth.changeCredentials(
          currentPassword: 'password123',
          newPassword: 'newpassword1',
          ip: '6.6.6.6',
        ),
        CredentialChangeStatus.lockedOut,
      );
    });
  });
}
