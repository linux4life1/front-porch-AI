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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Parsed subset of `tailscale status --json`.
class TailscaleStatus {
  const TailscaleStatus({
    required this.running,
    this.backendState = 'NoState',
    this.magicDnsName,
    this.ip,
  });

  final bool running;

  /// Raw daemon state: `Running`, `NeedsLogin`, `Stopped`, `NoState`, etc.
  final String backendState;

  /// MagicDNS FQDN (trailing dot trimmed), e.g. `host.tailnet.ts.net`. A cert
  /// for this name is publicly trusted, giving a real secure context.
  final String? magicDnsName;

  /// The 100.x tailnet IP.
  final String? ip;

  /// Daemon is up but the user hasn't authenticated this machine yet.
  bool get needsLogin => backendState == 'NeedsLogin';

  static const unavailable = TailscaleStatus(running: false);
}

/// How a `tailscale serve` attempt resolved — lets the UI distinguish the one
/// case that needs a human (the tailnet hasn't opted into HTTPS certificates)
/// from a hard failure, and offer the right next step.
enum TailscaleServeOutcome {
  /// HTTPS serve is live; [TailscaleServeResult.url] is the public address.
  ok,

  /// Tailscale is up but the tailnet's HTTPS-certificates feature is off — a
  /// one-time toggle the admin must enable at [TailscaleProvider.enableHttpsUrl].
  httpsDisabled,

  /// Tailscale isn't running / signed in (no MagicDNS name yet).
  notReady,

  /// Anything else (permissions, daemon error). Fall back to the port URL.
  failed,
}

/// Result of [TailscaleProvider.serve].
class TailscaleServeResult {
  const TailscaleServeResult(this.outcome, [this.url]);

  final TailscaleServeOutcome outcome;

  /// The `https://<magicdns>` address — only set when [outcome] is
  /// [TailscaleServeOutcome.ok].
  final String? url;
}

/// Detects and drives an installed Tailscale. We do NOT bundle the binary.
///
/// Recommended HTTPS path (plan §4): `tailscale serve` lets the tailscaled
/// daemon terminate TLS with an auto-renewed Let's Encrypt cert and reverse-
/// proxy plain http to our loopback server — so we keep zero cert/renewal code
/// and trust `X-Forwarded-Proto: https` from the loopback proxy.
class TailscaleProvider {
  TailscaleProvider({String? executable}) : _exe = executable ?? _findExe();

  final String _exe;

  /// Whether a `tailscale` binary was located.
  bool get isInstalled => _exe.isNotEmpty;

  /// Run `tailscale status --json` and parse the bits we need.
  Future<TailscaleStatus> status() async {
    if (!isInstalled) return TailscaleStatus.unavailable;
    try {
      // `tailscale status --json` still emits BackendState (e.g. NeedsLogin)
      // with a non-zero exit when logged out, so parse stdout regardless.
      final result = await Process.run(_exe, ['status', '--json']);
      final out = result.stdout.toString();
      if (out.trim().isEmpty) return TailscaleStatus.unavailable;
      return parseStatus(out);
    } catch (e) {
      debugPrint('[Tailscale] status failed: $e');
      return TailscaleStatus.unavailable;
    }
  }

  /// Start a TLS-terminating reverse proxy from the tailnet to our [port].
  ///
  /// On success Tailscale provisions and auto-renews a publicly-trusted
  /// Let's Encrypt cert for the MagicDNS name with no extra step from us — so
  /// [TailscaleServeOutcome.ok] already means "HTTPS works". The one human gate
  /// is the tailnet-wide HTTPS toggle ([enableHttpsUrl]); when it's off, serve
  /// fails and we surface [TailscaleServeOutcome.httpsDisabled].
  Future<TailscaleServeResult> serve(int port) async {
    final st = await status();
    if (!st.running || st.magicDnsName == null) {
      return const TailscaleServeResult(TailscaleServeOutcome.notReady);
    }
    try {
      final result = await Process.run(_exe, [
        'serve',
        '--bg',
        '--https=443',
        'http://127.0.0.1:$port',
      ]);
      if (result.exitCode != 0) {
        final outcome =
            classifyServeFailure('${result.stderr}${result.stdout}');
        if (outcome == TailscaleServeOutcome.failed) {
          debugPrint('[Tailscale] serve failed: ${result.stderr}');
        }
        return TailscaleServeResult(outcome);
      }
      return TailscaleServeResult(
        TailscaleServeOutcome.ok,
        'https://${st.magicDnsName}',
      );
    } catch (e) {
      debugPrint('[Tailscale] serve error: $e');
      return const TailscaleServeResult(TailscaleServeOutcome.failed);
    }
  }

