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
import 'package:flutter/foundation.dart' show ValueNotifier;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/web/auth/auth_types.dart';
import 'package:front_porch_ai/services/web/auth/password_hasher.dart';
import 'package:front_porch_ai/services/web/auth/rate_limiter.dart';
import 'package:front_porch_ai/services/web/auth/session_store.dart';
import 'package:front_porch_ai/services/web/auth/setup_gate.dart';
import 'package:front_porch_ai/services/web/auth/totp_service.dart';

export 'package:front_porch_ai/services/web/auth/auth_types.dart';

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

  /// One-time token for non-local first-run setup. Never served over HTTP —
  /// desktop Settings shows it while setup is open.
  String? _setupToken;

  /// Ticks when the account is created or removed, or its username or 2FA
  /// changes, so desktop Settings redraws a login made from a phone.
  final ValueNotifier<int> accountChanges = ValueNotifier<int>(0);

  void _accountChanged() => accountChanges.value++;

  // ── Account lifecycle ───────────────────────────────────────────────────

  /// True when no account exists yet — the server runs in setup mode.
  Future<bool> isSetupRequired() async => (await _loadCredentials()) == null;

  /// Desktop-only setup claim code while no account exists. Null once setup
  /// completes. Lazy-minted so a fresh install always has something to show
  /// after "Reset web login" or first server start with no credentials.
  Future<String?> setupTokenForDesktop() async {
    if (!await isSetupRequired()) {
      _setupToken = null;
      return null;
    }
    return _setupToken ??= SetupGate.generateToken();
  }

  /// The account's public bits for display (web account page, desktop
  /// settings card). Null when no account exists yet.
  Future<({String username, bool totpEnabled})?> accountInfo() async {
    final creds = await _loadCredentials();
    if (creds == null) return null;
    return (username: creds.username, totpEnabled: creds.totpEnabled);
  }

  /// Create the single account. Local (direct loopback) clients need no token;
  /// LAN/proxy clients must supply [setupToken] matching the desktop value.
  Future<SetupStatus> setupAccount(
    String username,
    String password, {
    String? setupToken,
    bool isDirectLoopbackClient = false,
    String? ip,
  }) async {
    if (!await isSetupRequired()) return SetupStatus.alreadyConfigured;
    if (!_limiter.setupIpAllowed(ip)) return SetupStatus.rateLimited;
    _limiter.recordSetupAttempt(ip);

    if (!isDirectLoopbackClient) {
      await setupTokenForDesktop();
      if (!SetupGate.tokensMatch(setupToken, _setupToken)) {
        // Empty token from a remote client is "required", wrong token is invalid.
        final blank = setupToken == null || setupToken.trim().isEmpty;
        return blank ? SetupStatus.tokenRequired : SetupStatus.invalidToken;
      }
    }

    final u = username.trim();
    if (u.isEmpty || password.length < 8) return SetupStatus.invalidInput;
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
    _setupToken = null;
    _accountChanged();
    return SetupStatus.success;
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

  /// Password (+ TOTP when enabled) step-up for privileged operations that
  /// a stolen session cookie alone must not perform — e.g. publishing a
  /// public tunnel (audit P0.6). Returns [CredentialChangeStatus.success]
  /// when re-auth passes.
  Future<CredentialChangeStatus> verifyStepUp({
    required String currentPassword,
    String? totpCode,
    String? ip,
  }) async {
    final creds = await _loadCredentials();
    if (creds == null) return CredentialChangeStatus.notSetUp;
    final denied = await _reauthenticate(creds, currentPassword, totpCode, ip);
    if (denied != null) return denied;
    _limiter.recordSuccess(creds.username);
    return CredentialChangeStatus.success;
  }

  // ── Credential management ─────────────────────────────────────────────────

  /// Change the username and/or password. Requires the CURRENT password (and,
  /// with 2FA on, a current code) even from a signed-in session, so a stolen
  /// device with a live cookie cannot take the account over. Failed attempts
  /// feed the same lockout as login, so this endpoint can't be used to
  /// brute-force the current password from a hijacked session.
  Future<CredentialChangeStatus> changeCredentials({
    required String currentPassword,
    String? totpCode,
    String? newUsername,
    String? newPassword,
    String? ip,
  }) async {
    final creds = await _loadCredentials();
    if (creds == null) return CredentialChangeStatus.notSetUp;
    final denied = await _reauthenticate(creds, currentPassword, totpCode, ip);
    if (denied != null) return denied;

    final u = newUsername?.trim() ?? '';
    final p = newPassword ?? '';
    if (u.isEmpty && p.isEmpty) return CredentialChangeStatus.invalidInput;
    if (p.isNotEmpty && p.length < 8) return CredentialChangeStatus.invalidInput;

    await _db.customStatement(
      'UPDATE web_auth_credentials SET username = ?, password_hash = ?, '
      'updated_at = ? WHERE id = ?',
      [
        u.isEmpty ? creds.username : u,
        p.isEmpty ? creds.passwordHash : await _hasher.hash(p),
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        _accountId,
      ],
    );
    _limiter.recordSuccess(creds.username);
    _accountChanged();
    return CredentialChangeStatus.success;
  }

  /// Log out every signed-in web device (desktop settings "Sign out all").
  Future<void> signOutAllDevices() => sessions.revokeAllFor(_accountId);

  /// Wipe the account and every session, returning the server to first-run
  /// setup mode. Desktop-only recovery: whoever sits at the desktop already
  /// owns the database, so local access is strictly a stronger credential
  /// than the web password — this is the "forgot password" path.
  Future<void> resetAccount() async {
    _pendingTotpSecret = null;
    // Fresh token so a prior leak cannot reclaim after reset.
    _setupToken = SetupGate.generateToken();
    await sessions.revokeAllFor(_accountId);
    await _db.customStatement(
      'DELETE FROM web_auth_credentials WHERE id = ?',
      [_accountId],
    );
    _accountChanged();
  }

  // ── TOTP enrollment ───────────────────────────────────────────────────────

  /// Start enrollment: returns a fresh secret + provisioning URI for the QR.
  /// Not persisted until [confirmTotpEnrollment] succeeds.
  ///
  /// Requires the current password (same step-up as credential change /
  /// disable). A session cookie alone must not mint a new secret — that is
  /// how a hijacker replaces the owner's authenticator and recovery codes.
  /// If 2FA is already on, enrollment is refused entirely; disable first.
  Future<TotpBeginResult> beginTotpEnrollment({
    required String currentPassword,
    String? totpCode,
    String? ip,
  }) async {
    final creds = await _loadCredentials();
    if (creds == null) {
      return const TotpBeginResult(CredentialChangeStatus.notSetUp);
    }
    if (creds.totpEnabled) {
      return const TotpBeginResult(CredentialChangeStatus.alreadyEnabled);
    }
    final denied = await _reauthenticate(creds, currentPassword, totpCode, ip);
    if (denied != null) return TotpBeginResult(denied);
    final secret = _totp.generateSecret();
    _pendingTotpSecret = secret;
    _limiter.recordSuccess(creds.username);
    return TotpBeginResult(
      CredentialChangeStatus.success,
      enrollment: TotpEnrollment(
        secret,
        _totp.provisioningUri(creds.username, secret),
      ),
    );
  }

  /// Confirm enrollment with a current authenticator code. On success persists
  /// the secret, enables 2FA, and returns the one-time recovery codes
  /// (plaintext). Re-checks the current password so a hijacked session that
  /// did not know the password still cannot complete enrollment if begin was
  /// never reached (and cannot complete a race if begin somehow leaked).
  Future<TotpConfirmResult> confirmTotpEnrollment({
    required String currentPassword,
    required String code,
    String? totpCode,
    String? ip,
  }) async {
    final creds = await _loadCredentials();
    if (creds == null) {
      return const TotpConfirmResult(CredentialChangeStatus.notSetUp);
    }
    if (creds.totpEnabled) {
      _pendingTotpSecret = null;
      return const TotpConfirmResult(CredentialChangeStatus.alreadyEnabled);
    }
    final denied = await _reauthenticate(creds, currentPassword, totpCode, ip);
    if (denied != null) return TotpConfirmResult(denied);

    final secret = _pendingTotpSecret;
    if (secret == null || !_totp.verify(secret, code)) {
      return const TotpConfirmResult(CredentialChangeStatus.invalidInput);
    }
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
    _limiter.recordSuccess(creds.username);
    _accountChanged();
    return TotpConfirmResult(
      CredentialChangeStatus.success,
      recoveryCodes: recovery,
    );
  }

  /// Disable 2FA, clearing the secret and recovery codes. Requires the
  /// current password + a current code (same re-auth policy as
  /// [changeCredentials]) so a hijacked session can't silently strip the
  /// second factor.
  Future<CredentialChangeStatus> disableTotp({
    required String currentPassword,
    String? totpCode,
    String? ip,
  }) async {
    final creds = await _loadCredentials();
    if (creds == null) return CredentialChangeStatus.notSetUp;
    final denied = await _reauthenticate(creds, currentPassword, totpCode, ip);
    if (denied != null) return denied;
    _pendingTotpSecret = null;
    await _db.customStatement(
      'UPDATE web_auth_credentials SET totp_secret = NULL, totp_enabled = 0, '
      'recovery_codes = NULL, updated_at = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch ~/ 1000, _accountId],
    );
    _limiter.recordSuccess(creds.username);
    _accountChanged();
    return CredentialChangeStatus.success;
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  /// Shared "sudo mode" gate for credential operations: verify the current
  /// password and, when 2FA is on, a current TOTP or recovery code. Failures
  /// count toward the login lockout. Returns null when re-auth passes, else
  /// the status to surface.
  Future<CredentialChangeStatus?> _reauthenticate(
    WebAuthCredential creds,
    String currentPassword,
    String? totpCode,
    String? ip,
  ) async {
    if (!_limiter.ipAllowed(ip) || _limiter.lockoutFor(creds.username) != null) {
      return CredentialChangeStatus.lockedOut;
    }
    if (!await _hasher.verify(currentPassword, creds.passwordHash)) {
      _limiter.recordFailure(creds.username, ip);
      return CredentialChangeStatus.invalidCurrentPassword;
    }
    if (creds.totpEnabled) {
      final code = totpCode?.trim() ?? '';
      final secret = creds.totpSecret;
      final accepted = code.isNotEmpty &&
          ((secret != null && _totp.verify(secret, code)) ||
              await _consumeRecoveryCode(creds, code));
      if (!accepted) {
        if (code.isNotEmpty) _limiter.recordFailure(creds.username, ip);
        return CredentialChangeStatus.totpRequired;
      }
    }
    return null;
  }

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
