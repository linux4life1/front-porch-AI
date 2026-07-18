// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';

/// Where the repository session currently stands.
///
/// [unknown] is the brief startup window while a saved session is being
/// restored — the UI shows a loader rather than flashing the login screen.
enum AuthStatus { unknown, loggedOut, loggedIn }

/// Holds the signed-in repository account and session tokens, and orchestrates
/// sign-up / sign-in / sign-out against the Front Porch server. The repository
/// page watches this; the rest of the app is unaffected (accounts gate only the
/// repository, not local/offline use).
class AuthState extends ChangeNotifier {
  AuthState({BackporchApi? api, BackporchAuthStore? store})
    : _api = api ?? BackporchApi(),
      _store = store ?? BackporchAuthStore();

  final BackporchApi _api;
  final BackporchAuthStore _store;

  AuthStatus _status = AuthStatus.unknown;
  BackporchUser? _user;
  String? _accessToken;
  String? _refreshToken;
  String _policyVersion = '';

  // Local, opt-out preference for anonymous app analytics (default on). Loaded
  // from the Stoop's beta-isolated store in [init]; the StoopAnalytics service
  // reads it before each ping.
  bool _analyticsEnabled = true;

  // Access tokens expire after ~15 min; this proactively rotates them so every
  // Stoop call keeps working without a per-call retry-on-401.
  Timer? _refreshTimer;

  AuthStatus get status => _status;
  BackporchUser? get user => _user;
  bool get isLoggedIn => _status == AuthStatus.loggedIn && _user != null;
  String? get accessToken => _accessToken;

  /// Whether anonymous app analytics may be sent (local, opt-out, default on).
  bool get analyticsEnabled => _analyticsEnabled;

  /// The live AUP version reported by the server.
  String get policyVersion => _policyVersion;

  /// True when a signed-in user still owes agreement to the current AUP — the
  /// repository content stays gated behind the policy screen until they accept.
  bool get needsPolicyAcceptance =>
      isLoggedIn &&
      _policyVersion.isNotEmpty &&
      _user!.acceptedPolicyVersion != _policyVersion;

  /// Restore a saved session on startup. Call once after construction.
  Future<void> init() async {
    _analyticsEnabled = await _store.analyticsEnabled();
    final tokens = await _store.read();
    if (!tokens.hasRefresh) {
      _clearSession();
      return;
    }
    _accessToken = tokens.access;
    _refreshToken = tokens.refresh;

    // Prefer the still-valid access token; only fall back to refresh on a 401.
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      try {
        final me = await _api.me(_accessToken!);
        _user = me.user;
        _policyVersion = me.policyVersion;
        _status = AuthStatus.loggedIn;
        _scheduleTokenRefresh();
        notifyListeners();
        return;
      } on BackporchApiException catch (e) {
        if (e.statusCode != 401) {
          // Server/network hiccup, not an auth failure — keep the saved tokens
          // and stay logged out for now rather than destroying a good session.
          _clearSession();
          return;
        }
      } catch (_) {
        _clearSession();
        return;
      }
    }

