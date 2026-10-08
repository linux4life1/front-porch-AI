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

/// A saved SuperGrok session. [expiresAt] is when [accessToken] stops
/// working; [refreshToken] buys a new one.
class XaiTokens {
  const XaiTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.email,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  /// From the id token, for "Signed in as …". Null when xAI sent none.
  final String? email;

  /// Refresh a little early so a long generation does not start on a token
  /// that dies mid-stream.
  static const refreshMargin = Duration(minutes: 2);

  bool needsRefresh([DateTime? now]) =>
      !(now ?? DateTime.now()).isBefore(expiresAt.subtract(refreshMargin));

  /// Parse an OAuth token response. A refresh may omit the refresh token or
  /// the id token; [previous] fills those gaps.
  factory XaiTokens.fromTokenResponse(
    Map<String, dynamic> body, {
    XaiTokens? previous,
    DateTime? now,
  }) {
    final seconds = body['expires_in'];
    final lifetime = seconds is num && seconds > 0 ? seconds.toInt() : 3600;
    final refresh = body['refresh_token']?.toString() ?? '';
    return XaiTokens(
      accessToken: body['access_token'].toString(),
      refreshToken: refresh.isNotEmpty
          ? refresh
          : (previous?.refreshToken ?? ''),
      expiresAt: (now ?? DateTime.now()).add(Duration(seconds: lifetime)),
      email: emailFromIdToken(body['id_token']?.toString()) ?? previous?.email,
    );
  }

  Map<String, dynamic> toJson() => {
    'access': accessToken,
    'refresh': refreshToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (email != null) 'email': email,
  };

  String encode() => jsonEncode(toJson());

  /// Null for a missing or unreadable record — never throws on bad prefs.
  static XaiTokens? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final access = m['access']?.toString() ?? '';
      final refresh = m['refresh']?.toString() ?? '';
      final expires = DateTime.tryParse(m['expiresAt']?.toString() ?? '');
      if (access.isEmpty || refresh.isEmpty || expires == null) return null;
      return XaiTokens(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: expires,
        email: m['email']?.toString(),
      );
    } on FormatException {
      return null;
    }
  }

  /// The `email` claim of a JWT id token. Display only — not verified.
  static String? emailFromIdToken(String? idToken) {
    final parts = idToken?.split('.') ?? const [];
    if (parts.length < 2) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final claims = jsonDecode(payload);
      final email = claims is Map ? claims['email']?.toString() : null;
      return (email == null || email.isEmpty) ? null : email;
    } on FormatException {
      return null;
    }
  }
}
