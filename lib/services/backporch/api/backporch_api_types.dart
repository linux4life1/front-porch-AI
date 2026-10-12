// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:front_porch_ai/services/backporch/backporch_user.dart';

/// Thrown on any non-2xx response. [code] is the server's machine-readable
/// `error` field (e.g. `invalid_credentials`, `email_taken`, `underage`) so the
/// UI can show a friendly, specific message. [detail] is an optional human
/// sentence from the server (e.g. incomplete_card missing fields list).
class BackporchApiException implements Exception {
  final int statusCode;
  final String code;
  final String? detail;
  const BackporchApiException(this.statusCode, this.code, [this.detail]);

  @override
  String toString() =>
      'BackporchApiException($statusCode, $code${detail != null ? ', $detail' : ''})';
}

/// A successful authentication: the account, its session tokens, and the live
/// AUP version (so the client can tell whether the policy gate is due).
class AuthResult {
  final BackporchUser user;
  final String accessToken;
  final String refreshToken;
  final String policyVersion;
  const AuthResult({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.policyVersion,
  });
}

AuthResult parseAuthResult(Map<String, dynamic> json) => AuthResult(
  user: BackporchUser.fromJson(json['user'] as Map<String, dynamic>),
  accessToken: json['accessToken'] as String,
  refreshToken: json['refreshToken'] as String,
  policyVersion: json['policyVersion'] as String? ?? '',
);

({BackporchUser user, String policyVersion}) parseMeResult(
  Map<String, dynamic> json,
) => (
  user: BackporchUser.fromJson(json['user'] as Map<String, dynamic>),
  policyVersion: json['policyVersion'] as String? ?? '',
);

/// Server path for a card asset. [thumb] is the postcard-sized WebP the hub
/// shows on tiles (`?v=thumb`); without it the server returns the original.
/// One builder so the desktop client and the web relay ask for the same URL.
String stoopAssetPath(String assetId, {bool thumb = false}) =>
    '/assets/${Uri.encodeComponent(assetId)}/raw${thumb ? '?v=thumb' : ''}';
