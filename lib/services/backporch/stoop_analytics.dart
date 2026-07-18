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
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch_api.dart';
import 'package:front_porch_ai/services/backporch/backporch_auth_store.dart';
import 'package:front_porch_ai/services/hardware_service.dart';

/// Sends one anonymous device ping per app launch — but only when the user is
/// signed in to The Stoop AND has analytics enabled (opt-out, default on).
///
/// It listens to [AuthState] so the ping fires as soon as a saved session is
/// restored or a fresh login completes. Every field is coarse (platform, OS,
/// app version, locale, GPU name + VRAM); the server buckets the GPU into a
/// tier and never stores an IP. Failures are swallowed — analytics must never
/// disrupt the app.
class StoopAnalytics {
  StoopAnalytics(
    this._auth,
    this._hardware, {
    BackporchApi? api,
    BackporchAuthStore? store,
  })  : _api = api ?? BackporchApi(),
        _store = store ?? BackporchAuthStore() {
    _auth.addListener(_maybePing);
    unawaited(_maybePing()); // in case we're already signed in at startup
  }

  final AuthState _auth;
  final HardwareService _hardware;
  final BackporchApi _api;
  final BackporchAuthStore _store;

  bool _pinged = false; // once per launch

  Future<void> _maybePing() async {
    if (_pinged) return;
    // Only ping once the user is fully past the AUP gate. The gate carries its
    // own analytics toggle, so by the time this fires the choice is already made
    // — and we never send a doomed pre-acceptance request the server would 403.
    if (!_auth.isLoggedIn ||
        _auth.needsPolicyAcceptance ||
        !_auth.analyticsEnabled) {
      return;
    }
    final token = _auth.accessToken;
    if (token == null || token.isEmpty) return;

    // Set the guard before awaiting so a burst of notifyListeners (e.g. a token
    // refresh right after login) can't fire a second ping.
    _pinged = true;
    try {
      await _api.sendAppPing(accessToken: token, payload: await _payload());
    } catch (_) {
      _pinged = false; // transient failure — let the next auth change retry
    }
  }

  Future<Map<String, dynamic>> _payload() async {
    final hw = _hardware.hardwareInfo;
    return {
      'installId': await _store.installId(),
      'platform': Platform.isMacOS
          ? 'macos'
          : Platform.isWindows
              ? 'windows'
              : Platform.isLinux
                  ? 'linux'
                  : 'other',
      'osVersion': _osVersion(),
      'appVersion': appVersion,
      'locale': _locale(),
      if (hw != null && hw.gpuName.isNotEmpty) 'gpu': hw.gpuName,
      if (hw != null && hw.vramMb > 0) 'vramMb': hw.vramMb,
    };
  }

  // A coarse OS label with the noisy build suffix stripped so buckets stay broad
  // (e.g. "macOS 15.5", "Windows 10.0", "Linux 6.8.0-...").
  String _osVersion() {
    var v = Platform.operatingSystemVersion;
    final paren = v.indexOf('(');
    if (paren > 0) v = v.substring(0, paren);
    v = v.trim();
    if (Platform.isMacOS) {
      final m = RegExp(r'(\d+(?:\.\d+)*)').firstMatch(v);
      v = m != null ? 'macOS ${m.group(1)}' : 'macOS';
    }
    return v.length > 60 ? v.substring(0, 60) : v;
  }

  String _locale() {
    try {
      return WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();
    } catch (_) {
      return '';
    }
  }

  void dispose() => _auth.removeListener(_maybePing);
}
