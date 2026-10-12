// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/backporch/api/backporch_api_types.dart';
import 'package:front_porch_ai/services/backporch/api/backporch_transport.dart';
import 'package:front_porch_ai/services/backporch/backporch_user.dart';

/// Account, sign-in, 2FA and profile endpoints. [BackporchApi] forwards here.
class BackporchAccountApi {
  BackporchAccountApi(this._t);

  final BackporchTransport _t;

  Future<AuthResult> signup({
    required String email,
    required String password,
    required String displayName,
    required DateTime dateOfBirth,
    String? installId,
  }) async {
    final json = await _t.post('/auth/signup', {
      'email': email,
      'password': password,
      'displayName': displayName,
      'dateOfBirth': dateOfBirth.toUtc().toIso8601String(),
      'installId': ?installId,
    });
    return parseAuthResult(json);
  }

  Future<AuthResult> login({
    required String email,
    required String password,
    String? installId,
    String? totp,
  }) async {
    final json = await _t.post('/auth/login', {
      'email': email,
      'password': password,
      'installId': ?installId,
      'totp': ?totp,
    });
    return parseAuthResult(json);
  }

  Future<({String secret, String otpauthUrl, String qrDataUrl})> twoFactorSetup(
    String accessToken,
  ) async {
    final json = await _t.post('/2fa/setup', const {}, token: accessToken);
    return (
      secret: (json['secret'] ?? '').toString(),
      otpauthUrl: (json['otpauthUrl'] ?? '').toString(),
      qrDataUrl: (json['qrDataUrl'] ?? '').toString(),
    );
  }

  Future<void> twoFactorEnable(String accessToken, String totp) async {
    await _t.post('/2fa/enable', {'totp': totp}, token: accessToken);
  }

  Future<void> twoFactorDisable(String accessToken, String totp) async {
    await _t.post('/2fa/disable', {'totp': totp}, token: accessToken);
  }

  Future<({BackporchUser user, String policyVersion})> acceptPolicy(
    String accessToken,
    String version,
  ) async {
    final json = await _t.post('/auth/accept-policy', {
      'version': version,
    }, token: accessToken);
    return parseMeResult(json);
  }

  Future<({BackporchUser user, String policyVersion})> setDisplayName(
    String accessToken,
    String displayName,
  ) async {
    final json = await _t.post('/auth/display-name', {
      'displayName': displayName,
    }, token: accessToken);
    return parseMeResult(json);
  }

  Future<({BackporchUser user, String policyVersion})> setNsfwEnabled(
    String accessToken,
    bool enabled,
  ) async {
    final json = await _t.post('/auth/nsfw', {
      'enabled': enabled,
    }, token: accessToken);
    return parseMeResult(json);
  }

  Future<({BackporchUser user, String policyVersion})> updateProfile(
    String accessToken, {
    required String bio,
    required List<String> links,
  }) async {
    final json = await _t.post('/me/profile', {
      'bio': bio,
      'links': links,
    }, token: accessToken);
    return parseMeResult(json);
  }

  Future<({BackporchUser user, String policyVersion})> uploadAvatar({
    required String accessToken,
    required Uint8List bytes,
    required String filename,
  }) async {
    final req =
        http.MultipartRequest('POST', Uri.parse('${_t.baseUrl}/me/avatar'))
          ..headers['Authorization'] = 'Bearer $accessToken'
          ..files.add(
            http.MultipartFile.fromBytes('avatar', bytes, filename: filename),
          );
    final res = await http.Response.fromStream(
      await req.send().timeout(const Duration(seconds: 60)),
    );
    return parseMeResult(_t.parse(res));
  }

  Future<({BackporchUser user, String policyVersion})> deleteAvatar(
    String accessToken,
  ) async {
    return parseMeResult(await _t.delete('/me/avatar', accessToken));
  }

  Future<({BackporchUser user, String policyVersion})> changeEmail(
    String accessToken, {
    required String newEmail,
    String? password,
    String? totp,
  }) async {
    final json = await _t.post('/auth/change-email', {
      'newEmail': newEmail,
      'password': ?password,
      'totp': ?totp,
    }, token: accessToken);
    return parseMeResult(json);
  }

  Future<({BackporchUser user, String policyVersion})> cancelEmailChange(
    String accessToken,
  ) async {
    return parseMeResult(await _t.delete('/auth/change-email', accessToken));
  }

  Future<void> forgotPassword(String email) async {
    await _t.post('/auth/forgot', {'email': email});
  }

  Future<void> deleteCharacter(String accessToken, String id) async {
    await _t.delete('/characters/$id', accessToken);
  }

  Future<void> deleteAccount(String accessToken) async {
    await _t.delete('/auth/me', accessToken);
  }

  Future<void> sendAppPing({
    required String accessToken,
    required Map<String, dynamic> payload,
  }) async {
    await _t.post('/me/app-ping', payload, token: accessToken);
  }

  Future<void> resendVerification(String accessToken) async {
    await _t.post('/auth/resend-verification', const {}, token: accessToken);
  }

  Future<void> logout(String? refreshToken) async {
    final body = <String, dynamic>{};
    if (refreshToken != null) body['refreshToken'] = refreshToken;
    try {
      await _t.post('/auth/logout', body);
    } catch (_) {
      // The local session is cleared regardless of whether the server is
      // reachable, so a failed logout call is non-fatal.
    }
  }
}
