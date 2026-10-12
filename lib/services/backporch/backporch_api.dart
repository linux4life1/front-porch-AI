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

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:front_porch_ai/services/backporch/api/backporch_account_api.dart';
import 'package:front_porch_ai/services/backporch/api/backporch_api_types.dart';
import 'package:front_porch_ai/services/backporch/api/backporch_catalog_api.dart';
import 'package:front_porch_ai/services/backporch/api/backporch_transport.dart';

import 'backporch_user.dart';
import 'stoop_character.dart';
import 'stoop_card.dart';
import 'stoop_creator.dart';
import 'stoop_message.dart';

export 'package:front_porch_ai/services/backporch/api/backporch_api_types.dart';

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

  late final _transport = BackporchTransport(baseUrl);
  late final _account = BackporchAccountApi(_transport);
  late final _catalog = BackporchCatalogApi(_transport);

  Future<AuthResult> refresh(String refreshToken) async {
    final json = await _transport.post('/auth/refresh', {
      'refreshToken': refreshToken,
    });
    return parseAuthResult(json);
  }

  Future<({BackporchUser user, String policyVersion})> me(
    String accessToken,
  ) async {
    return parseMeResult(await _transport.get('/auth/me', accessToken));
  }

  Future<AuthResult> signup({
    required String email,
    required String password,
    required String displayName,
    required DateTime dateOfBirth,
    String? installId,
  }) => _account.signup(
    email: email,
    password: password,
    displayName: displayName,
    dateOfBirth: dateOfBirth,
    installId: installId,
  );

  Future<AuthResult> login({
    required String email,
    required String password,
    String? installId,
    String? totp,
  }) => _account.login(
    email: email,
    password: password,
    installId: installId,
    totp: totp,
  );

  /// Begin authenticator (TOTP) enrollment. Returns the shared secret, the
  /// otpauth:// URI, and a ready-to-show QR image (a `data:image/png;base64,…`
  /// URL). The secret is stored server-side but stays inactive until [confirm].
  Future<({String secret, String otpauthUrl, String qrDataUrl})> twoFactorSetup(
    String accessToken,
  ) => _account.twoFactorSetup(accessToken);

  /// Confirm a code to switch 2FA on. Throws `invalid_code` on a wrong code.
  Future<void> twoFactorEnable(String accessToken, String totp) =>
      _account.twoFactorEnable(accessToken, totp);

  /// Turn 2FA off — requires a current code. Throws `invalid_code` if wrong.
  Future<void> twoFactorDisable(String accessToken, String totp) =>
      _account.twoFactorDisable(accessToken, totp);

  Future<({BackporchUser user, String policyVersion})> acceptPolicy(
    String accessToken,
    String version,
  ) => _account.acceptPolicy(accessToken, version);

  /// Change the public display name. Returns the refreshed account.
  Future<({BackporchUser user, String policyVersion})> setDisplayName(
    String accessToken,
    String displayName,
  ) => _account.setDisplayName(accessToken, displayName);

  /// Set the NSFW content preference. Returns the refreshed account.
  Future<({BackporchUser user, String policyVersion})> setNsfwEnabled(
    String accessToken,
    bool enabled,
  ) => _account.setNsfwEnabled(accessToken, enabled);

  /// Edit the public creator profile (bio ≤ 300 chars, up to 4 http(s) links).
  /// Returns the refreshed account.
  Future<({BackporchUser user, String policyVersion})> updateProfile(
    String accessToken, {
    required String bio,
    required List<String> links,
  }) => _account.updateProfile(accessToken, bio: bio, links: links);

  /// Upload a profile picture. Live instantly (post-moderated); requires a
  /// verified email. Throws `email_not_verified` / `avatar_locked` /
  /// `unsupported_image_type` for the UI to explain.
  Future<({BackporchUser user, String policyVersion})> uploadAvatar({
    required String accessToken,
    required Uint8List bytes,
    required String filename,
  }) => _account.uploadAvatar(
    accessToken: accessToken,
    bytes: bytes,
    filename: filename,
  );

  /// Remove the profile picture (always allowed, instant).
  Future<({BackporchUser user, String policyVersion})> deleteAvatar(
    String accessToken,
  ) => _account.deleteAvatar(accessToken);

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
  }) => _account.changeEmail(
    accessToken,
    newEmail: newEmail,
    password: password,
    totp: totp,
  );

  /// Abandon a pending email change (nothing was ever committed).
  Future<({BackporchUser user, String policyVersion})> cancelEmailChange(
    String accessToken,
  ) => _account.cancelEmailChange(accessToken);

  /// Ask for a password-reset email. The server always answers ok (it never
  /// reveals whether the address has an account); the emailed link opens the
  /// hub's reset page.
  Future<void> forgotPassword(String email) => _account.forgotPassword(email);

  /// Delete one of the signed-in user's own uploads from The Stoop (owner-only
  /// server-side). Existing downloaders keep their copies.
  Future<void> deleteCharacter(String accessToken, String id) =>
      _account.deleteCharacter(accessToken, id);

  /// Permanently delete the signed-in account (GDPR erasure). Throws on failure.
  Future<void> deleteAccount(String accessToken) =>
      _account.deleteAccount(accessToken);

  /// Send an anonymous, opt-out device ping (platform / OS / app version /
  /// locale / GPU name + VRAM). The server upserts one row per install, buckets
  /// the GPU into a coarse tier, and returns 204. Fire-and-forget for callers.
  Future<void> sendAppPing({
    required String accessToken,
    required Map<String, dynamic> payload,
  }) => _account.sendAppPing(accessToken: accessToken, payload: payload);

  /// Ask for another email-confirmation link. Throws `resend_too_soon` when
  /// one was sent within the last couple of minutes.
  Future<void> resendVerification(String accessToken) =>
      _account.resendVerification(accessToken);

  /// Best-effort: revokes the server session. Never throws.
  Future<void> logout(String? refreshToken) => _account.logout(refreshToken);

  /// Upload a character card (the V2 [card] JSON + an avatar image) to The
  /// Stoop. Lands in the moderation queue as PENDING. Returns its id + status.
  Future<({String id, String status})> uploadCharacter({
    required String accessToken,
    required Map<String, dynamic> payload,
    required Uint8List avatarBytes,
    required String avatarFilename,
  }) => _catalog.uploadCharacter(
    accessToken: accessToken,
    payload: payload,
    avatarBytes: avatarBytes,
    avatarFilename: avatarFilename,
  );

  /// Publish a new version of an existing character IN PLACE (owner only). Keeps
  /// the Stoop id, downloads, score, and votes; re-enters the moderation queue.
  /// Used by the Mine-tab "Update" flow.
  Future<({String id, int version, String status})> publishVersion({
    required String accessToken,
    required String characterId,
    required Map<String, dynamic> payload,
    required Uint8List avatarBytes,
    required String avatarFilename,
  }) => _catalog.publishVersion(
    accessToken: accessToken,
    characterId: characterId,
    payload: payload,
    avatarBytes: avatarBytes,
    avatarFilename: avatarFilename,
  );

  /// The signed-in user's own uploads and their moderation status.
  Future<List<StoopCharacter>> myCharacters(String accessToken) =>
      _catalog.myCharacters(accessToken);

  /// Cards the user has downloaded before (newest first), so they can grab them
  /// again on a new device. Returns the same shape as browse items.
  Future<List<StoopCard>> myDownloads(String accessToken) =>
      _catalog.myDownloads(accessToken);

  /// The authenticated URL for a card asset (avatar). Load with an Authorization
  /// header — assets are served only to signed-in users, never publicly.
  /// [thumb] asks for the postcard-sized WebP the hub uses for tiles.
  String assetUrl(String assetId, {bool thumb = false}) =>
      _catalog.assetUrl(assetId, thumb: thumb);

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
  }) => _catalog.browse(
    accessToken: accessToken,
    sort: sort,
    type: type,
    q: q,
    pick: pick,
    following: following,
    page: page,
    take: take,
  );

  /// Full card detail (definitions, greetings, lorebook, tags, the caller's vote).
  Future<StoopCardDetail> cardDetail(String accessToken, String id) =>
      _catalog.cardDetail(accessToken, id);

  /// Cast a vote (1 up, -1 down, 0 clear). Returns the new score + your vote.
  Future<({int score, int myVote})> vote(
    String accessToken,
    String id,
    int value,
  ) => _catalog.vote(accessToken, id, value);

  /// Record a download and return the card payload for local import.
  Future<Map<String, dynamic>> download(String accessToken, String id) =>
      _catalog.download(accessToken, id);

  /// Fetch a card asset's bytes: the original (for embedding on import, the
  /// card page) or the postcard [thumb] the grids show.
  Future<Uint8List> assetBytes(
    String accessToken,
    String assetId, {
    bool thumb = false,
  }) => _catalog.assetBytes(accessToken, assetId, thumb: thumb);

  /// File a report against a card. [category] is one of SPAM, MISLABELED,
  /// ILLEGAL, STOLEN, REAL_PERSON, LOW_EFFORT, PROHIBITED_IMAGE, OTHER.
  Future<void> reportCharacter(
    String accessToken,
    String characterId, {
    required String category,
    String reason = '',
  }) => _catalog.reportCharacter(
    accessToken,
    characterId,
    category: category,
    reason: reason,
  );

  /// A creator's profile + their approved cards.
  Future<StoopCreator> creatorProfile(String accessToken, String id) =>
      _catalog.creatorProfile(accessToken, id);

  /// Follow / unfollow a creator. Returns the new follow state + follower count.
  Future<({bool following, int followers})> setFollow(
    String accessToken,
    String creatorId,
    bool follow,
  ) => _catalog.setFollow(accessToken, creatorId, follow);

  /// The creators the signed-in user follows.
  Future<List<StoopFollowedCreator>> myFollowing(String accessToken) =>
      _catalog.myFollowing(accessToken);

  /// Owner-only PATCH for `commentsEnabled` / `commentsLocked`.
  /// 404 is fail-closed at the call site (hide Discussion).
  Future<({bool commentsEnabled, bool commentsLocked})> patchCardComments(
    String accessToken,
    String cardId, {
    bool? commentsEnabled,
    bool? commentsLocked,
  }) => _catalog.patchCardComments(
    accessToken,
    cardId,
    commentsEnabled: commentsEnabled,
    commentsLocked: commentsLocked,
  );

  /// The whole conversation, oldest first.
  Future<List<StoopMessage>> myMessages(String accessToken) =>
      _catalog.myMessages(accessToken);

  /// Count of unread moderator messages (drives the notification bell badge).
  Future<int> unreadMessageCount(String accessToken) =>
      _catalog.unreadMessageCount(accessToken);

  /// Mark all moderator messages as read (called when the inbox opens).
  Future<void> markMessagesRead(String accessToken) =>
      _catalog.markMessagesRead(accessToken);

  /// Send a reply in the thread.
  Future<StoopMessage> sendMessage(String accessToken, String body) =>
      _catalog.sendMessage(accessToken, body);
}
