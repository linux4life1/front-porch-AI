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

import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Variable;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/web/auth/password_hasher.dart';
import 'package:front_porch_ai/services/web/auth/rate_limiter.dart';
import 'package:front_porch_ai/services/web/auth/session_store.dart';
import 'package:front_porch_ai/services/web/auth/totp_service.dart';

/// Outcome of a login attempt.
enum LoginStatus {
  success,
  invalidCredentials,
  totpRequired,
  lockedOut,
  rateLimited,
  notSetUp,
}

class LoginResult {
  const LoginResult(this.status, {this.token, this.retryAfterSeconds});
  final LoginStatus status;
  final String? token; // raw session cookie token on success
  final int? retryAfterSeconds;
}

/// Result of confirming TOTP enrollment — recovery codes are returned ONCE.
class TotpEnrollment {
  const TotpEnrollment(this.secret, this.provisioningUri);
  final String secret;
  final String provisioningUri;
}

/// The single-account secure-login service for the rewritten web server.
///
/// One credentials row (id 'local'). Coordinates Argon2id password hashing,
/// optional TOTP 2FA + single-use recovery codes, rate limiting, and persisted
/// sessions. All credential storage uses raw SQL against `web_auth_credentials`
/// (matching the codebase's service-level DB style).
class AuthService {
  AuthService(
    this._db, {
    PasswordHasher? passwordHasher,
    TotpService? totpService,
    SessionStore? sessionStore,
    RateLimiter? rateLimiter,
  })  : _hasher = passwordHasher ?? PasswordHasher(),
        _totp = totpService ?? TotpService(),
        sessions = sessionStore ?? SessionStore(_db),
        _limiter = rateLimiter ?? RateLimiter();

  final AppDatabase _db;
  final PasswordHasher _hasher;
  final TotpService _totp;
  final RateLimiter _limiter;

  /// Exposed so the host/routes share one session store instance.
  final SessionStore sessions;

  static const String _accountId = 'local';
  static const int _recoveryCodeCount = 10;

  /// In-memory pending secret during TOTP enrollment (single host account).
  String? _pendingTotpSecret;

  // ── Account lifecycle ───────────────────────────────────────────────────

  /// True when no account exists yet — the server runs in setup mode.
  Future<bool> isSetupRequired() async => (await _loadCredentials()) == null;

  /// Create the single account. Fails if one already exists or input is invalid.
  Future<bool> setupAccount(String username, String password) async {
    if (!await isSetupRequired()) return false;
    final u = username.trim();
    if (u.isEmpty || password.length < 8) return false;
    final hash = await _hasher.hash(password);
    final nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.customInsert(
      'INSERT INTO web_auth_credentials '
      '(id, username, password_hash, totp_secret, totp_enabled, recovery_codes, created_at, updated_at) '
      'VALUES (?, ?, ?, NULL, 0, NULL, ?, ?)',
      variables: [
        Variable<String>(_accountId),
        Variable<String>(u),
        Variable<String>(hash),
        Variable<int>(nowSecs),
        Variable<int>(nowSecs),
      ],
    );
    return true;
  }

  // ── Login / logout ──────────────────────────────────────────────────────

  /// Authenticate and (on success) mint a session token for the cookie.
  Future<LoginResult> login(
    String username,
    String password, {
    String? totpCode,
    String? ip,
    String? userAgent,
  }) async {
    final creds = await _loadCredentials();
    if (creds == null) return const LoginResult(LoginStatus.notSetUp);

    final u = username.trim();
    if (!_limiter.ipAllowed(ip)) {
      return const LoginResult(LoginStatus.rateLimited, retryAfterSeconds: 300);
    }
    final lock = _limiter.lockoutFor(u);
    if (lock != null) {
      return LoginResult(
        LoginStatus.lockedOut,
        retryAfterSeconds: lock.inSeconds + 1,
      );
    }

    final passwordOk = u == creds.username &&
        await _hasher.verify(password, creds.passwordHash);
    if (!passwordOk) {
      _limiter.recordFailure(u, ip);
      // Generic, slightly delayed response (Argon2 cost already dominates).
      return const LoginResult(LoginStatus.invalidCredentials);
    }

    if (creds.totpEnabled) {
      final code = totpCode?.trim() ?? '';
      if (code.isEmpty) return const LoginResult(LoginStatus.totpRequired);
      final secret = creds.totpSecret;
      final accepted = (secret != null && _totp.verify(secret, code)) ||
          await _consumeRecoveryCode(creds, code);
      if (!accepted) {
        _limiter.recordFailure(u, ip);
        return const LoginResult(LoginStatus.totpRequired);
      }
    }

    _limiter.recordSuccess(u);
    final token = await sessions.create(
      creds.id,
      ip: ip,
      userAgent: userAgent,
    );
    return LoginResult(LoginStatus.success, token: token);
  }

