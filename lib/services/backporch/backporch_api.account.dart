// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

part of 'backporch_api.dart';

extension BackporchApiAccount on BackporchApi {
  Future<AuthResult> signup({
    required String email,
    required String password,
    required String displayName,
    required DateTime dateOfBirth,
    String? installId,
  }) async {
    final json = await _post('/auth/signup', {
      'email': email,
      'password': password,
      'displayName': displayName,
      'dateOfBirth': dateOfBirth.toUtc().toIso8601String(),
      'installId': ?installId,
    });
    return _authResult(json);
  }

  Future<AuthResult> login({
    required String email,
    required String password,
    String? installId,
    String? totp,
  }) async {
    final json = await _post('/auth/login', {
      'email': email,
      'password': password,
      'installId': ?installId,
      'totp': ?totp,
    });
    return _authResult(json);
  }

  /// Begin authenticator (TOTP) enrollment. Returns the shared secret, the
  /// otpauth:// URI, and a ready-to-show QR image (a `data:image/png;base64,…`
  /// URL). The secret is stored server-side but stays inactive until [confirm].
  Future<({String secret, String otpauthUrl, String qrDataUrl})> twoFactorSetup(
    String accessToken,
  ) async {
    final json = await _post('/2fa/setup', const {}, token: accessToken);
    return (
      secret: (json['secret'] ?? '').toString(),
      otpauthUrl: (json['otpauthUrl'] ?? '').toString(),
      qrDataUrl: (json['qrDataUrl'] ?? '').toString(),
    );
  }

  /// Confirm a code to switch 2FA on. Throws `invalid_code` on a wrong code.
  Future<void> twoFactorEnable(String accessToken, String totp) async {
    await _post('/2fa/enable', {'totp': totp}, token: accessToken);
  }

  /// Turn 2FA off — requires a current code. Throws `invalid_code` if wrong.
  Future<void> twoFactorDisable(String accessToken, String totp) async {
    await _post('/2fa/disable', {'totp': totp}, token: accessToken);
  }

  Future<({BackporchUser user, String policyVersion})> acceptPolicy(
    String accessToken,
    String version,
  ) async {
    final json = await _post('/auth/accept-policy', {
      'version': version,
    }, token: accessToken);
    return _meResult(json);
  }

  /// Change the public display name. Returns the refreshed account.
  Future<({BackporchUser user, String policyVersion})> setDisplayName(
    String accessToken,
    String displayName,
  ) async {
    final json = await _post('/auth/display-name', {
      'displayName': displayName,
    }, token: accessToken);
    return _meResult(json);
  }

  /// Set the NSFW content preference. Returns the refreshed account.
  Future<({BackporchUser user, String policyVersion})> setNsfwEnabled(
    String accessToken,
    bool enabled,
  ) async {
    final json = await _post('/auth/nsfw', {
      'enabled': enabled,
    }, token: accessToken);
    return _meResult(json);
  }

  /// Edit the public creator profile (bio ≤ 300 chars, up to 4 http(s) links).
  /// Returns the refreshed account.
  Future<({BackporchUser user, String policyVersion})> updateProfile(
    String accessToken, {
    required String bio,
    required List<String> links,
  }) async {
    final json = await _post('/me/profile', {
      'bio': bio,
      'links': links,
    }, token: accessToken);
    return _meResult(json);
  }

  /// Upload a profile picture. Live instantly (post-moderated); requires a
  /// verified email. Throws `email_not_verified` / `avatar_locked` /
  /// `unsupported_image_type` for the UI to explain.
  Future<({BackporchUser user, String policyVersion})> uploadAvatar({
    required String accessToken,
    required Uint8List bytes,
    required String filename,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/me/avatar'))
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..files.add(
        http.MultipartFile.fromBytes('avatar', bytes, filename: filename),
      );
    final res = await http.Response.fromStream(
      await req.send().timeout(const Duration(seconds: 60)),
    );
    return _meResult(_parse(res));
  }

  /// Remove the profile picture (always allowed, instant).
  Future<({BackporchUser user, String policyVersion})> deleteAvatar(
    String accessToken,
  ) async {
    return _meResult(await _delete('/me/avatar', accessToken));
  }

  /// Ask to change the account's sign-in email. The change only lands when
  /// the NEW address clicks its confirmation link; until then it shows as
  /// `user.pendingEmail`. Requires the current password (when one exists) and
  /// the TOTP code when 2FA is on. Throws `email_taken`, `same_email`,
  /// `wrong_password`, `two_factor_required`, or `resend_too_soon`.
  Future<({BackporchUser user, String policyVersion})> changeEmail(
    String accessToken, {
    required String newEmail,
    String? password,
    String? totp,
  }) async {
    final json = await _post('/auth/change-email', {
      'newEmail': newEmail,
      'password': ?password,
      'totp': ?totp,
    }, token: accessToken);
    return _meResult(json);
  }

  /// Abandon a pending email change (nothing was ever committed).
  Future<({BackporchUser user, String policyVersion})> cancelEmailChange(
    String accessToken,
  ) async {
    return _meResult(await _delete('/auth/change-email', accessToken));
  }

  /// Ask for a password-reset email. The server always answers ok (it never
  /// reveals whether the address has an account); the emailed link opens the
  /// hub's reset page.
  Future<void> forgotPassword(String email) async {
    await _post('/auth/forgot', {'email': email});
  }

  /// Delete one of the signed-in user's own uploads from The Stoop (owner-only
  /// server-side). Existing downloaders keep their copies.
  Future<void> deleteCharacter(String accessToken, String id) async {
    await _delete('/characters/$id', accessToken);
  }

  /// Permanently delete the signed-in account (GDPR erasure). Throws on failure.
  Future<void> deleteAccount(String accessToken) async {
    await _delete('/auth/me', accessToken);
  }

  /// Send an anonymous, opt-out device ping (platform / OS / app version /
  /// locale / GPU name + VRAM). The server upserts one row per install, buckets
  /// the GPU into a coarse tier, and returns 204. Fire-and-forget for callers.
  Future<void> sendAppPing({
    required String accessToken,
    required Map<String, dynamic> payload,
  }) async {
    await _post('/me/app-ping', payload, token: accessToken);
  }

  /// Ask for another email-confirmation link. Throws `resend_too_soon` when
  /// one was sent within the last couple of minutes.
  Future<void> resendVerification(String accessToken) async {
    await _post('/auth/resend-verification', const {}, token: accessToken);
  }

  /// Best-effort: revokes the server session. Never throws.
  Future<void> logout(String? refreshToken) async {
    final body = <String, dynamic>{};
    if (refreshToken != null) body['refreshToken'] = refreshToken;
    try {
      await _post('/auth/logout', body);
    } catch (_) {
      // The local session is cleared regardless of whether the server is
      // reachable, so a failed logout call is non-fatal.
    }
  }
}
