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

/// The ONE text-prompt dialog for group objectives: adding an objective and
/// renaming a task were two copies of the same AlertDialog differing only in
/// their labels. Returns the TRIMMED text, or null when cancelled or left
/// blank, so no caller re-checks for empty. Disposes its controller; neither
/// copy did.
Future<String?> promptForObjectiveText(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? hint,
  String? initial,
}) async {
  final ctrl = TextEditingController(text: initial);
  try {
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: hint == null ? null : InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    final trimmed = text?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  } finally {
    ctrl.dispose();
  }
}
