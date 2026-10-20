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
//
// The external-image consent flow: the one-time "allow images from the
// internet?" dialog (risk list + per-character persisted consent) that
// MessageBubble raises via onRequestImagePermission.

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// The chat page's answer to "may this chat load images from the internet?".
/// [allowed] is null until asked; [onDecided] rebuilds the owning page after
/// [allowed] changes (only while the page is still mounted).
class ExternalImageConsent {
  ExternalImageConsent({required this.onDecided});

  final VoidCallback onDecided;

  /// Null = not decided yet this page; feeds MessageBubble.
  bool? allowed;
  bool _checked = false;

  /// Raise the consent dialog (or answer from the persisted per-character
  /// consent) from the chat page's [context].
  Future<bool> request(BuildContext context) async {
    if (allowed != null) {
      return allowed!;
    }
    // Check persisted consent first
    if (!_checked) {
      _checked = true;
      final prefs = await SharedPreferences.getInstance();
      final consented = prefs.getStringList('image_consent_characters') ?? [];
      final charName =
          Provider.of<ChatService>(
            context,
            listen: false,
          ).activeCharacter?.name ??
          '';
      if (charName.isNotEmpty && consented.contains(charName)) {
        if (context.mounted) {
          allowed = true;
          onDecided();
        }
        return true;
      }
    }
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardOf(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Icon(
          Icons.shield_outlined,
          color: StatusColors.warningOf(ctx),
          size: 36,
        ),
        title: Text(
          'External Image Detected',
          style: TextStyle(
            color: AppColors.textPrimary(ctx),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This message contains images hosted on an external server. '
              'Loading them carries security risks:',
              style: TextStyle(
                color: AppColors.textSecondary(ctx),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            _buildRiskItem(
              ctx,
              Icons.visibility,
              'Your IP address will be exposed to the image host',
            ),
            _buildRiskItem(
              ctx,
              Icons.bug_report,
              'Maliciously crafted images could potentially exploit vulnerabilities',
            ),
            _buildRiskItem(
              ctx,
              Icons.track_changes,
              'The URL may be used for tracking',
            ),
            const SizedBox(height: 16),
            Text(
              'The source has not been verified as safe.',
              style: TextStyle(
                color: StatusColors.warningOf(ctx).withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Block Images',
              style: TextStyle(color: AppColors.textSecondary(ctx)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: StatusColors.warningFill,
              foregroundColor: StatusColors.onWarningFill,
            ),
            child: const Text('Accept Risk & Load'),
          ),
        ],
      ),
    );
    final decided = result ?? false;
    if (decided) {
      // Persist consent for this character
      final prefs = await SharedPreferences.getInstance();
      final charName =
          Provider.of<ChatService>(
            context,
            listen: false,
          ).activeCharacter?.name ??
          '';
      if (charName.isNotEmpty) {
        final consented = prefs.getStringList('image_consent_characters') ?? [];
        if (!consented.contains(charName)) {
          consented.add(charName);
          await prefs.setStringList('image_consent_characters', consented);
        }
      }
    }
    if (context.mounted) {
      allowed = decided;
      onDecided();
    }
    return decided;
  }
}

Widget _buildRiskItem(BuildContext context, IconData icon, String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: StatusColors.warningOf(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}
