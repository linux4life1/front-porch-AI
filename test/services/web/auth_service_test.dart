// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hashlib/hashlib.dart' show Argon2Security;
import 'package:otp/otp.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/auth/password_hasher.dart';
import 'package:front_porch_ai/services/web/auth/totp_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService', () {
    late AppDatabase db;
    const fixedMs = 1700000000000;

    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    // Real Argon2id at its test cost. At the app's 64 MiB cost the TOTP case
    // spent its time on 27 Argon2 passes (10 recovery codes hashed, then
    // checked) and ran past the 30 s limit on a busy runner.
    AuthService make() => AuthService(
      db,
      totpService: TotpService(nowMs: () => fixedMs),
      passwordHasher: const PasswordHasher(security: Argon2Security.test),
    );

    test('first run requires setup, then does not', () async {
      final auth = make();
      expect(await auth.isSetupRequired(), isTrue);
      expect(
        await auth.setupAccount(
          'admin',
          'password123',
          isDirectLoopbackClient: true,
        ),
        SetupStatus.success,
      );
      expect(await auth.isSetupRequired(), isFalse);
      // A second setup is refused.
      expect(
        await auth.setupAccount(
          'other',
          'password123',
          isDirectLoopbackClient: true,
        ),
        SetupStatus.alreadyConfigured,
      );
    });

    test('rejects a too-short password at setup', () async {
      final auth = make();
      expect(
        await auth.setupAccount('admin', 'short', isDirectLoopbackClient: true),
        SetupStatus.invalidInput,
      );
      expect(await auth.isSetupRequired(), isTrue);
    });

    test('remote setup demands the desktop one-time token', () async {
      final auth = make();
      expect(
        await auth.setupAccount(
          'admin',
          'password123',
          isDirectLoopbackClient: false,
        ),
        SetupStatus.tokenRequired,
      );
      expect(await auth.isSetupRequired(), isTrue);

      final token = await auth.setupTokenForDesktop();
      expect(token, isNotNull);
      expect(token!.length, greaterThanOrEqualTo(16));

      expect(
        await auth.setupAccount(
          'admin',
          'password123',
          isDirectLoopbackClient: false,
          setupToken: 'wrong-token-value!!!!',
        ),
        SetupStatus.invalidToken,
      );
      // Wrong token must not length-match if different; use same length junk.
      final sameLenWrong = 'x' * token.length;
      expect(
        await auth.setupAccount(
          'admin',
          'password123',
          isDirectLoopbackClient: false,
          setupToken: sameLenWrong,
        ),
        SetupStatus.invalidToken,
      );

      expect(
        await auth.setupAccount(
          'admin',
          'password123',
          isDirectLoopbackClient: false,
          setupToken: token,
        ),
        SetupStatus.success,
      );
      expect(await auth.isSetupRequired(), isFalse);
      expect(await auth.setupTokenForDesktop(), isNull);
    });

    test('setup rate-limits by IP', () async {
      final auth = make();
      for (var i = 0; i < 10; i++) {
        await auth.setupAccount(
          'admin',
          'password123',
          isDirectLoopbackClient: false,
          ip: '8.8.8.8',
        );
      }
      expect(
        await auth.setupAccount(
          'admin',
          'password123',
          isDirectLoopbackClient: false,
          ip: '8.8.8.8',
        ),
        SetupStatus.rateLimited,
      );
      // A different IP is not blocked by the first client's window.
      final token = await auth.setupTokenForDesktop();
      expect(
        await auth.setupAccount(
          'admin',
          'password123',
          isDirectLoopbackClient: false,
          setupToken: token,
          ip: '1.1.1.1',
        ),
        SetupStatus.success,
      );
    });

    test('resetAccount mints a fresh setup token', () async {
      final auth = make();
      await auth.setupAccount(
        'admin',
        'password123',
        isDirectLoopbackClient: true,
      );
      await auth.resetAccount();
      final token = await auth.setupTokenForDesktop();
      expect(token, isNotNull);
      expect(await auth.isSetupRequired(), isTrue);
    });

    test(
      'verifyStepUp demands the current password (tunnel enable gate)',
      () async {
        final auth = make();
        await auth.setupAccount(
          'admin',
          'password123',
          isDirectLoopbackClient: true,
        );
        // Session alone is not enough — empty / wrong password fail.
        expect(
          await auth.verifyStepUp(currentPassword: ''),
          CredentialChangeStatus.invalidCurrentPassword,
        );
        expect(
          await auth.verifyStepUp(currentPassword: 'wrong'),
          CredentialChangeStatus.invalidCurrentPassword,
        );
        expect(
          await auth.verifyStepUp(currentPassword: 'password123'),
          CredentialChangeStatus.success,
        );

        // With 2FA on, password alone is not enough.
        final begin = await auth.beginTotpEnrollment(
          currentPassword: 'password123',
        );
        final code = OTP.generateTOTPCodeString(
          begin.enrollment!.secret,
          fixedMs,
          length: 6,
          interval: 30,
          algorithm: Algorithm.SHA1,
          isGoogle: true,
        );
        await auth.confirmTotpEnrollment(
          currentPassword: 'password123',
          code: code,
        );
        expect(
          await auth.verifyStepUp(currentPassword: 'password123'),
          CredentialChangeStatus.totpRequired,
        );
        expect(
          await auth.verifyStepUp(
            currentPassword: 'password123',
            totpCode: code,
          ),
          CredentialChangeStatus.success,
        );
      },
    );

    test('login succeeds with correct creds, fails otherwise', () async {
      final auth = make();
      await auth.setupAccount(
        'admin',
        'password123',
        isDirectLoopbackClient: true,
      );

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
      await auth.setupAccount(
        'admin',
        'password123',
        isDirectLoopbackClient: true,
      );
      for (var i = 0; i < 5; i++) {
        await auth.login('admin', 'wrong', ip: '5.5.5.5');
      }
      final locked = await auth.login('admin', 'password123', ip: '5.5.5.5');
      expect(locked.status, LoginStatus.lockedOut);
      expect(locked.retryAfterSeconds, greaterThan(0));
    });

    test('TOTP enrollment then login requires and accepts the code', () async {
      final auth = make();
      await auth.setupAccount(
        'admin',
        'password123',
        isDirectLoopbackClient: true,
      );

      final begin = await auth.beginTotpEnrollment(
        currentPassword: 'password123',
      );
      expect(begin.status, CredentialChangeStatus.success);
      expect(begin.enrollment, isNotNull);
      final code = OTP.generateTOTPCodeString(
        begin.enrollment!.secret,
        fixedMs,
        length: 6,
        interval: 30,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
      final confirm = await auth.confirmTotpEnrollment(
        currentPassword: 'password123',
        code: code,
      );
      expect(confirm.status, CredentialChangeStatus.success);
      expect(confirm.recoveryCodes, isNotNull);
      expect(confirm.recoveryCodes!.length, 10);
      final recovery = confirm.recoveryCodes!;

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

    test(
      '2FA begin/confirm demand the current password (session alone is not enough)',
      () async {
        final auth = make();
        await auth.setupAccount(
          'admin',
          'password123',
          isDirectLoopbackClient: true,
        );

        // Hijacked session path: no / wrong password cannot start enrollment.
        expect(
          (await auth.beginTotpEnrollment(currentPassword: '')).status,
          CredentialChangeStatus.invalidCurrentPassword,
        );
        expect(
          (await auth.beginTotpEnrollment(currentPassword: 'wrong')).status,
          CredentialChangeStatus.invalidCurrentPassword,
        );

        final begin = await auth.beginTotpEnrollment(
          currentPassword: 'password123',
        );
        expect(begin.status, CredentialChangeStatus.success);
        final code = OTP.generateTOTPCodeString(
          begin.enrollment!.secret,
          fixedMs,
          length: 6,
          interval: 30,
          algorithm: Algorithm.SHA1,
          isGoogle: true,
        );

        // Confirm also demands the password — a leaked pending secret + session
        // cookie without the password still cannot enable 2FA.
        expect(
          (await auth.confirmTotpEnrollment(
            currentPassword: 'wrong',
            code: code,
          )).status,
          CredentialChangeStatus.invalidCurrentPassword,
        );
        expect(
          (await auth.confirmTotpEnrollment(
            currentPassword: 'password123',
            code: code,
          )).status,
          CredentialChangeStatus.success,
        );
      },
    );

    test(
      '2FA re-enroll is refused while already enabled (no silent replace)',
      () async {
        final auth = make();
        await auth.setupAccount(
          'admin',
          'password123',
          isDirectLoopbackClient: true,
        );
        final begin = await auth.beginTotpEnrollment(
          currentPassword: 'password123',
        );
        final code = OTP.generateTOTPCodeString(
          begin.enrollment!.secret,
          fixedMs,
          length: 6,
          interval: 30,
          algorithm: Algorithm.SHA1,
          isGoogle: true,
        );
        await auth.confirmTotpEnrollment(
          currentPassword: 'password123',
          code: code,
        );

        // Owner (or hijacker) with password still cannot replace the secret
        // while 2FA is on — must disable first.
        expect(
          (await auth.beginTotpEnrollment(
            currentPassword: 'password123',
          )).status,
          CredentialChangeStatus.alreadyEnabled,
        );
        expect(
          (await auth.confirmTotpEnrollment(
            currentPassword: 'password123',
            code: code,
          )).status,
          CredentialChangeStatus.alreadyEnabled,
        );
        // Original secret still works for login.
        expect(
          (await auth.login('admin', 'password123', totpCode: code)).status,
          LoginStatus.success,
        );
      },
    );

    test('changeCredentials demands the current password', () async {
      final auth = make();
      await auth.setupAccount(
        'admin',
        'password123',
        isDirectLoopbackClient: true,
      );

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
      await auth.setupAccount(
        'admin',
        'password123',
        isDirectLoopbackClient: true,
      );

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
      await auth.setupAccount(
        'admin',
        'password123',
        isDirectLoopbackClient: true,
      );

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
      await auth.setupAccount(
        'admin',
        'password123',
        isDirectLoopbackClient: true,
      );
      final begin = await auth.beginTotpEnrollment(
        currentPassword: 'password123',
      );
      final code = OTP.generateTOTPCodeString(
        begin.enrollment!.secret,
        fixedMs,
        length: 6,
        interval: 30,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
      await auth.confirmTotpEnrollment(
        currentPassword: 'password123',
        code: code,
      );

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
      await auth.setupAccount(
        'admin',
        'password123',
        isDirectLoopbackClient: true,
      );
      final begin = await auth.beginTotpEnrollment(
        currentPassword: 'password123',
      );
      final code = OTP.generateTOTPCodeString(
        begin.enrollment!.secret,
        fixedMs,
        length: 6,
        interval: 30,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
      await auth.confirmTotpEnrollment(
        currentPassword: 'password123',
        code: code,
      );

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
      await auth.setupAccount(
        'admin',
        'password123',
        isDirectLoopbackClient: true,
      );
      final session = await auth.login('admin', 'password123');
      expect(await auth.sessions.validate(session.token!), isNotNull);

      await auth.resetAccount();
      expect(await auth.isSetupRequired(), isTrue);
      expect(await auth.accountInfo(), isNull);
      expect(await auth.sessions.validate(session.token!), isNull);
      // A fresh setup works after the wipe.
      expect(
        await auth.setupAccount(
          'fresh',
          'password456',
          isDirectLoopbackClient: true,
        ),
        SetupStatus.success,
      );
    });

    test('repeated wrong current passwords lock credential changes', () async {
      final auth = make();
      await auth.setupAccount(
        'admin',
        'password123',
        isDirectLoopbackClient: true,
      );
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
