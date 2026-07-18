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
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:front_porch_ai/services/web/tunnels/tailscale_installer.dart';
import 'package:front_porch_ai/services/web/tunnels/tailscale_provider.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Open [url] in the OS browser/app. Shared by every web-access guide.
Future<void> launchWebAccessUrl(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// A selectable URL with a one-tap copy button.
class WebUrlBox extends StatefulWidget {
  const WebUrlBox({super.key, required this.url});
  final String url;

  @override
  State<WebUrlBox> createState() => _WebUrlBoxState();
}

class _WebUrlBoxState extends State<WebUrlBox> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              widget.url,
              style: TextStyle(
                color: AppColors.userBubble,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _copy,
            icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
            label: Text(_copied ? 'Copied' : 'Copy'),
          ),
        ],
      ),
    );
  }
}

/// A scannable QR of [data] for opening the address on a phone. A QR must stay
/// high-contrast to scan, so it intentionally uses a fixed white background
/// with dark modules regardless of the app theme — the one place we don't
/// follow AppColors, because theming it would break scanning.
class WebQrCode extends StatelessWidget {
  const WebQrCode({super.key, required this.data, this.size = 168, this.caption});
  final String data;
  final double size;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white, // functional: QR contrast, not chrome
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: QrImageView(
            data: data,
            size: size,
            backgroundColor: Colors.white, // functional: QR contrast
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFF000000),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF000000),
            ),
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(
            caption!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

/// "Install Tailscale for me" — runs the OS-appropriate official installer
/// (App Store-free standalone pkg / winget / install.sh) and tells the user the
/// exact next step. [onInstalled] fires after a package-manager install so the
/// parent can re-detect automatically.
class TailscaleInstallButton extends StatefulWidget {
  const TailscaleInstallButton({super.key, this.onInstalled});
  final VoidCallback? onInstalled;

  @override
  State<TailscaleInstallButton> createState() => _TailscaleInstallButtonState();
}

class _TailscaleInstallButtonState extends State<TailscaleInstallButton> {
  bool _busy = false;
  TailscaleInstallResult? _result;

  Future<void> _install() async {
    setState(() => _busy = true);
    final result = await TailscaleInstaller().install();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
    if (result.outcome == TailscaleInstallOutcome.installed) {
      widget.onInstalled?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.userBubble),
          onPressed: _busy ? null : _install,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download, size: 18),
          label: Text(_busy ? 'Starting install…' : 'Install Tailscale for me'),
        ),
        if (_result != null) ...[
          const SizedBox(height: 8),
          _feedback(context, _result!),
        ],
      ],
    );
  }

  Widget _feedback(BuildContext context, TailscaleInstallResult r) {
    switch (r.outcome) {
      case TailscaleInstallOutcome.installed:
        return WebDetectRow(
          ok: true,
          okText: 'Tailscale is installed! Now sign in below (or tap Re-check).',
        );
      case TailscaleInstallOutcome.launchedInstaller:
        return WebDetectRow(
          ok: true,
          warn: true,
          okText: 'The Tailscale installer opened. Finish it (approve the admin '
              'prompt), then tap Re-check above.',
        );
      case TailscaleInstallOutcome.openedDownloadPage:
        return WebDetectRow(
          ok: false,
          warn: true,
          badText: 'I opened the Tailscale download page. Install it, then tap '
              'Re-check above.',
        );
      case TailscaleInstallOutcome.needsManualCommand:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste this into a terminal to install Tailscale, then Re-check:',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            WebUrlBox(url: r.command ?? TailscaleInstaller.linuxCommand),
          ],
        );
      case TailscaleInstallOutcome.unsupported:
      case TailscaleInstallOutcome.failed:
        return WebDetectRow(
          ok: false,
          badText: 'Couldn\'t start the installer automatically. Use the '
              'download button below instead.',
        );
    }
  }
}

/// Step-by-step guidance to install Tailscale on the user's phone, with direct
/// App Store / Play Store links and the "same account" reminder.
class PhoneInstallCard extends StatelessWidget {
  const PhoneInstallCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone_iphone, size: 18, color: AppColors.userBubble),
              const SizedBox(width: 8),
              Text(
                'Install Tailscale on your phone',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '1. Get the free Tailscale app:',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      launchWebAccessUrl(TailscaleProvider.iosAppUrl),
                  icon: const Icon(Icons.apple, size: 18),
                  label: const Text('iPhone / iPad'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      launchWebAccessUrl(TailscaleProvider.androidAppUrl),
                  icon: const Icon(Icons.android, size: 18),
                  label: const Text('Android'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '2. Sign in with the SAME account you used on this computer.\n'
            '3. Scan the code above (or open the address) — and you\'re in.',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Coloured info/warn banner with an optional action button.
class WebBanner extends StatelessWidget {
  const WebBanner({
    super.key,
    required this.color,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });
  final Color color;
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ),
          ],
        ],
      ),
    );
  }
}

/// A pass/warn/fail status row with optional numbered steps and an action.
class WebDetectRow extends StatelessWidget {
  const WebDetectRow({
    super.key,
    required this.ok,
    this.warn = false,
    this.okText = '',
    this.badText = '',
    this.steps,
    this.actionLabel,
    this.onAction,
  });
  final bool ok;
  final bool warn;
  final String okText;
  final String badText;
  final List<String>? steps;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final color = ok
        ? AppColors.logReady
        : (warn ? AppColors.logWarn : AppColors.logError);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ok ? Icons.check_circle : Icons.error_outline,
                color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ok ? okText : badText,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        if (steps != null) ...[
          const SizedBox(height: 8),
          for (var i = 0; i < steps!.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 4),
              child: Text(
                '${i + 1}. ${steps![i]}',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 13,
                ),
              ),
            ),
        ],
        if (actionLabel != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: FilledButton.tonal(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ),
        ],
      ],
    );
  }
}
