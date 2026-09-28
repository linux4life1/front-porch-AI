// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// `UserRead` (1) OR `ModelsRead` (4). Re-check CivitAI's scope table before
/// any browser sign-in ships. This file does not open a browser or a socket.
///
/// The download credential is per Front Porch account
/// (`civitai_credential_<accountId>`), not one secret for the install.
const int kCivitaiModelsScope = 5;

/// Secure-storage name for one account's CivitAI key or token.
String civitaiCredentialKey(String accountId) {
  final id = accountId.trim();
  if (id.isEmpty || id.contains('/') || id.contains(r'\')) {
    throw ArgumentError('account id');
  }
  return 'civitai_credential_$id';
}

/// civitai.red does not accept the civitai.com key.
String civitaiRedCredentialKey(String accountId) {
  return '${civitaiCredentialKey(accountId)}_red';
}

const _kUnreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// PKCE verifier, 64 characters from the unreserved set.
String pkceVerifier([Random? random]) {
  final rng = random ?? Random.secure();
  return String.fromCharCodes(
    List.generate(
      64,
      (_) => _kUnreserved.codeUnitAt(rng.nextInt(_kUnreserved.length)),
    ),
  );
}

/// S256 challenge, base64url without padding.
String pkceChallenge(String verifier) {
  final digest = sha256.convert(utf8.encode(verifier)).bytes;
  return base64Url.encode(digest).replaceAll('=', '');
}

/// Authorize URL. No token is placed in the query.
String civitaiAuthorizeUrl({
  required String clientId,
  required String redirectUri,
  required String state,
  required String codeChallenge,
  String authorizeBase = 'https://auth.civitai.com/api/auth/oauth/authorize',
}) {
  return Uri.parse(authorizeBase)
      .replace(
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': '$kCivitaiModelsScope',
          'state': state,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
        },
      )
      .toString();
}
