// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otp/otp.dart';
import 'package:shelf/shelf.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/auth/totp_service.dart';
import 'package:front_porch_ai/services/web/middleware/auth_middleware.dart';

/// The password the harness account was set up with.
const String kCivitaiTestPassword = 'password123';

/// The clock the harness's two-factor codes are made against.
const int kCivitaiTestClockMs = 1700000000000;

/// A real [AuthService] on an in-memory database with one account, so route
/// tests exercise the same password step-up the phone hits.
class CivitaiAuthHarness {
  CivitaiAuthHarness._(this.db, this.auth);

  final AppDatabase db;
  final AuthService auth;
  String? _secret;

  static Future<CivitaiAuthHarness> create() async {
    final db = AppDatabase.forTesting();
    final auth = AuthService(
      db,
      totpService: TotpService(nowMs: () => kCivitaiTestClockMs),
    );
    final status = await auth.setupAccount(
      'admin',
      kCivitaiTestPassword,
      isDirectLoopbackClient: true,
    );
    expect(status, SetupStatus.success);
    addTearDown(db.close);
    return CivitaiAuthHarness._(db, auth);
  }

  /// Turns two-factor on for the account, as the settings page does.
  Future<void> enableTwoFactor() async {
    final begin = await auth.beginTotpEnrollment(
      currentPassword: kCivitaiTestPassword,
    );
    _secret = begin.enrollment!.secret;
    await auth.confirmTotpEnrollment(
      currentPassword: kCivitaiTestPassword,
      code: code(),
    );
  }

  /// The code the authenticator app shows now, or [monthsAway] months from
  /// now for one that is certainly not valid.
  String code({int monthsAway = 0}) {
    return OTP.generateTOTPCodeString(
      _secret!,
      kCivitaiTestClockMs + monthsAway * 30 * 24 * 3600 * 1000,
      length: 6,
      interval: 30,
      algorithm: Algorithm.SHA1,
      isGoogle: true,
    );
  }
}

/// Key store backed by a map, so a test can read what was written.
CivitaiCredentialStore memoryCivitaiStore(Map<String, String> box) {
  return CivitaiCredentialStore(
    readKey: (key) async => box[key],
    writeKey: (key, value) async {
      box[key] = value;
    },
    deleteKey: (key) async {
      box.remove(key);
    },
  );
}

Request civitaiRequest(
  String method,
  String path, {
  Map<String, Object?>? body,
  String? account = 'local',
}) {
  return Request(
    method,
    Uri.parse('http://localhost$path'),
    body: body == null ? null : jsonEncode(body),
    context: {kAuthUserIdContextKey: ?account},
  );
}

Future<Map<String, dynamic>> civitaiJson(Response response) async {
  return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
}