  /// Tear down the serve configuration we created.
  Future<void> serveOff() async {
    if (!isInstalled) return;
    try {
      await Process.run(_exe, ['serve', '--https=443', 'off']);
    } catch (_) {}
  }

  /// Classify a non-zero `tailscale serve` output. Tailscale rejects `--https`
  /// when the tailnet hasn't enabled HTTPS certificates; that message names
  /// "HTTPS" alongside an enable/disabled/feature hint and points at the admin
  /// page — the one case a human can fix. Everything else is a hard failure.
  /// Pure + exposed for testing.
  static TailscaleServeOutcome classifyServeFailure(String output) {
    final err = output.toLowerCase();
    if (err.contains('https') &&
        (err.contains('enable') ||
            err.contains('disabled') ||
            err.contains('not available') ||
            err.contains('feature'))) {
      return TailscaleServeOutcome.httpsDisabled;
    }
    return TailscaleServeOutcome.failed;
  }

  /// Pure parse of `tailscale status --json`. Exposed for testing.
  static TailscaleStatus parseStatus(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      if (data is! Map) return TailscaleStatus.unavailable;
      final self = data['Self'];
      final state = data['BackendState']?.toString() ?? 'NoState';
      String? dns;
      String? ip;
      if (self is Map) {
        final raw = self['DNSName']?.toString();
        if (raw != null && raw.isNotEmpty) {
          dns = raw.endsWith('.') ? raw.substring(0, raw.length - 1) : raw;
        }
        final ips = self['TailscaleIPs'];
        if (ips is List && ips.isNotEmpty) ip = ips.first.toString();
      }
      return TailscaleStatus(
        running: state == 'Running',
        backendState: state,
        magicDnsName: dns,
        ip: ip,
      );
    } catch (_) {
      return TailscaleStatus.unavailable;
    }
  }

  /// Where to download Tailscale (shown when it isn't installed).
  static const String installUrl = 'https://tailscale.com/download';

  /// Admin page hosting the one-time "HTTPS Certificates" toggle. Enabling it
  /// is a deliberate browser-only action (it publishes machine names to public
  /// certificate-transparency logs), so there is no CLI/API equivalent — we can
  /// only deep-link the user straight to it.
  static const String enableHttpsUrl =
      'https://login.tailscale.com/admin/dns';

  /// Tailscale mobile apps, for the phone-side install instructions.
  static const String iosAppUrl =
      'https://apps.apple.com/app/tailscale/id1470499037';
  static const String androidAppUrl =
      'https://play.google.com/store/apps/details?id=com.tailscale.ipn';

  /// Kick off interactive login (`tailscale up`) and return the auth URL the
  /// user should open in a browser — so they never need a terminal. The process
  /// keeps running in the background until the user completes login (after which
  /// `status()` flips to Running). Returns null if no URL was captured.
  Future<String?> login() async {
    if (!isInstalled) return null;
    try {
      final proc = await Process.start(_exe, ['up']);
      final completer = Completer<String?>();
      final urlRe = RegExp(r'https://login\.tailscale\.com/\S+');
      void scan(String line) {
        final m = urlRe.firstMatch(line);
        if (m != null && !completer.isCompleted) {
          completer.complete(m.group(0));
        }
      }

      proc.stdout.transform(const SystemEncoding().decoder).listen(scan);
      proc.stderr.transform(const SystemEncoding().decoder).listen(scan);
      // If `up` returns quickly (already logged in), there is no URL.
      proc.exitCode.then((_) {
        if (!completer.isCompleted) completer.complete(null);
      });
      return await completer.future
          .timeout(const Duration(seconds: 20), onTimeout: () => null);
    } catch (e) {
      debugPrint('[Tailscale] login error: $e');
      return null;
    }
  }

  static String _findExe() {
    const candidates = [
      'tailscale',
      '/usr/bin/tailscale',
      '/usr/local/bin/tailscale',
      '/Applications/Tailscale.app/Contents/MacOS/Tailscale',
      r'C:\Program Files\Tailscale\tailscale.exe',
    ];
    for (final c in candidates) {
      if (c == 'tailscale') {
        try {
          final r = Process.runSync(c, ['version']);
          if (r.exitCode == 0) return c;
        } catch (_) {}
      } else if (File(c).existsSync()) {
        return c;
      }
    }
    return '';
  }
}
