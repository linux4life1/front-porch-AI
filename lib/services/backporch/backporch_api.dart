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
import 'package:http/http.dart' as http;

import 'backporch_user.dart';
import 'stoop_character.dart';
import 'stoop_card.dart';
import 'stoop_creator.dart';
import 'stoop_message.dart';

/// Thrown on any non-2xx response. [code] is the server's machine-readable
/// `error` field (e.g. `invalid_credentials`, `email_taken`, `underage`) so the
/// UI can show a friendly, specific message.
class BackporchApiException implements Exception {
  final int statusCode;
  final String code;
  const BackporchApiException(this.statusCode, this.code);

  @override
  String toString() => 'BackporchApiException($statusCode, $code)';
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
  BackporchApi({String? baseUrl}) : baseUrl = baseUrl ?? defaultBaseUrl;

  /// The live server. Overridable for local development against a dev backend
  /// via `--dart-define=BACKPORCH_BASE_URL=http://localhost:8090`.
  static const String defaultBaseUrl = String.fromEnvironment(
    'BACKPORCH_BASE_URL',
    defaultValue: 'https://api.frontporchai.app',
  );
  final String baseUrl;

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
  Future<({String secret, String otpauthUrl, String qrDataUrl})>
  twoFactorSetup(String accessToken) async {
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

  Future<AuthResult> refresh(String refreshToken) async {
    final json = await _post('/auth/refresh', {'refreshToken': refreshToken});
    return _authResult(json);
  }

  /// Record agreement to the live AUP [version]. Returns the refreshed account.
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

  /// Upload a character card (the V2 [card] JSON + an avatar image) to The
  /// Stoop. Lands in the moderation queue as PENDING. Returns its id + status.
  Future<({String id, String status})> uploadCharacter({
    required String accessToken,
    required Map<String, dynamic> payload,
    required Uint8List avatarBytes,
    required String avatarFilename,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/characters'))
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..fields['payload'] = jsonEncode(payload)
      ..files.add(
        http.MultipartFile.fromBytes(
          'avatar',
          avatarBytes,
          filename: avatarFilename,
        ),
      );
    final res = await http.Response.fromStream(
      await req.send().timeout(const Duration(seconds: 60)),
    );
    final json = _parse(res);
    return (
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING',
    );
  }

  /// Publish a new version of an existing character IN PLACE (owner only). Keeps
  /// the Stoop id, downloads, score, and votes; re-enters the moderation queue.
  /// Used by the Mine-tab "Update" flow.
  Future<({String id, int version, String status})> publishVersion({
    required String accessToken,
    required String characterId,
    required Map<String, dynamic> payload,
    required Uint8List avatarBytes,
    required String avatarFilename,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/characters/$characterId/versions'),
    )
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..fields['payload'] = jsonEncode(payload)
      ..files.add(
        http.MultipartFile.fromBytes(
          'avatar',
          avatarBytes,
          filename: avatarFilename,
        ),
      );
    final res = await http.Response.fromStream(
      await req.send().timeout(const Duration(seconds: 60)),
    );
    final json = _parse(res);
    return (
      id: json['id'] as String? ?? characterId,
      version: (json['version'] as num?)?.toInt() ?? 2,
      status: json['status'] as String? ?? 'PENDING',
    );
  }

  /// The signed-in user's own uploads and their moderation status.
  Future<List<StoopCharacter>> myCharacters(String accessToken) async {
    final json = await _get('/me/characters', accessToken);
    final items = (json['items'] as List?) ?? const [];
    return items
        .map((e) => StoopCharacter.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Cards the user has downloaded before (newest first), so they can grab them
  /// again on a new device. Returns the same shape as browse items.
  Future<List<StoopCard>> myDownloads(String accessToken) async {
    final json = await _get('/me/downloads', accessToken);
    final items = (json['items'] as List?) ?? const [];
    return items
        .map((e) => StoopCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Browse / discovery ----

  /// The authenticated URL for a card asset (avatar). Load with an Authorization
  /// header — assets are served only to signed-in users, never publicly.
  String assetUrl(String assetId) => '$baseUrl/assets/$assetId/raw';

  /// Browse approved cards. [sort] is `newest`|`top`|`downloads`; [type] is
  /// `solo`|`group`|`all`. [q] supports `@creator`, `#tag`, or a name.
  Future<StoopBrowsePage> browse({
    required String accessToken,
    String sort = 'newest',
    String type = 'all',
    String? q,
    bool pick = false,
    bool following = false,
    int page = 0,
    int take = 24,
  }) async {
    final params = <String, String>{
      'sort': sort,
      'type': type,
      'page': '$page',
      'take': '$take',
      if (q != null && q.isNotEmpty) 'q': q,
      if (pick) 'pick': 'true',
      if (following) 'following': 'true',
    };
    final query = Uri(queryParameters: params).query;
    return StoopBrowsePage.fromJson(
      await _get('/characters?$query', accessToken),
    );
  }

  /// Full card detail (definitions, greetings, lorebook, tags, the caller's vote).
  Future<StoopCardDetail> cardDetail(String accessToken, String id) async {
    return StoopCardDetail.fromJson(await _get('/characters/$id', accessToken));
  }

  /// Cast a vote (1 up, -1 down, 0 clear). Returns the new score + your vote.
  Future<({int score, int myVote})> vote(
    String accessToken,
    String id,
    int value,
  ) async {
    final json = await _post('/characters/$id/vote', {
      'value': value,
    }, token: accessToken);
    return (
      score: (json['score'] as num?)?.toInt() ?? 0,
      myVote: (json['myVote'] as num?)?.toInt() ?? 0,
    );
  }

  /// Record a download and return the card payload for local import.
  Future<Map<String, dynamic>> download(String accessToken, String id) async {
    return _post('/characters/$id/download', const {}, token: accessToken);
  }

  /// Fetch a card asset's raw bytes (the avatar), for embedding on import.
  Future<Uint8List> assetBytes(String accessToken, String assetId) async {
    final client = http.Client();
    try {
      final res = await client
          .get(
            Uri.parse(assetUrl(assetId)),
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
      throw BackporchApiException(res.statusCode, 'asset_${res.statusCode}');
    } finally {
      client.close();
    }
  }

  /// File a report against a card. [category] is one of SPAM, MISLABELED,
  /// ILLEGAL, STOLEN, LOW_EFFORT, PROHIBITED_IMAGE, OTHER.
  Future<void> reportCharacter(
    String accessToken,
    String characterId, {
    required String category,
    String reason = '',
  }) async {
    await _post('/reports', {
      'characterId': characterId,
      'category': category,
      'reason': reason,
    }, token: accessToken);
  }

  /// A creator's profile + their approved cards.
  Future<StoopCreator> creatorProfile(String accessToken, String id) async {
    return StoopCreator.fromJson(await _get('/creators/$id', accessToken));
  }

  /// Follow / unfollow a creator. Returns the new follow state + follower count.
  Future<({bool following, int followers})> setFollow(
    String accessToken,
    String creatorId,
    bool follow,
  ) async {
    final json = follow
        ? await _post(
            '/creators/$creatorId/follow',
            const {},
            token: accessToken,
          )
        : await _delete('/creators/$creatorId/follow', accessToken);
    return (
      following: json['following'] as bool? ?? follow,
      followers: (json['followers'] as num?)?.toInt() ?? 0,
    );
  }

  /// The creators the signed-in user follows.
  Future<List<StoopFollowedCreator>> myFollowing(String accessToken) async {
    final json = await _get('/me/following', accessToken);
    final items = (json['items'] as List?) ?? const [];
    return items
        .map((e) => StoopFollowedCreator.fromJson(e as Map<String, dynamic>))
        .toList();
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

  Future<({BackporchUser user, String policyVersion})> me(
    String accessToken,
  ) async {
    return _meResult(await _get('/auth/me', accessToken));
  }

  // --- messaging: the user's thread with the moderation team ---

  /// The whole conversation, oldest first.
  Future<List<StoopMessage>> myMessages(String accessToken) async {
    final json = await _get('/me/messages', accessToken);
    final items = (json['items'] as List?) ?? const [];
    return items
        .map((e) => StoopMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Count of unread moderator messages (drives the notification bell badge).
  Future<int> unreadMessageCount(String accessToken) async {
    final json = await _get('/me/messages/unread', accessToken);
    return (json['count'] as num?)?.toInt() ?? 0;
  }

  /// Mark all moderator messages as read (called when the inbox opens).
  Future<void> markMessagesRead(String accessToken) async {
    await _post('/me/messages/read', const {}, token: accessToken);
  }

  /// Send a reply in the thread.
  Future<StoopMessage> sendMessage(String accessToken, String body) async {
    final json = await _post(
      '/me/messages',
      {'body': body},
      token: accessToken,
    );
    return StoopMessage.fromJson(json['message'] as Map<String, dynamic>);
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
    );
  }
}
