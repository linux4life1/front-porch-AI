// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:front_porch_ai/app_version.dart';

/// The Backporch session tokens read back from disk.
class StoredTokens {
  final String? access;
  final String? refresh;
  const StoredTokens(this.access, this.refresh);

  bool get hasRefresh => refresh != null && refresh!.isNotEmpty;
}

/// Persists the repository session tokens in SharedPreferences.
///
/// Consistent with how the app already stores other credentials (API keys),
/// and beta-isolated via the same `beta_` key prefix used elsewhere so a
/// pre-release build never shares a session with the stable install.
class BackporchAuthStore {
  static String _k(String key) => isPreRelease ? 'beta_$key' : key;

  static final String _accessKey = _k('backporch_access_token');
  static final String _refreshKey = _k('backporch_refresh_token');
  static final String _installIdKey = _k('backporch_install_id');
  static final String _analyticsKey = _k('backporch_analytics_enabled');

  /// A stable, anonymous per-install id, generated once and persisted. Sent on
  /// signup/login so a banned account's device can be recognised (ban evasion).
  /// It is not cleared on logout — that's the whole point of the trace.
  Future<String> installId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_installIdKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_installIdKey, id);
    }
    return id;
  }

  /// Whether anonymous app analytics may be sent. Opt-OUT: defaults to true
  /// until the user turns it off in the Stoop account sheet. Beta-isolated like
  /// the rest of the Stoop's local state.
  Future<bool> analyticsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_analyticsKey) ?? true;
  }

  Future<void> setAnalyticsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_analyticsKey, value);
  }

  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, accessToken);
    await prefs.setString(_refreshKey, refreshToken);
  }

  Future<StoredTokens> read() async {
    final prefs = await SharedPreferences.getInstance();
    return StoredTokens(
      prefs.getString(_accessKey),
      prefs.getString(_refreshKey),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }
}
