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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The severe "type DELETE to confirm" gate for mass-destructive actions
/// (bulk character delete, delete-folder-with-characters). A plain confirm
/// button is too easy to click through when the blast radius is 100+
/// characters and their chat histories — this one stays disabled until the
/// user types the keyword exactly.
///
/// Returns true only on a typed-and-confirmed delete.
Future<bool> showTypeDeleteDialog(
  BuildContext context, {
  required String title,
  required String message,
  String keyword = 'DELETE',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => _TypeDeleteDialog(
      title: title,
      message: message,
      keyword: keyword,
    ),
  );
  return confirmed == true;
}

class _TypeDeleteDialog extends StatefulWidget {
  final String title;
  final String message;
  final String keyword;

  const _TypeDeleteDialog({
    required this.title,
    required this.message,
    required this.keyword,
  });

  @override
  State<_TypeDeleteDialog> createState() => _TypeDeleteDialogState();
}

class _TypeDeleteDialogState extends State<_TypeDeleteDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final danger = AppColors.negativeAccentOf(context);
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: danger.withValues(alpha: 0.6), width: 1.5),
      ),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.title,
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.message,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Type ${widget.keyword} to confirm:',
              style: TextStyle(
                color: danger,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              style: TextStyle(color: AppColors.textPrimary(context)),
              onChanged: (v) =>
                  setState(() => _matches = v.trim() == widget.keyword),
              onSubmitted: (_) {
                if (_matches) Navigator.of(context).pop(true);
              },
              decoration: InputDecoration(
                hintText: widget.keyword,
                hintStyle: TextStyle(color: AppColors.textTertiary(context)),
                filled: true,
                fillColor: AppColors.surfaceContainerOf(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: danger.withValues(alpha: 0.4),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: danger.withValues(alpha: 0.4),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: danger),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          icon: const Icon(Icons.delete_forever, size: 18),
          label: const Text('Delete Permanently'),
          style: ElevatedButton.styleFrom(
            backgroundColor: danger,
            foregroundColor: AppColors.userText,
            disabledBackgroundColor: AppColors.surfaceContainerOf(context),
          ),
        ),
      ],
    );
  }
}
