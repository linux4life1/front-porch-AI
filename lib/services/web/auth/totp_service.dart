// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:otp/otp.dart';

/// RFC 6238 TOTP for the optional web-login second factor.
///
/// Uses SHA1 / 6 digits / 30 s with Google-Authenticator-compatible secret
/// handling ([isGoogle]) so the generated `otpauth://` URI works with the common
/// authenticator apps (Google/Microsoft Authenticator, Authy, etc.). The QR is
/// rendered client-side in the web UI from the URI returned here; the raw secret
/// is shown only once during enrollment and never re-sent afterward.
class TotpService {
  TotpService({int Function()? nowMs})
      : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _nowMs;

  static const String _issuer = 'Front Porch AI';
  static const int _digits = 6;
  static const int _interval = 30;
  static const Algorithm _algorithm = Algorithm.SHA1;

  /// Generate a fresh base32 secret to enroll a new authenticator.
  String generateSecret() => OTP.randomSecret();

  /// Build the `otpauth://totp/...` provisioning URI for [username]/[secret].
  String provisioningUri(String username, String secret) {
    final label = Uri.encodeComponent('$_issuer:$username');
    final params = {
      'secret': secret,
      'issuer': _issuer,
      'algorithm': 'SHA1',
      'digits': '$_digits',
      'period': '$_interval',
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return 'otpauth://totp/$label?$query';
  }

  /// Verify [code] against [secret], accepting the previous/current/next step
  /// (±1 window) to tolerate clock skew. Non-digit input returns false.
  bool verify(String secret, String code) {
    final cleaned = code.trim();
    if (cleaned.length != _digits || int.tryParse(cleaned) == null) {
      return false;
    }
    final now = _nowMs();
    for (final offset in const [-1, 0, 1]) {
      final t = now + offset * _interval * 1000;
      final expected = OTP.generateTOTPCodeString(
        secret,
        t,
        length: _digits,
        interval: _interval,
        algorithm: _algorithm,
        isGoogle: true,
      );
      if (_constantTimeEquals(expected, cleaned)) return true;
    }
    return false;
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
