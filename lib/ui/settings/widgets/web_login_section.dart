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
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final info = await widget.auth.accountInfo();
    if (mounted) {
      setState(() {
        _info = info;
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
        content: Text(
          'Web login reset — create a new one from the browser.',
        ),
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
      return Text(
        'No web login yet — it’s created in the browser on first visit.',
        style: labelStyle,
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
