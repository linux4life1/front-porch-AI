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
import 'package:front_porch_ai/ui/pages/repository/stoop_twofa_sheet.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The Stoop account menu: NSFW visibility, account deletion, sign out.
/// Opened from the app-bar avatar; durable across the browse UI to come.
Future<void> showStoopAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.cardOf(context),
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

  Future<void> _editDisplayName(String current) async {
    final controller = TextEditingController(text: current);
    final messenger = ScaffoldMessenger.of(context);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardOf(ctx),
        title: Text(
          'Display name',
          style: TextStyle(color: AppColors.textPrimary(ctx)),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          style: TextStyle(color: AppColors.textPrimary(ctx)),
          decoration: InputDecoration(
            hintText: 'How others see you on The Stoop',
            hintStyle: TextStyle(color: AppColors.textTertiary(ctx)),
            helperText: 'This is your public name on cards and profiles.',
            helperStyle: TextStyle(color: AppColors.textTertiary(ctx)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName == current || !mounted) return;
    if (newName.length < 2) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Name must be at least 2 characters.')),
      );
      return;
    }
    try {
      await context.read<AuthState>().setDisplayName(newName);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t update your name. Try again.')),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardOf(ctx),
        title: Text(
          'Delete your account?',
          style: TextStyle(color: AppColors.textPrimary(ctx)),
        ),
        content: Text(
          'This permanently erases your Stoop account, every character you’ve '
          'uploaded, your votes, and your messages. This cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.resolve(
                ctx,
                Colors.red.shade600,
                Colors.red.shade700,
              ),
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
    final danger = AppColors.resolve(
      context,
      Colors.redAccent,
      Colors.red.shade700,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.surfaceContainerOf(context),
                  child: Text(
                    user.displayName.isNotEmpty
                        ? user.displayName.characters.first.toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        user.email,
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Change display name',
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: AppColors.iconSecondary(context),
                  ),
                  onPressed: () => _editDisplayName(user.displayName),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                value: user.nsfwEnabled,
                onChanged: _nsfwBusy ? null : _toggleNsfw,
                secondary: Icon(
                  user.nsfwEnabled
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.iconSecondary(context),
                ),
                title: Text(
                  'Show NSFW content',
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
                subtitle: Text(
                  'Off by default. When on, adult cards appear in The Stoop.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                value: context.watch<AuthState>().analyticsEnabled,
                onChanged: (v) =>
                    context.read<AuthState>().setAnalyticsEnabled(v),
                secondary: Icon(
                  Icons.insights_outlined,
                  color: AppColors.iconSecondary(context),
                ),
                title: Text(
                  'Share anonymous analytics',
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
                subtitle: Text(
                  'Coarse device info (platform, app version, GPU tier) to guide '
                  'development. Never your chats or characters. On by default.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
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
                    ? AppColors.resolve(context, Colors.tealAccent, Colors.teal)
                    : AppColors.iconSecondary(context),
              ),
              title: Text(
                'Two-factor authentication',
                style: TextStyle(color: AppColors.textPrimary(context)),
              ),
              subtitle: Text(
                user.twoFactorEnabled
                    ? 'On — a code is required at sign-in.'
                    : 'Off — add an authenticator app to protect your account.',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                ),
              ),
              trailing: Text(
                user.twoFactorEnabled ? 'On' : 'Off',
                style: TextStyle(
                  color: user.twoFactorEnabled
                      ? AppColors.resolve(context, Colors.tealAccent, Colors.teal)
                      : AppColors.textTertiary(context),
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
                Icons.logout,
                color: AppColors.iconSecondary(context),
              ),
              title: Text(
                'Log out',
                style: TextStyle(color: AppColors.textPrimary(context)),
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
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                ),
              ),
              onTap: _confirmDelete,
            ),
          ],
        ),
      ),
    );
  }
}
