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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/backporch/stoop_aup.dart';

/// The Acceptable Use Policy gate. Shown once a user is signed in but has not
/// yet agreed to the live AUP version. The Stoop's content stays behind this
/// until they tick the box and accept; declining signs them out.
class StoopPolicyGate extends StatefulWidget {
  const StoopPolicyGate({super.key});

  @override
  State<StoopPolicyGate> createState() => _StoopPolicyGateState();
}

class _StoopPolicyGateState extends State<StoopPolicyGate> {
  bool _agreed = false;
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().acceptPolicy();
      // Success: AuthState notifies and the parent swaps the gate out.
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'Couldn’t save your agreement. Check your connection and try '
              'again.';
        });
      }
    }
  }

  Future<void> _decline() async {
    setState(() => _busy = true);
    await context.read<AuthState>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final version = context.select<AuthState, String>((a) => a.policyVersion);
    return Column(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                children: [
                  Text(
                    'Welcome to The Stoop',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Acceptable Use Policy'
                    '${version.isNotEmpty ? '  ·  v$version' : ''}',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    kStoopAupIntro,
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final section in kStoopAupSections)
                    _section(context, section),
                ],
              ),
            ),
          ),
        ),
        _actionBar(context),
      ],
    );
  }

  Widget _section(BuildContext context, StoopPolicySection section) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            section.body,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(top: BorderSide(color: AppColors.borderOf(context))),
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(
                    color: AppColors.resolve(
                      context,
                      Colors.redAccent,
                      Colors.red.shade700,
                    ),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              // Analytics choice surfaced HERE, not only the account menu, so the
              // user makes it before the first ping — which only fires once this
              // gate is accepted. Optional; sits above the required agreement.
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share anonymous analytics',
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Coarse device info — platform, app version, GPU tier — '
                          'to help guide development. Never your chats or '
                          'characters. Optional, and changeable anytime in your '
                          'account.',
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch(
                    value: context.select<AuthState, bool>(
                      (a) => a.analyticsEnabled,
                    ),
                    onChanged: _busy
                        ? null
                        : (v) =>
                              context.read<AuthState>().setAnalyticsEnabled(v),
                  ),
                ],
              ),
              Divider(height: 24, color: AppColors.borderOf(context)),
              InkWell(
                onTap: _busy ? null : () => setState(() => _agreed = !_agreed),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _agreed,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _agreed = v ?? false),
                      ),
                      Expanded(
                        child: Text(
                          'I am 18 or older and I have read and agree to The '
                          'Stoop’s Acceptable Use Policy.',
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy ? null : _decline,
                    child: const Text('Decline & sign out'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: (_agreed && !_busy) ? _accept : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Agree & continue'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
