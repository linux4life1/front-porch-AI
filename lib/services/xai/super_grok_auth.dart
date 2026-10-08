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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/openrouter_native_tools.dart';
import 'package:front_porch_ai/services/remote_reachability.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/xai/xai_oauth_client.dart';
import 'package:front_porch_ai/services/xai/xai_tokens.dart';

enum SuperGrokPhase { signedOut, waiting, signedIn }

/// UNOFFICIAL SuperGrok sign-in (see [kGrokCliClientId]). While signed in,
/// [bearerFor] hands the access token to every request bound for api.x.ai,
/// so chat, side jobs, and the web relay all ride the subscription without a
/// pasted key. Signing out falls back to the xAI API key, if one is saved.
class SuperGrokAuth extends ChangeNotifier {
  SuperGrokAuth({
    required String? Function() readSession,
    required Future<void> Function(String? encoded) writeSession,
    XaiOAuthClient? client,
    http.Client Function()? httpClientFactory,
  }) : _readSession = readSession,
       _writeSession = writeSession,
       _httpClientFactory = httpClientFactory ?? http.Client.new,
       _client = client ?? XaiOAuthClient(clientFactory: httpClientFactory);

  /// Session lives beside the other API keys in SharedPreferences — the
  /// macOS keychain comes back empty on ad-hoc Rawhide launches.
  factory SuperGrokAuth.inPrefs(
    SharedPreferences? Function() prefs,
    String key,
  ) => SuperGrokAuth(
    readSession: () => prefs()?.getString(key),
    writeSession: (encoded) async {
      final p = prefs();
      if (p == null) return;
      if (encoded == null) {
        await p.remove(key);
      } else {
        await p.setString(key, encoded);
      }
    },
  );

  final String? Function() _readSession;
  final Future<void> Function(String? encoded) _writeSession;
  final http.Client Function() _httpClientFactory;
  final XaiOAuthClient _client;

  XaiTokens? _tokens;
  XaiDeviceCode? _pending;
  SuperGrokPhase _phase = SuperGrokPhase.signedOut;
  String? _error;
  String? _accessNote;
  Timer? _refreshTimer;
  Future<void>? _refreshing;
  int _signInGeneration = 0;
  bool _disposed = false;

  SuperGrokPhase get phase => _phase;
  bool get isSignedIn => _tokens != null;
  String? get email => _tokens?.email;

  /// Code + link to approve while [phase] is waiting.
  String? get userCode => _pending?.userCode;
  String? get verificationUri => _pending?.verificationUri;

  /// Last sign-in / refresh failure, in plain words.
  String? get error => _error;

  /// What xAI said when asked for the model list, when it refused
  /// (allowance used up, plan not allowed). Null when access looked fine.
  String? get accessNote => _accessNote;

  /// Access token for an api.x.ai URL while signed in, else null.
  String? bearerFor(String url) =>
      _tokens != null && remoteApiUrlIsXai(url) ? _tokens!.accessToken : null;

  Map<String, dynamic> toJson() => {
    'phase': _phase.name,
    'signedIn': isSignedIn,
    'email': ?email,
    'userCode': ?userCode,
    'verificationUri': ?verificationUri,
    'error': ?_error,
    'accessNote': ?_accessNote,
  };

  Future<void> load() async {
    final saved = XaiTokens.decode(_readSession());
    if (saved == null) return;
    _tokens = saved;
    _phase = SuperGrokPhase.signedIn;
    _notify();
    if (saved.needsRefresh()) {
      await _refresh();
    } else {
      _scheduleRefresh();
    }
    if (!kSkipRemoteAutoPing) unawaited(checkAccess());
  }

  /// Ask xAI for a code, then poll in the background until it is approved.
  /// [openBrowser] gets the approval link (desktop opens it; the web relay
  /// hands it to the phone instead).
  Future<void> startSignIn({void Function(String uri)? openBrowser}) async {
    final generation = ++_signInGeneration;
    _error = null;
    _notify();
    final XaiDeviceCode code;
    try {
      code = await _client.startDeviceLogin();
    } catch (e) {
      if (generation != _signInGeneration) return;
      _error = e is XaiOAuthException
          ? e.message
          : 'Could not reach xAI to sign in. Check your internet connection.';
      debugPrint('[SuperGrok] start sign-in failed: $e');
      _notify();
      return;
    }
    if (generation != _signInGeneration || _disposed) return;
    _pending = code;
    _phase = SuperGrokPhase.waiting;
    _notify();
    openBrowser?.call(code.verificationUri);
    unawaited(_pollUntilDone(code, generation));
  }

