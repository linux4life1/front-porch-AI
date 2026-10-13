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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Step 2 of "Start New Chat": *which of you* is walking into this scene.
///
/// A fresh chat must never silently inherit whatever persona the last one used
/// — the same character can be met by a different you — so this asks outright.
/// Returns the chosen persona id, or null when cancelled (the caller then
/// starts nothing at all).
///
/// [subject] names who the chat is with, so the ask reads as one continuous
/// action ("Start a new chat with Misty as…").
Future<String?> showPersonaPickerDialog(
  BuildContext context, {
  required String subject,
}) {
  final service = Provider.of<UserPersonaService>(context, listen: false);
  final personas = service.personas;
  // New chats start as the default (the persona the Personas page shows),
  // not whoever the last open chat happened to speak as.
  final defaultId = service.defaultPersona.id;

  return showWarmDialog<String>(
    context,
    title: 'Start a new chat with $subject as…',
    icon: Icons.person_outline,
    accent: AppColors.porchAmberOf(context),
    width: 420,
    content: SizedBox(
      width: 420,
      child: personas.isEmpty
          // Can't happen through normal use (the service seeds a default
          // "User"), but a dialog that can render nothing is a dead end.
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No personas yet — the chat will use your default.',
                style: TextStyle(color: AppColors.textTertiary(context)),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in personas)
                    _PersonaTile(
                      label: p.displayLabel,
                      name: p.name,
                      persona: p.persona,
                      avatarPath: p.avatarPath,
                      isDefault: p.id == defaultId,
                      onTap: () => Navigator.pop(context, p.id),
                    ),
                ],
              ),
            ),
    ),
    actions: [warmDialogCancel(context)],
  );
}

class _PersonaTile extends StatelessWidget {
  const _PersonaTile({
    required this.label,
    required this.name,
    required this.persona,
    required this.avatarPath,
    required this.isDefault,
    required this.onTap,
  });

  final String label;
  final String name;
  final String persona;
  final String? avatarPath;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchAmberOf(context);
    // A one-line hint of who this persona is, so identically-named personas
    // ("User") are still tellable apart at a glance.
    final blurb = persona.trim().isNotEmpty
        ? persona.trim().replaceAll(RegExp(r'\s+'), ' ')
        : (label == name ? '' : name);
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.surfaceContainerOf(context),
        backgroundImage: (avatarPath != null && avatarPath!.isNotEmpty)
            ? FileImage(File(avatarPath!))
            : null,
        // A persona whose avatar file vanished still renders.
        onBackgroundImageError: (avatarPath != null && avatarPath!.isNotEmpty)
            ? (_, _) {}
            : null,
        child: (avatarPath == null || avatarPath!.isEmpty)
            ? Icon(
                Icons.person,
                size: 20,
                color: AppColors.iconSecondary(context),
              )
            : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isDefault) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Default',
                style: TextStyle(fontSize: 10.5, color: accent),
              ),
            ),
          ],
        ],
      ),
      subtitle: blurb.isEmpty
          ? null
          : Text(
              blurb,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
              ),
            ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: onTap,
    );
  }
}
