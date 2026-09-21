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

extension BackporchApiCatalog on BackporchApi {
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
    final req =
        http.MultipartRequest(
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
    final json = await _get(
      '/me/characters?types=$kStoopWorldTypes',
      accessToken,
    );
    final items = (json['items'] as List?) ?? const [];
    return items
        .map((e) => StoopCharacter.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Cards the user has downloaded before (newest first), so they can grab them
  /// again on a new device. Returns the same shape as browse items.
  Future<List<StoopCard>> myDownloads(String accessToken) async {
    final json = await _get(
      '/me/downloads?types=$kStoopWorldTypes',
      accessToken,
    );
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
      // Mixed views ask for worlds explicitly. The server keeps `type=all`
      // meaning solo+group forever, because every already-shipped app sends
      // it and would render a world as a broken character; `types=` is the
      // opt-in no old client has ever sent. Older servers ignore the param.
      if (type == 'all') 'types': kStoopWorldTypes,
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
    return StoopCreator.fromJson(
      await _get('/creators/$id?types=$kStoopWorldTypes', accessToken),
    );
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

  /// Owner-only PATCH for `commentsEnabled` / `commentsLocked`.
  /// 404 is fail-closed at the call site (hide Discussion).
  Future<({bool commentsEnabled, bool commentsLocked})> patchCardComments(
    String accessToken,
    String cardId, {
    bool? commentsEnabled,
    bool? commentsLocked,
  }) async {
    final body = <String, dynamic>{};
    if (commentsEnabled != null) body['commentsEnabled'] = commentsEnabled;
    if (commentsLocked != null) body['commentsLocked'] = commentsLocked;
    final json = await _patch('/characters/$cardId', body, token: accessToken);
    return (
      commentsEnabled: json['commentsEnabled'] == true,
      commentsLocked: json['commentsLocked'] == true,
    );
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
    final json = await _post('/me/messages', {
      'body': body,
    }, token: accessToken);
    return StoopMessage.fromJson(json['message'] as Map<String, dynamic>);
  }
}
