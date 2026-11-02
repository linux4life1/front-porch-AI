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

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';

/// Asks for a new preset name. A name in [taken] is refused, so Save as new
/// never overwrites; the bar's own Save does that. Null when cancelled.
Future<String?> askGenPresetName(
  BuildContext context, {
  required Iterable<String> taken,
  String title = 'Save as new preset',
}) => showWarmDialogOf<String>(
  context,
  builder: (_) => _NameDialog(title: title, taken: taken.toSet()),
);

/// Confirms deleting preset [name]. True to delete.
Future<bool> confirmGenPresetDelete(BuildContext context, String name) async {
  final yes = await showWarmDialog<bool>(
    context,
    title: 'Delete “$name”?',
    icon: Icons.delete_outline,
    destructive: true,
    content: const WarmDialogText(
      'The preset is removed, and any model linked to it keeps the values '
      'it has.',
    ),
    actions: [
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
      ),
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ),
    ],
  );
  return yes == true;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.taken});

  final String title;
  final Set<String> taken;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (_done || name.isEmpty) return;
    if (widget.taken.contains(name)) {
      setState(
        () => _error =
            'You already have a preset called “$name”. Pick another name.',
      );
      return;
    }
    _done = true;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return WarmDialog(
      title: widget.title,
      icon: Icons.save_outlined,
      content: TextField(
        key: const ValueKey('gen-preset-name'),
        controller: _controller,
        autofocus: true,
        style: TextStyle(color: AppColors.textPrimary(context)),
        decoration: InputDecoration(
          hintText: 'Preset name...',
          hintStyle: TextStyle(color: AppColors.textTertiary(context)),
          errorText: _error,
          errorMaxLines: 3,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.formAccentOf(context),
            foregroundColor: AppColors.onAccentOf(context),
          ),
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