  Future<void> logout(String rawToken) => sessions.revoke(rawToken);

  // ── TOTP enrollment ───────────────────────────────────────────────────────

  /// Start enrollment: returns a fresh secret + provisioning URI for the QR.
  /// Not persisted until [confirmTotpEnrollment] succeeds.
  Future<TotpEnrollment?> beginTotpEnrollment() async {
    final creds = await _loadCredentials();
    if (creds == null) return null;
    final secret = _totp.generateSecret();
    _pendingTotpSecret = secret;
    return TotpEnrollment(secret, _totp.provisioningUri(creds.username, secret));
  }

  /// Confirm enrollment with a current code. On success persists the secret,
  /// enables 2FA, and returns the one-time recovery codes (plaintext).
  Future<List<String>?> confirmTotpEnrollment(String code) async {
    final secret = _pendingTotpSecret;
    if (secret == null || !_totp.verify(secret, code)) return null;
    final recovery = List.generate(_recoveryCodeCount, (_) => _recoveryCode());
    final hashed = <String>[];
    for (final c in recovery) {
      // Hash the normalized (dash-less, lowercase) form so the user can type the
      // displayed code with or without its separator. Display keeps the dash.
      hashed.add(await _hasher.hash(c.replaceAll('-', '').toLowerCase()));
    }
    await _db.customStatement(
      'UPDATE web_auth_credentials SET totp_secret = ?, totp_enabled = 1, '
      'recovery_codes = ?, updated_at = ? WHERE id = ?',
      [
        secret,
        jsonEncode(hashed),
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        _accountId,
      ],
    );
    _pendingTotpSecret = null;
    return recovery;
  }

  /// Disable 2FA, clearing the secret and recovery codes.
  Future<void> disableTotp() async {
    _pendingTotpSecret = null;
    await _db.customStatement(
      'UPDATE web_auth_credentials SET totp_secret = NULL, totp_enabled = 0, '
      'recovery_codes = NULL, updated_at = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch ~/ 1000, _accountId],
    );
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<WebAuthCredential?> _loadCredentials() async {
    final rows = await _db.customSelect(
      'SELECT * FROM web_auth_credentials WHERE id = ? LIMIT 1',
      variables: [Variable<String>(_accountId)],
    ).get();
    if (rows.isEmpty) return null;
    final d = rows.first.data;
    return WebAuthCredential(
      id: d['id'] as String,
      username: d['username'] as String,
      passwordHash: d['password_hash'] as String,
      totpSecret: d['totp_secret'] as String?,
      totpEnabled: (d['totp_enabled'] as int? ?? 0) != 0,
      recoveryCodes: d['recovery_codes'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (d['created_at'] as int? ?? 0) * 1000,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (d['updated_at'] as int? ?? 0) * 1000,
      ),
    );
  }

  /// Verify [code] against stored recovery-code hashes; consume it on match.
  Future<bool> _consumeRecoveryCode(WebAuthCredential creds, String code) async {
    final raw = creds.recoveryCodes;
    if (raw == null || raw.isEmpty) return false;
    final normalized = code.replaceAll('-', '').toLowerCase().trim();
    List<dynamic> hashes;
    try {
      hashes = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return false;
    }
    for (var i = 0; i < hashes.length; i++) {
      if (await _hasher.verify(normalized, hashes[i] as String)) {
        hashes.removeAt(i);
        await _db.customStatement(
          'UPDATE web_auth_credentials SET recovery_codes = ?, updated_at = ? WHERE id = ?',
          [
            jsonEncode(hashes),
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
            _accountId,
          ],
        );
        return true;
      }
    }
    return false;
  }

  String _recoveryCode() {
    const alphabet = 'abcdefghijkmnpqrstuvwxyz23456789'; // no ambiguous chars
    final rng = Random.secure();
    String chunk() =>
        List.generate(5, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
    return '${chunk()}-${chunk()}';
  }
}
