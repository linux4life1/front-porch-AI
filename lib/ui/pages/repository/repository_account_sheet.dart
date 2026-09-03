// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_change_email_dialog.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_profile_header.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_twofa_sheet.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_verified_badge.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The Stoop account menu: NSFW visibility, account deletion, sign out.
/// Opened from the app-bar avatar; durable across the browse UI to come.
Future<void> showStoopAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: stoopCard2(context),
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _StoopAccountSheet(),
  );
}

class _StoopAccountSheet extends StatefulWidget {
  const _StoopAccountSheet();

  @override
  State<_StoopAccountSheet> createState() => _StoopAccountSheetState();
}

class _StoopAccountSheetState extends State<_StoopAccountSheet> {
  bool _nsfwBusy = false;

  Future<void> _toggleNsfw(bool value) async {
    setState(() => _nsfwBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AuthState>().setNsfwEnabled(value);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t update that. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _nsfwBusy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: stoopCard2(ctx),
        title: Text(
          'Delete your account?',
          style: TextStyle(color: stoopCream(ctx)),
        ),
        content: Text(
          'This permanently erases your Stoop account, every character you’ve '
          'uploaded, your votes, and your messages. This cannot be undone.',
          style: TextStyle(color: stoopCream2(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.stoopEmber,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await context.read<AuthState>().deleteAccount();
      navigator.pop(); // close the sheet; page swaps to the logged-out view
      messenger.showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Couldn’t delete the account. Check your connection.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthState>().user;
    if (user == null) return const SizedBox.shrink();
    final danger = stoopEmberText(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // Real profile picture when set; monogram otherwise. Name/bio/
                // photo editing lives in Edit Profile on the @you tab — this
                // sheet keeps the account/security switches.
                StoopCreatorAvatar(
                  assetId: user.avatarAssetId,
                  name: user.displayName,
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            user.displayName,
                            style: TextStyle(
                              color: stoopCream(context),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          StoopVerifiedBadge(
                            verification: user.verification,
                            size: 15,
                          ),
                        ],
                      ),
                      Text(
                        user.email,
                        style: TextStyle(
                          color: stoopCream2(context),
                          fontSize: 13,
                        ),
                      ),
                      if (user.pendingEmail != null)
                        Text(
                          '→ ${user.pendingEmail} (awaiting confirmation)',
                          style: TextStyle(
                            color: stoopAmberText(context),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // tileColor + shape (not a decorated wrapper): ListTile paints its
            // fill and ink on the ancestor Material, and a DecoratedBox on top
            // of that Material trips Flutter's ink-visibility assertion.
            SwitchListTile(
              tileColor: stoopBg1(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              value: user.nsfwEnabled,
              onChanged: _nsfwBusy ? null : _toggleNsfw,
              secondary: Icon(
                user.nsfwEnabled
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: stoopMute(context),
              ),
              title: Text(
                'Show NSFW content',
                style: TextStyle(color: stoopCream(context)),
              ),
              subtitle: Text(
                'Off by default. When on, adult cards appear in The Stoop.',
                style: TextStyle(color: stoopMute(context), fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              tileColor: stoopBg1(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              value: context.watch<AuthState>().analyticsEnabled,
              onChanged: (v) =>
                  context.read<AuthState>().setAnalyticsEnabled(v),
              secondary: Icon(
                Icons.insights_outlined,
                color: stoopMute(context),
              ),
              title: Text(
                'Share anonymous analytics',
                style: TextStyle(color: stoopCream(context)),
              ),
              subtitle: Text(
                'Coarse device info (platform, app version, GPU tier) to guide '
                'development. Never your chats or characters. On by default.',
                style: TextStyle(color: stoopMute(context), fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(
                user.twoFactorEnabled
                    ? Icons.lock_rounded
                    : Icons.lock_outline_rounded,
                color: user.twoFactorEnabled
                    ? stoopTealText(context)
                    : stoopMute(context),
              ),
              title: Text(
                'Two-factor authentication',
                style: TextStyle(color: stoopCream(context)),
              ),
              subtitle: Text(
                user.twoFactorEnabled
                    ? 'On — a code is required at sign-in.'
                    : 'Off — add an authenticator app to protect your account.',
                style: TextStyle(color: stoopMute(context), fontSize: 12),
              ),
              trailing: Text(
                user.twoFactorEnabled ? 'On' : 'Off',
                style: TextStyle(
                  color: user.twoFactorEnabled
                      ? stoopTealText(context)
                      : stoopMute(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => showStoopTwoFactor(context),
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(
                Icons.alternate_email_rounded,
                color: stoopMute(context),
              ),
              title: Text(
                'Change email',
                style: TextStyle(color: stoopCream(context)),
              ),
              subtitle: Text(
                user.pendingEmail != null
                    ? 'Waiting on ${user.pendingEmail} to confirm'
                    : 'A confirmation link goes to the new address first.',
                style: TextStyle(color: stoopMute(context), fontSize: 12),
              ),
              onTap: () => showStoopChangeEmail(context),
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(Icons.logout, color: stoopMute(context)),
              title: Text(
                'Log out',
                style: TextStyle(color: stoopCream(context)),
              ),
              onTap: () async {
                final navigator = Navigator.of(context);
                await context.read<AuthState>().logout();
                navigator.pop();
              },
            ),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(Icons.delete_forever_outlined, color: danger),
              title: Text('Delete my account', style: TextStyle(color: danger)),
              subtitle: Text(
                'Permanently erase your account and uploads',
                style: TextStyle(color: stoopMute(context), fontSize: 12),
              ),
              onTap: _confirmDelete,
            ),
          ],
        ),
      ),
    );
  }
}
