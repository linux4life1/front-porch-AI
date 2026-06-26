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

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';
import 'package:front_porch_ai/ui/dialogs/web_access/web_access_internet_step.dart';
import 'package:front_porch_ai/ui/dialogs/web_access/web_access_widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// How the user intends to reach the web interface — drives the guidance.
enum WebAccessMode { thisPc, lan, internet }

/// Tutorial shown when the web server is first enabled, guiding the user to the
/// right access method (local / LAN / internet), funnelling toward Tailscale for
/// internet use, offering ngrok, and detecting whether each tool is set up.
class WebAccessSetupDialog extends StatefulWidget {
  const WebAccessSetupDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog(
        context: context,
        builder: (_) => const WebAccessSetupDialog(),
      );

  @override
  State<WebAccessSetupDialog> createState() => _WebAccessSetupDialogState();
}

class _WebAccessSetupDialogState extends State<WebAccessSetupDialog> {
  WebAccessMode? _mode;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _mode == null ? _buildChoice(context) : _buildGuide(context),
        ),
      ),
    );
  }

  // ── Step 1: how will you use it? ─────────────────────────────────────────
  Widget _buildChoice(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How will you use the web interface?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Pick the closest match — we\'ll walk you through it.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        const SizedBox(height: 16),
        _choiceCard(
          context,
          icon: Icons.computer,
          title: 'On this computer',
          subtitle: 'Just open it in a browser on this PC. No setup.',
          mode: WebAccessMode.thisPc,
        ),
        _choiceCard(
          context,
          icon: Icons.wifi,
          title: 'Another device on my home Wi-Fi',
          subtitle: 'A second PC, tablet, or phone on the same network.',
          mode: WebAccessMode.lan,
        ),
        _choiceCard(
          context,
          icon: Icons.public,
          title: 'My phone, or over the internet',
          subtitle: 'Reach it from anywhere — installable as an app.',
          mode: WebAccessMode.internet,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Skip'),
          ),
        ),
      ],
    );
  }

  Widget _choiceCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required WebAccessMode mode,
  }) {
    return Card(
      color: AppColors.cardOf(context),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.borderOf(context)),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.userBubble),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary(context),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        trailing: Icon(Icons.chevron_right, color: AppColors.iconSecondary(context)),
        onTap: () => setState(() => _mode = mode),
      ),
    );
  }

  // ── Step 2: guidance per mode ────────────────────────────────────────────
  Widget _buildGuide(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: AppColors.iconSecondary(context)),
              onPressed: () => setState(() => _mode = null),
            ),
            Expanded(
              child: Text(
                _titleFor(_mode!),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Flexible(
          child: SingleChildScrollView(
            child: switch (_mode!) {
              WebAccessMode.thisPc => _thisPcGuide(context),
              WebAccessMode.lan => _lanGuide(context),
              WebAccessMode.internet => const InternetAccessStep(),
            },
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.userBubble),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  String _titleFor(WebAccessMode m) => switch (m) {
        WebAccessMode.thisPc => 'On this computer',
        WebAccessMode.lan => 'On your home Wi-Fi',
        WebAccessMode.internet => 'Over the internet',
      };

  Widget _thisPcGuide(BuildContext context) {
    final port = context.read<WebServerHost>().port;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Open this address in any browser on this computer:',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        const SizedBox(height: 8),
        WebUrlBox(url: 'http://localhost:$port'),
        const SizedBox(height: 8),
        Text(
          'localhost is treated as secure, so you can install it as an app right '
          'from this PC. The first visit asks you to create your login.',
          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
        ),
      ],
    );
  }

  Widget _lanGuide(BuildContext context) {
    final host = context.read<WebServerHost>();
    final storage = context.read<StorageService>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!storage.webServerSettings.webServerAllowLan)
          WebBanner(
            color: AppColors.logWarn,
            icon: Icons.lock_open,
            text: 'LAN access is off. Turn it on so other devices on your Wi-Fi '
                'can connect, then this PC will show its network address.',
            actionLabel: 'Allow LAN access',
            onAction: () async {
              await storage.webServerSettings.setWebServerAllowLan(true);
              if (host.isRunning) {
                await host.stop();
                await host.start(storage.webServerSettings.webServerPort);
              }
              if (context.mounted) setState(() {});
            },
          )
        else ...[
          Text(
            'Open this address in a browser on the other device:',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 8),
          WebUrlBox(
            url:
                'http://${host.lanIp ?? 'your-pc-ip'}:${storage.webServerSettings.webServerPort}',
          ),
        ],
        const SizedBox(height: 12),
        WebBanner(
          color: AppColors.userBubble,
          icon: Icons.info_outline,
          text: 'Home Wi-Fi uses plain HTTP, so it works in a browser tab but '
              'can\'t be installed as an app. To install it on a phone (or reach '
              'it away from home), use Tailscale.',
          actionLabel: 'Set up Tailscale instead',
          onAction: () => setState(() => _mode = WebAccessMode.internet),
        ),
      ],
    );
  }
}
