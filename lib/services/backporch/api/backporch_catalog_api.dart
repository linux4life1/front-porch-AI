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

import 'package:front_porch_ai/services/backporch/api/backporch_api_types.dart';
import 'package:front_porch_ai/services/backporch/api/backporch_transport.dart';
import 'package:front_porch_ai/services/backporch/stoop_card.dart';
import 'package:front_porch_ai/services/backporch/stoop_character.dart';
import 'package:front_porch_ai/services/backporch/stoop_creator.dart';
import 'package:front_porch_ai/services/backporch/stoop_message.dart';

/// Upload, browse, card, creator and inbox endpoints. [BackporchApi] forwards
/// here.
class BackporchCatalogApi {
  BackporchCatalogApi(this._t);

  final BackporchTransport _t;

  Future<({String id, String status})> uploadCharacter({
    required String accessToken,
    required Map<String, dynamic> payload,
    required Uint8List avatarBytes,
    required String avatarFilename,
  }) async {
    final req =
        http.MultipartRequest('POST', Uri.parse('${_t.baseUrl}/characters'))
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
    final json = _t.parse(res);
    return (
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING',
    );
  }

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
            Uri.parse('${_t.baseUrl}/characters/$characterId/versions'),
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
    final json = _t.parse(res);
    return (
      id: json['id'] as String? ?? characterId,
      version: (json['version'] as num?)?.toInt() ?? 2,
      status: json['status'] as String? ?? 'PENDING',
    );
  }

  Future<List<StoopCharacter>> myCharacters(String accessToken) async {
    final json = await _t.get(
      '/me/characters?types=$kStoopWorldTypes',
      accessToken,
    );
    final items = (json['items'] as List?) ?? const [];
    return items
        .map((e) => StoopCharacter.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<StoopCard>> myDownloads(String accessToken) async {
    final json = await _t.get(
      '/me/downloads?types=$kStoopWorldTypes',
      accessToken,
    );
    final items = (json['items'] as List?) ?? const [];
    return items
        .map((e) => StoopCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  String assetUrl(String assetId, {bool thumb = false}) =>
      '${_t.baseUrl}${stoopAssetPath(assetId, thumb: thumb)}';

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
      await _t.get('/characters?$query', accessToken),
    );
  }

  Future<StoopCardDetail> cardDetail(String accessToken, String id) async {
    return StoopCardDetail.fromJson(
      await _t.get('/characters/$id', accessToken),
    );
  }

  Future<({int score, int myVote})> vote(
    String accessToken,
    String id,
    int value,
  ) async {
    final json = await _t.post('/characters/$id/vote', {
      'value': value,
    }, token: accessToken);
    return (
      score: (json['score'] as num?)?.toInt() ?? 0,
      myVote: (json['myVote'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Map<String, dynamic>> download(String accessToken, String id) async {
    return _t.post('/characters/$id/download', const {}, token: accessToken);
  }

  Future<Uint8List> assetBytes(
    String accessToken,
    String assetId, {
    bool thumb = false,
  }) async {
    final client = http.Client();
    try {
      final res = await client
          .get(
            Uri.parse(assetUrl(assetId, thumb: thumb)),
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
      throw BackporchApiException(res.statusCode, 'asset_${res.statusCode}');
    } finally {
      client.close();
    }
  }

  Future<void> reportCharacter(
    String accessToken,
    String characterId, {
    required String category,
    String reason = '',
  }) async {
    await _t.post('/reports', {
      'characterId': characterId,
      'category': category,
      'reason': reason,
    }, token: accessToken);
  }

  Future<StoopCreator> creatorProfile(String accessToken, String id) async {
    return StoopCreator.fromJson(
      await _t.get('/creators/$id?types=$kStoopWorldTypes', accessToken),
    );
  }

  Future<({bool following, int followers})> setFollow(
    String accessToken,
    String creatorId,
    bool follow,
  ) async {
    final json = follow
        ? await _t.post(
            '/creators/$creatorId/follow',
            const {},
            token: accessToken,
          )
        : await _t.delete('/creators/$creatorId/follow', accessToken);
    return (
      following: json['following'] as bool? ?? follow,
      followers: (json['followers'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<StoopFollowedCreator>> myFollowing(String accessToken) async {
    final json = await _t.get('/me/following', accessToken);
    final items = (json['items'] as List?) ?? const [];
    return items
        .map((e) => StoopFollowedCreator.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<({bool commentsEnabled, bool commentsLocked})> patchCardComments(
    String accessToken,
    String cardId, {
    bool? commentsEnabled,
    bool? commentsLocked,
  }) async {
    final body = <String, dynamic>{};
    if (commentsEnabled != null) body['commentsEnabled'] = commentsEnabled;
    if (commentsLocked != null) body['commentsLocked'] = commentsLocked;
    final json = await _t.patch(
      '/characters/$cardId',
      body,
      token: accessToken,
    );
    return (
      commentsEnabled: json['commentsEnabled'] == true,
      commentsLocked: json['commentsLocked'] == true,
    );
  }

  Future<List<StoopMessage>> myMessages(String accessToken) async {
    final json = await _t.get('/me/messages', accessToken);
    final items = (json['items'] as List?) ?? const [];
    return items
        .map((e) => StoopMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> unreadMessageCount(String accessToken) async {
    final json = await _t.get('/me/messages/unread', accessToken);
    return (json['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markMessagesRead(String accessToken) async {
    await _t.post('/me/messages/read', const {}, token: accessToken);
  }

  Future<StoopMessage> sendMessage(String accessToken, String body) async {
    final json = await _t.post('/me/messages', {
      'body': body,
    }, token: accessToken);
    return StoopMessage.fromJson(json['message'] as Map<String, dynamic>);
  }
}
