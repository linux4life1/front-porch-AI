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

import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The desktop-side web-login card shown inside Settings → Web Server.
///
/// The desktop is the root of trust for the web account: whoever sits at this
/// machine already owns the database, so local access is strictly a stronger
/// credential than the web password. This card therefore offers the recovery
/// actions that must never exist over the network — "sign out all devices"
/// and "reset web login" (wipes the account + sessions, returning the browser
/// to first-run setup). Day-to-day changes (username/password/2FA) live in
/// the web UI's Account page, gated by re-authentication.
class WebLoginSection extends StatefulWidget {
  const WebLoginSection({required this.auth, super.key});

  final AuthService auth;

  @override
  State<WebLoginSection> createState() => _WebLoginSectionState();
}

class _WebLoginSectionState extends State<WebLoginSection> {
  ({String username, bool totpEnabled})? _info;
  String? _setupToken;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // A login made (or changed) from a phone lands here without a reopen.
    widget.auth.accountChanges.addListener(_refresh);
    _refresh();
  }

  @override
  void didUpdateWidget(WebLoginSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.auth, widget.auth)) return;
    oldWidget.auth.accountChanges.removeListener(_refresh);
    widget.auth.accountChanges.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    widget.auth.accountChanges.removeListener(_refresh);
    super.dispose();
  }

  /// Bumped per refresh: only the newest read may draw, so a read begun
  /// before the phone made the login cannot land late and undo it.
  int _refreshGen = 0;

  Future<void> _refresh() async {
    final gen = ++_refreshGen;
    final info = await widget.auth.accountInfo();
    final token = info == null
        ? await widget.auth.setupTokenForDesktop()
        : null;
    if (mounted && gen == _refreshGen) {
      setState(() {
        _info = info;
        _setupToken = token;
        _loaded = true;
      });
    }
  }

  Future<void> _signOutAll() async {
    final messenger = ScaffoldMessenger.of(context);
    await widget.auth.signOutAllDevices();
    messenger.showSnackBar(
      const SnackBar(content: Text('All web devices were signed out.')),
    );
  }

  Future<void> _resetLogin() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset web login?'),
        content: const Text(
          'This erases the web username, password and 2FA, and signs out '
          'every device. The next browser visit will show the first-run '
          'setup page to create a new login.\n\nYour characters, chats and '
          'settings are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Reset login',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.auth.resetAccount();
    await _refresh();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Web login reset — create a new one from the browser.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final info = _info;
    final labelStyle = TextStyle(
      color: AppColors.textSecondary(context),
      fontSize: 12,
    );
    if (info == null) {
      final token = _setupToken;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No web login yet. On this computer, open the browser at '
            'localhost and create the account. From another device, phone, '
            'or a public tunnel, enter this one-time setup code:',
            style: labelStyle,
          ),
          if (token != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              token,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: token));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Setup code copied.')),
                );
              },
              child: const Text(
                'Copy setup code',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Signed-in user: ${info.username}'
          '${info.totpEnabled ? '  ·  2FA on' : ''}',
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Change the username/password from the web UI’s Account page. '
          'Forgot it? Reset here — this computer is the recovery key.',
          style: labelStyle,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: _signOutAll,
              child: const Text(
                'Sign out all devices',
                style: TextStyle(fontSize: 12),
              ),
            ),
            OutlinedButton(
              onPressed: _resetLogin,
              child: Text(
                'Reset web login…',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
