// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Paste a personal CivitAI API key. There is no password field.
class CivitaiSheet extends StatefulWidget {
  const CivitaiSheet({super.key, required this.onSave});

  /// Saves the key. Returns an error sentence, or null when it was stored.
  final Future<String?> Function(String token) onSave;

  @override
  State<CivitaiSheet> createState() => _CivitaiSheetState();
}

class _CivitaiSheetState extends State<CivitaiSheet> {
  final TextEditingController _token = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final token = pastedCivitaiToken({'token': _token.text});
    if (token == null) {
      setState(() => _error = 'Paste the API key from your CivitAI account.');
      return;
    }
    final error = await widget.onSave(token);
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      title: Text(
        'CivitAI sign-in',
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: TextField(
        controller: _token,
        obscureText: true,
        decoration: InputDecoration(labelText: 'API key', errorText: _error),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save key')),
      ],
    );
  }
}
