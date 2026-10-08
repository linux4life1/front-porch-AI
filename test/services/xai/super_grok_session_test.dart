// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unofficial SuperGrok sign-in: the saved session, the token overlay that
// lets every api.x.ai request ride it, and the guard that keeps the session
// token out of the per-host API key vault. The live device-code login is
// not pinned here — it needs a real xAI account.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/generation_error_messages.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';
import 'package:front_porch_ai/services/xai/xai.dart';
import 'package:shared_preferences/shared_preferences.dart';

XaiTokens _tokens({Duration life = const Duration(hours: 1)}) => XaiTokens(
  accessToken: 'session-access',
  refreshToken: 'session-refresh',
  expiresAt: DateTime.now().add(life),
  email: 'porch@example.com',
);

String _idToken(Map<String, Object?> claims) =>
    'h.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.s';

Future<BackendSettings> _backend() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final b = BackendSettings()..initializeBase(prefs, () {});
  b.load();
  return b;
}

void main() {
  group('XaiTokens', () {
    test('survives a save and load', () {
      final saved = _tokens();
      final back = XaiTokens.decode(saved.encode())!;
      expect(back.accessToken, 'session-access');
      expect(back.refreshToken, 'session-refresh');
      expect(back.email, 'porch@example.com');
      expect(
        back.expiresAt.millisecondsSinceEpoch,
        saved.expiresAt.millisecondsSinceEpoch,
      );
    });

    test('a broken record reads as signed out, not a crash', () {
      expect(XaiTokens.decode(null), isNull);
      expect(XaiTokens.decode('not json'), isNull);
      expect(XaiTokens.decode('{"access":"a"}'), isNull);
    });

    test('refreshes two minutes before the token dies', () {
      final now = DateTime(2026, 10, 1, 12);
      final t = XaiTokens(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: now.add(const Duration(minutes: 3)),
      );
      expect(t.needsRefresh(now), isFalse);
      expect(t.needsRefresh(now.add(const Duration(minutes: 1))), isTrue);
    });

    test('a refresh without a new refresh token keeps the old one', () {
      final next = XaiTokens.fromTokenResponse({
        'access_token': 'fresh',
        'expires_in': 900,
      }, previous: _tokens());
      expect(next.accessToken, 'fresh');
      expect(next.refreshToken, 'session-refresh');
      expect(next.email, 'porch@example.com');
    });

    test('reads the email claim from the id token', () {
      expect(
        XaiTokens.emailFromIdToken(_idToken({'email': 'me@x.example'})),
        'me@x.example',
      );
      expect(XaiTokens.emailFromIdToken('garbage'), isNull);
    });
  });

  group('SuperGrokAuth', () {
    test('a saved session signs in on load and only covers api.x.ai', () async {
      String? stored = _tokens().encode();
      final auth = SuperGrokAuth(
        readSession: () => stored,
        writeSession: (v) async => stored = v,
      );
      addTearDown(auth.dispose);
      await auth.load();

      expect(auth.phase, SuperGrokPhase.signedIn);
      expect(auth.email, 'porch@example.com');
      expect(auth.bearerFor(kXaiApiV1), 'session-access');
      expect(auth.bearerFor('https://api.x.ai/v1/'), 'session-access');
      expect(auth.bearerFor(kOpenRouterApiV1), isNull);
      expect(auth.toJson().containsKey('access'), isFalse);
      expect(jsonEncode(auth.toJson()), isNot(contains('session-access')));

      await auth.signOut();
      expect(auth.isSignedIn, isFalse);
      expect(auth.bearerFor(kXaiApiV1), isNull);
      expect(stored, isNull);
    });
  });

  group('bearer overlay', () {
    test('rides remoteApiKeyFor without entering the key vault', () async {
      final b = await _backend();
      await b.setRemoteApiUrl(kXaiApiV1);
      await b.setRemoteApiKey('xai-real-key');

      b.bearerOverlay = (url) =>
          remoteApiUrlIsXai(url) ? 'session-access' : null;
      expect(b.remoteApiKey, 'session-access');
      expect(b.remoteApiKeyFor(kXaiApiV1), 'session-access');
      expect(b.remoteApiKeyFor(kOpenRouterApiV1), isEmpty);
      expect(typedRemoteApiKey(b), isEmpty);

      // A key field pre-filled with the token and saved back must not
      // overwrite the user's real key.
      await b.setRemoteApiKey('session-access');
      await b.setRemoteApiKeyFor(kXaiApiV1, 'session-access');

      b.bearerOverlay = null;
      expect(b.remoteApiKey, 'xai-real-key');
      expect(typedRemoteApiKey(b), 'xai-real-key');
    });
  });

  test('api.x.ai is the xAI host pill and needs a key', () {
    final kind = resolveRemoteProviderKind(
      backendType: 'openRouter',
      url: kXaiApiV1,
    );
    expect(kind, RemoteProviderKind.xai);
    expect(urlForRemoteProvider(kind), kXaiApiV1);
    expect(remoteProviderNeedsApiKey(kind), isTrue);
    expect(remoteProviderShowsUrlField(kind), isFalse);
  });

  test('xAI out-of-credits refusal reads in plain words', () {
    final msg = friendlyGenerationError(
      'Exception: API error: You have run out of credits or need a Grok '
      'subscription. Add credits at https://grok.com/?_s=usage',
    );
    expect(msg, contains('out of credits for now'));
    expect(msg, contains('SuperGrok'));
  });
}
