// Copyright (C) 2026 Front Porch AI — SPDX-License-Identifier: AGPL-3.0-or-later
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
//
// "Confirm your email" banner for The Stoop — desktop twin of the hub's
// `verifyBanner`. Sharing, reporting, and a profile photo stay locked until
// they confirm; browsing and downloading stay open.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class StoopVerifyBanner extends StatefulWidget {
  const StoopVerifyBanner({super.key});

  @override
  State<StoopVerifyBanner> createState() => _StoopVerifyBannerState();
}

class _StoopVerifyBannerState extends State<StoopVerifyBanner> {
  bool _sending = false;

  Future<void> _resend(AuthState auth) async {
    final token = auth.accessToken;
    if (token == null || _sending) return;
    setState(() => _sending = true);
    String message;
    try {
      await BackporchApi().resendVerification(token);
      message = 'Sent. Check your inbox, and the spam folder just in case.';
    } on BackporchApiException catch (e) {
      message = e.code == 'resend_too_soon'
          ? 'One just went out — give it a couple of minutes before asking again.'
          : 'Couldn’t send that right now. Try again shortly.';
    } catch (_) {
      message = 'Couldn’t send that right now. Check your connection.';
    }
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.user;
    // Nothing to say when verified — or when talking to an older server that
    // doesn't report the field (the model defaults it true).
    if (user == null || user.emailVerified) return const SizedBox.shrink();

    final amber = AppColors.porchAmberOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: amber.withValues(alpha: 0.35)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: amber),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.mark_email_unread_outlined,
                        size: 20,
                        color: amber,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Confirm your email to share cards, report characters, and set a profile photo.',
                              style: TextStyle(
                                color: amber,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'We sent a link to ${user.email}. Browsing and downloading '
                              'work without it — confirming unlocks sharing, reporting, '
                              'and a profile photo.',
                              style: TextStyle(
                                color: stoopCream(
                                  context,
                                ).withValues(alpha: 0.85),
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: _sending ? null : () => _resend(auth),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.onChaosAccent,
                          backgroundColor: amber,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        child: Text(_sending ? 'Sending…' : 'Send it again'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
