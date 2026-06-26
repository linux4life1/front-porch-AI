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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/web/tunnels/ngrok_provider.dart';
import 'package:front_porch_ai/services/web/tunnels/tailscale_provider.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';
import 'package:front_porch_ai/ui/dialogs/web_access/web_access_widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Where the local Tailscale daemon is in its lifecycle.
enum _TsDetect { notInstalled, needsLogin, off, ready }

/// The internet/phone guide: Tailscale-first, fully automated. When Tailscale
/// is signed in, one button binds the server to the tailnet, turns on HTTPS
/// (auto-cert), verifies it routes back, and shows a scannable phone link — or,
/// if the tailnet's HTTPS toggle is off, deep-links the user to enable it.
class InternetAccessStep extends StatefulWidget {
  const InternetAccessStep({super.key});

  @override
  State<InternetAccessStep> createState() => _InternetAccessStepState();
}

class _InternetAccessStepState extends State<InternetAccessStep> {
  late Future<_TsDetect> _detect;
  bool _busy = false;
  RemoteSetupResult? _result;

  @override
  void initState() {
    super.initState();
    _detect = _detectTailscale();
  }

  Future<_TsDetect> _detectTailscale() async {
    final p = TailscaleProvider();
    if (!p.isInstalled) return _TsDetect.notInstalled;
    final s = await p.status();
    if (s.needsLogin) return _TsDetect.needsLogin;
    if (s.running) return _TsDetect.ready;
    return _TsDetect.off;
  }

  void _recheckDetection() {
    setState(() {
      _result = null;
      _detect = _detectTailscale();
    });
  }

