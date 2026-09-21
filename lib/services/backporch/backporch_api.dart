// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'backporch_user.dart';
import 'stoop_character.dart';
import 'stoop_card.dart';
import 'stoop_creator.dart';
import 'stoop_message.dart';

part 'backporch_api.account.dart';
part 'backporch_api.catalog.dart';

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

/// Thin HTTP client for the Front Porch repository server. Stateless — callers
/// pass the access token where a request needs one. Uses the same `http.Client`
/// pattern as the rest of the app's network services.
class BackporchApi {
  BackporchApi({String? baseUrl})
    : baseUrl = baseUrl ?? overrideBaseUrl ?? defaultBaseUrl;

  /// The live server. Overridable for local development against a dev backend
  /// via `--dart-define=BACKPORCH_BASE_URL=http://localhost:8090`.
  static const String defaultBaseUrl = String.fromEnvironment(
    'BACKPORCH_BASE_URL',
    defaultValue: 'https://api.frontporchai.app',
  );

  /// Runtime seam over [defaultBaseUrl]. The desktop UI constructs bare
  /// `BackporchApi()` at every call site, and the dart-define above is
  /// compile-time only — CI's E2E runner passes no defines, so without this
  /// a Stoop suite would talk to the LIVE server. The E2E suite points this
  /// at its fake before boot; an explicit constructor [baseUrl] still wins.
  @visibleForTesting
  static String? overrideBaseUrl;

  final String baseUrl;

  Future<AuthResult> refresh(String refreshToken) async {
    final json = await _post('/auth/refresh', {'refreshToken': refreshToken});
    return _authResult(json);
  }

  Future<({BackporchUser user, String policyVersion})> me(
    String accessToken,
  ) async {
    return _meResult(await _get('/auth/me', accessToken));
  }

  AuthResult _authResult(Map<String, dynamic> json) => AuthResult(
    user: BackporchUser.fromJson(json['user'] as Map<String, dynamic>),
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    policyVersion: json['policyVersion'] as String? ?? '',
  );

  ({BackporchUser user, String policyVersion}) _meResult(
    Map<String, dynamic> json,
  ) => (
    user: BackporchUser.fromJson(json['user'] as Map<String, dynamic>),
    policyVersion: json['policyVersion'] as String? ?? '',
  );

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final client = http.Client();
    try {
      final res = await client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _parse(res);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _get(String path, String token) async {
    final client = http.Client();
    try {
      final res = await client
          .get(
            Uri.parse('$baseUrl$path'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      return _parse(res);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final client = http.Client();
    try {
      final res = await client
          .patch(
            Uri.parse('$baseUrl$path'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _parse(res);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _delete(String path, String token) async {
    final client = http.Client();
    try {
      final res = await client
          .delete(
            Uri.parse('$baseUrl$path'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      return _parse(res);
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _parse(http.Response res) {
    Map<String, dynamic> json = <String, dynamic>{};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {
        // Non-JSON body (e.g. a proxy error page) — fall through to status code.
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json;
    throw BackporchApiException(
      res.statusCode,
      (json['error'] as String?) ?? 'http_${res.statusCode}',
      (json['detail'] as String?)?.trim().isNotEmpty == true
          ? (json['detail'] as String).trim()
          : null,
    );
  }
}