    // Access token missing or expired → try the refresh token.
    try {
      await _applyAuth(await _api.refresh(_refreshToken!));
    } catch (_) {
      await _store.clear();
      _clearSession();
    }
  }

  Future<void> signup({
    required String email,
    required String password,
    required String displayName,
    required DateTime dateOfBirth,
  }) async {
    await _applyAuth(
      await _api.signup(
        email: email.trim(),
        password: password,
        displayName: displayName.trim(),
        dateOfBirth: dateOfBirth,
        installId: await _store.installId(),
      ),
    );
  }

  Future<void> login({
    required String email,
    required String password,
    String? totp,
  }) async {
    await _applyAuth(
      await _api.login(
        email: email.trim(),
        password: password,
        installId: await _store.installId(),
        totp: totp,
      ),
    );
  }

  /// Begin authenticator enrollment — returns the secret + QR for the account
  /// sheet to display. Not active until [enableTwoFactor] confirms a code.
  Future<({String secret, String otpauthUrl, String qrDataUrl})>
  setupTwoFactor() {
    return _api.twoFactorSetup(_accessToken!);
  }

  /// Confirm a code to turn 2FA on, then refresh the cached account.
  Future<void> enableTwoFactor(String totp) async {
    if (_accessToken == null) return;
    await _api.twoFactorEnable(_accessToken!, totp);
    await _refreshUser();
  }

  /// Turn 2FA off (needs a current code), then refresh the cached account.
  Future<void> disableTwoFactor(String totp) async {
    if (_accessToken == null) return;
    await _api.twoFactorDisable(_accessToken!, totp);
    await _refreshUser();
  }

  // Re-pull /auth/me so a server-side change (e.g. twoFactorEnabled) shows in
  // the UI without forcing a re-login.
  Future<void> _refreshUser() async {
    if (_accessToken == null) return;
    final me = await _api.me(_accessToken!);
    _user = me.user;
    _policyVersion = me.policyVersion;
    notifyListeners();
  }

  Future<void> logout() async {
    await _api.logout(_refreshToken);
    await _store.clear();
    _clearSession();
  }

  /// Agree to the current AUP. Updates the account so the gate clears.
  Future<void> acceptPolicy() async {
    if (_accessToken == null) return;
    final me = await _api.acceptPolicy(_accessToken!, _policyVersion);
    _user = me.user;
    _policyVersion = me.policyVersion;
    notifyListeners();
  }

  /// Change the public display name (persisted server-side).
  Future<void> setDisplayName(String displayName) async {
    if (_accessToken == null) return;
    final me = await _api.setDisplayName(_accessToken!, displayName.trim());
    _user = me.user;
    _policyVersion = me.policyVersion;
    notifyListeners();
  }

  /// Toggle the NSFW content preference (persisted server-side).
  Future<void> setNsfwEnabled(bool enabled) async {
    if (_accessToken == null) return;
    final me = await _api.setNsfwEnabled(_accessToken!, enabled);
    _user = me.user;
    _policyVersion = me.policyVersion;
    notifyListeners();
  }

  /// Toggle anonymous app analytics (local, opt-out, beta-isolated). When off,
  /// StoopAnalytics stops sending device pings.
  Future<void> setAnalyticsEnabled(bool enabled) async {
    _analyticsEnabled = enabled;
    await _store.setAnalyticsEnabled(enabled);
    notifyListeners();
  }

  /// Permanently delete this account on the server, then sign out locally.
  Future<void> deleteAccount() async {
    if (_accessToken != null) {
      await _api.deleteAccount(_accessToken!);
    }
    await _store.clear();
    _clearSession();
  }

  Future<void> _applyAuth(AuthResult r) async {
    _user = r.user;
    _accessToken = r.accessToken;
    _refreshToken = r.refreshToken;
    _policyVersion = r.policyVersion;
    _status = AuthStatus.loggedIn;
    await _store.save(accessToken: r.accessToken, refreshToken: r.refreshToken);
    _scheduleTokenRefresh();
    notifyListeners();
  }

  void _scheduleTokenRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 12),
      (_) => _refreshAccessToken(),
    );
  }

  /// Rotate the access token using the refresh token. Best-effort: a transient
  /// failure leaves the session in place; a real auth failure surfaces on the
  /// next call.
  Future<void> _refreshAccessToken() async {
    if (_refreshToken == null) return;
    try {
      final r = await _api.refresh(_refreshToken!);
      _user = r.user;
      _accessToken = r.accessToken;
      _refreshToken = r.refreshToken;
      _policyVersion = r.policyVersion;
      await _store.save(
        accessToken: r.accessToken,
        refreshToken: r.refreshToken,
      );
      notifyListeners();
    } catch (_) {
      // Keep the current session; the next real call will handle a hard failure.
    }
  }

  /// Reset to the logged-out state. The on-disk tokens are left untouched
  /// (only logout/deleteAccount clear storage), so a transient init failure
  /// can recover the saved session on the next launch.
  void _clearSession() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _user = null;
    _accessToken = null;
    _refreshToken = null;
    _policyVersion = '';
    _status = AuthStatus.loggedOut;
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