  Future<void> _runSetup({required bool restart}) async {
    setState(() => _busy = true);
    final host = context.read<WebServerHost>();
    final result = await host.setupRemoteAccess(restart: restart);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  Future<void> _signIn() async {
    setState(() => _busy = true);
    final url = await TailscaleProvider().login();
    if (!mounted) return;
    setState(() => _busy = false);
    if (url != null) await launchWebAccessUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Recommended: Tailscale',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _busy ? null : _recheckDetection,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Re-check'),
            ),
          ],
        ),
        Text(
          'A free, private network for your devices. It gives this PC a real '
          'HTTPS address with no browser warnings — so you can install the app '
          'on your phone and reach it from anywhere.',
          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
        ),
        const SizedBox(height: 12),
        FutureBuilder<_TsDetect>(
          future: _detect,
          builder: (context, snap) => snap.hasData
              ? _body(context, snap.data!)
              : const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
        ),
        const SizedBox(height: 16),
        Divider(color: AppColors.borderOf(context)),
        const SizedBox(height: 8),
        _ngrokFallback(context),
      ],
    );
  }

  Widget _body(BuildContext context, _TsDetect state) {
    switch (state) {
      case _TsDetect.notInstalled:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WebDetectRow(
              ok: false,
              badText: 'Tailscale isn\'t installed on this computer yet. I can '
                  'install it for you — you\'ll just approve your system\'s '
                  'admin prompt.',
            ),
            const SizedBox(height: 10),
            TailscaleInstallButton(onInstalled: _recheckDetection),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    launchWebAccessUrl(TailscaleProvider.installUrl),
                icon: const Icon(Icons.open_in_new, size: 15),
                label: const Text('Or download it myself'),
              ),
            ),
            const SizedBox(height: 8),
            const PhoneInstallCard(),
          ],
        );
      case _TsDetect.needsLogin:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WebDetectRow(
              ok: false,
              warn: true,
              badText: 'Tailscale is installed but not signed in on this PC. '
                  'I can open the sign-in page for you.',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.userBubble),
                onPressed: _busy ? null : _signIn,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login, size: 18),
                label: Text(_busy ? 'Opening…' : 'Sign in to Tailscale'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'After signing in, tap Re-check.',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
              ),
            ),
          ],
        );
      case _TsDetect.off:
        return WebDetectRow(
          ok: false,
          warn: true,
          badText: 'Tailscale is installed but turned off. Open the Tailscale '
              'app and connect this PC, then tap Re-check.',
        );
      case _TsDetect.ready:
        return _result == null
            ? _readyToSetUp(context)
            : _setupResult(context, _result!);
    }
  }

  Widget _readyToSetUp(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WebDetectRow(
          ok: true,
          okText: 'Tailscale is signed in and ready on this PC.',
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.userBubble,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _busy ? null : () => _runSetup(restart: true),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high),
            label: Text(_busy ? 'Setting everything up…' : 'Set it up for me'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'I\'ll open the network address, turn on free HTTPS (the certificate '
          'is handled automatically), and check it actually works.',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _setupResult(BuildContext context, RemoteSetupResult r) {
    switch (r.outcome) {
      case TailscaleServeOutcome.ok:
        return _liveResult(context, r);
      case TailscaleServeOutcome.httpsDisabled:
        return _enableHttpsResult(context, r);
      case TailscaleServeOutcome.notReady:
      case TailscaleServeOutcome.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WebDetectRow(
              ok: false,
              warn: true,
              badText: 'Couldn\'t finish automatic setup. Make sure Tailscale '
                  'is connected on this PC, then try again.',
              actionLabel: 'Try again',
              onAction: _busy ? null : () => _runSetup(restart: true),
            ),
            if (r.portUrl != null) ...[
              const SizedBox(height: 12),
              _addressBlock(context, r.portUrl!,
                  'Meanwhile, this address works on your tailnet:'),
            ],
          ],
        );
    }
  }

  // HTTPS is live (cert auto-provisioned). Show the clean no-port URL + QR.
  Widget _liveResult(BuildContext context, RemoteSetupResult r) {
    final url = r.httpsUrl!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WebDetectRow(
          ok: true,
          okText: r.reachable
              ? 'You\'re live and secure! Scan to open it on your phone.'
              : 'Secure HTTPS is on — the certificate may take a few seconds. '
                  'If the phone can\'t reach it yet, wait, then Re-verify.',
        ),
        const SizedBox(height: 12),
        Center(child: WebQrCode(data: url, caption: 'Scan with your phone')),
        const SizedBox(height: 12),
        WebUrlBox(url: url),
        if (!r.reachable) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _runSetup(restart: false),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Re-verify'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        const PhoneInstallCard(),
      ],
    );
  }

  // HTTPS certs aren't enabled for the tailnet — the one human gate. The port
  // URL works now (plain http); guide them to flip the one-time admin toggle.
  Widget _enableHttpsResult(BuildContext context, RemoteSetupResult r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (r.portUrl != null)
          _addressBlock(context, r.portUrl!,
              'This address works on your devices right now:'),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.userBubble.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.userBubble.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock, size: 18, color: AppColors.userBubble),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Turn on free HTTPS (one click, one time)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Your account hasn\'t enabled HTTPS certificates yet. Turning it '
                'on (free, in your browser) gets you:\n'
                '• A padlock with no security warnings\n'
                '• Install the app properly on your phone (offline, mic, push)\n'
                '• A clean address with no port to remember\n\n'
                'Click below, press "Enable HTTPS" on the Tailscale page, then '
                'come back and check again.',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.userBubble),
                    onPressed: () =>
                        launchWebAccessUrl(TailscaleProvider.enableHttpsUrl),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open Tailscale settings'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _runSetup(restart: false),
                    icon: _busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 16),
                    label: const Text('I\'ve enabled it — check again'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // A reusable "here's an address" block: QR + copyable URL + a lead-in line.
  Widget _addressBlock(BuildContext context, String url, String lead) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lead,
          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
        ),
        const SizedBox(height: 8),
        Center(child: WebQrCode(data: url, caption: 'Scan with your phone')),
        const SizedBox(height: 10),
        WebUrlBox(url: url),
      ],
    );
  }

  Widget _ngrokFallback(BuildContext context) {
    final installed = NgrokProvider().isInstalled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Alternative: ngrok',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(context),
          ),
        ),
        Text(
          'A quick public link. Easy to start, but the free URL changes each '
          'time. Finish ngrok setup on the Remote Access page in the web app.',
          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
        ),
        const SizedBox(height: 8),
        WebDetectRow(
          ok: installed,
          okText: 'ngrok detected — finish setup on the Remote Access page.',
          badText: 'ngrok not installed.',
          actionLabel: installed ? null : 'Download ngrok',
          onAction: () => launchWebAccessUrl(NgrokProvider.installUrl),
        ),
      ],
    );
  }
}
