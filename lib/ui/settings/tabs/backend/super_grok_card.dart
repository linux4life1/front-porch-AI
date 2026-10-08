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
import 'package:url_launcher/url_launcher.dart';

import 'package:front_porch_ai/services/xai/xai.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Same words on the web card (`web_ui/src/components/SuperGrokCard.tsx`).
const kSuperGrokUnofficialWarning =
    'Unofficial. This signs in the same way xAI\'s own Grok CLI does, so '
    'the approval screen will say "Grok CLI". xAI has not approved Front '
    'Porch AI for this. xAI could block it at any time, and using it may '
    'go against xAI\'s terms for your account. Use it at your own risk — '
    'an xAI API key is the official route.';

/// Backend tab, xAI host: sign in with a SuperGrok subscription instead of
/// pasting an API key.
class SuperGrokCard extends StatelessWidget {
  const SuperGrokCard({super.key, required this.auth, this.onUseApiKey});

  final SuperGrokAuth auth;

  /// Reveals the xAI API key box. Sign-in is the main path; the key is the
  /// fallback, so it stays tucked away until asked for.
  final VoidCallback? onUseApiKey;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) => WarmCard(
        key: const Key('super-grok-card'),
        accent: AppColors.porchAmberOf(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context),
            const SizedBox(height: 8),
            ...switch (auth.phase) {
              SuperGrokPhase.signedOut => _signedOut(context),
              SuperGrokPhase.waiting => _waiting(context),
              SuperGrokPhase.signedIn => _signedIn(context),
            },
            if (auth.error != null) ...[
              const SizedBox(height: 8),
              _note(context, auth.error!, AppColors.negativeAccentOf(context)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final warn = AppColors.taskAccentOf(context);
    return Row(
      children: [
        Text(
          'SuperGrok sign-in',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: warn.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: warn.withValues(alpha: 0.5)),
          ),
          child: Text(
            'UNOFFICIAL',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: warn,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _signedOut(BuildContext context) => [
    _note(
      context,
      kSuperGrokUnofficialWarning,
      AppColors.taskAccentOf(context),
    ),
    const SizedBox(height: 10),
    _button(
      context,
      key: const Key('super-grok-sign-in'),
      icon: Icons.login,
      label: 'Sign in with SuperGrok',
      onPressed: () => auth.startSignIn(openBrowser: _open),
    ),
    const SizedBox(height: 6),
    Text(
      'Uses your SuperGrok or X Premium+ allowance instead of paid API '
      'credits.',
      style: TextStyle(fontSize: 12, color: AppColors.textTertiary(context)),
    ),
    if (onUseApiKey != null)
      TextButton(
        key: const Key('super-grok-use-key'),
        onPressed: onUseApiKey,
        child: const Text('Use an xAI API key instead'),
      ),
  ];

  List<Widget> _waiting(BuildContext context) => [
    Text(
      'Approve Front Porch AI in the browser window that just opened. If it '
      'asks for a code, enter:',
      style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
    ),
    const SizedBox(height: 8),
    SelectableText(
      auth.userCode ?? '',
      key: const Key('super-grok-code'),
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: AppColors.porchAmberOf(context),
      ),
    ),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        TextButton.icon(
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: auth.userCode ?? '')),
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy code'),
        ),
        TextButton.icon(
          onPressed: auth.verificationUri == null
              ? null
              : () => _open(auth.verificationUri!),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Open xAI again'),
        ),
        TextButton(onPressed: auth.cancelSignIn, child: const Text('Cancel')),
      ],
    ),
    Row(
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text(
          'Waiting for you to approve…',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary(context),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _signedIn(BuildContext context) => [
    Row(
      children: [
        Icon(
          Icons.check_circle,
          size: 18,
          color: AppColors.bondHighOf(context),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            auth.email == null
                ? 'Signed in with SuperGrok'
                : 'Signed in as ${auth.email}',
            key: const Key('super-grok-signed-in'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 6),
    Text(
      'xAI chat uses your subscription allowance, not API credits. Sign out '
      'to use an xAI API key instead.',
      style: TextStyle(fontSize: 12, color: AppColors.textTertiary(context)),
    ),
    if (auth.accessNote != null) ...[
      const SizedBox(height: 8),
      _note(context, auth.accessNote!, AppColors.taskAccentOf(context)),
    ],
    const SizedBox(height: 10),
    Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        TextButton.icon(
          onPressed: auth.checkAccess,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Check access'),
        ),
        TextButton.icon(
          key: const Key('super-grok-sign-out'),
          onPressed: auth.signOut,
          icon: const Icon(Icons.logout, size: 16),
          label: const Text('Sign out'),
        ),
      ],
    ),
    const SizedBox(height: 4),
    Text(
      'Unofficial — xAI may block this sign-in at any time.',
      style: TextStyle(fontSize: 11, color: AppColors.taskAccentOf(context)),
    ),
  ];

  Widget _note(BuildContext context, String text, Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(text, style: TextStyle(fontSize: 12, color: color)),
  );

  Widget _button(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      key: key,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.porchAmberOf(context),
        foregroundColor: AppColors.onChaosAccent,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    ),
  );

  static void _open(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return;
    launchUrl(parsed, mode: LaunchMode.externalApplication).catchError((
      Object e,
    ) {
      debugPrint('[SuperGrok] could not open browser: $e');
      return false;
    });
  }
}