  Future<void> _pollUntilDone(XaiDeviceCode code, int generation) async {
    var gap = code.interval;
    bool live() => generation == _signInGeneration && !_disposed;
    while (live() && DateTime.now().isBefore(code.expiresAt)) {
      await Future<void>.delayed(gap);
      if (!live()) return;
      try {
        final result = await _client.poll(code);
        if (!live()) return;
        final tokens = result.tokens;
        if (tokens != null) {
          await _adopt(tokens);
          return;
        }
        if (result.slowDown) gap += const Duration(seconds: 5);
      } on XaiOAuthException catch (e) {
        if (live()) _endWaiting(e.message);
        return;
      } catch (e) {
        // A dropped poll is not a failed sign-in; the next one may land.
        debugPrint('[SuperGrok] poll failed, retrying: $e');
      }
    }
    if (live()) _endWaiting('The sign-in code expired. Start again.');
  }

  void _endWaiting(String? message) {
    _pending = null;
    _phase = isSignedIn ? SuperGrokPhase.signedIn : SuperGrokPhase.signedOut;
    _error = message;
    _notify();
  }

  void cancelSignIn() {
    if (_phase != SuperGrokPhase.waiting) return;
    _signInGeneration++;
    _endWaiting(null);
  }

  Future<void> signOut() async {
    _signInGeneration++;
    _refreshTimer?.cancel();
    _tokens = null;
    _pending = null;
    _phase = SuperGrokPhase.signedOut;
    _error = null;
    _accessNote = null;
    await _writeSession(null);
    _notify();
  }

  Future<void> _adopt(XaiTokens tokens) async {
    _tokens = tokens;
    _pending = null;
    _phase = SuperGrokPhase.signedIn;
    _error = null;
    await _writeSession(tokens.encode());
    _scheduleRefresh();
    _notify();
    unawaited(checkAccess());
  }

  Future<void> _refresh() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<void> _doRefresh() async {
    final current = _tokens;
    if (current == null) return;
    try {
      final next = await _client.refresh(current);
      if (!identical(_tokens, current) || _disposed) return;
      _tokens = next;
      await _writeSession(next.encode());
      _scheduleRefresh();
      _notify();
    } on XaiOAuthException catch (e) {
      debugPrint('[SuperGrok] refresh refused: $e');
      if (e.signedOut) {
        await signOut();
        _error = e.message;
        _notify();
      } else {
        _scheduleRefresh(const Duration(minutes: 1));
      }
    } catch (e) {
      debugPrint('[SuperGrok] refresh failed, retrying in 1 min: $e');
      _scheduleRefresh(const Duration(minutes: 1));
    }
  }

  void _scheduleRefresh([Duration? after]) {
    _refreshTimer?.cancel();
    final tokens = _tokens;
    if (tokens == null || _disposed) return;
    final wait =
        after ??
        tokens.expiresAt
            .subtract(XaiTokens.refreshMargin)
            .difference(DateTime.now());
    _refreshTimer = Timer(
      wait.isNegative ? Duration.zero : wait,
      () => unawaited(_refresh()),
    );
  }

  /// `GET /models` with the session token. A refusal is kept as
  /// [accessNote] so the card can say why chat will not work.
  Future<void> checkAccess() async {
    final tokens = _tokens;
    if (tokens == null) return;
    final client = _httpClientFactory();
    try {
      final res = await client
          .get(
            Uri.parse('$kXaiApiV1/models'),
            headers: remoteAuthHeaders(tokens.accessToken),
          )
          .timeout(const Duration(seconds: 15));
      if (!identical(_tokens, tokens)) return;
      _accessNote = res.statusCode == 200
          ? null
          : 'xAI says: ${openRouterApiErrorMessage(res.body, res.statusCode)}';
      _notify();
    } catch (e) {
      debugPrint('[SuperGrok] access check failed: $e');
    } finally {
      client.close();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _signInGeneration++;
    _refreshTimer?.cancel();
    super.dispose();
  }
}
