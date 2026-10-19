// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Paste-a-key box for a Remote host with no key yet. The key goes into the
/// shared key vault for that host; chat's chosen provider is not changed.
class StudioRemoteKeyField extends StatefulWidget {
  const StudioRemoteKeyField({
    super.key,
    required this.label,
    required this.hint,
    required this.note,
    required this.onSave,
  });

  final String label;
  final String hint;
  final String note;
  final ValueChanged<String> onSave;

  @override
  State<StudioRemoteKeyField> createState() => _StudioRemoteKeyFieldState();
}

class _StudioRemoteKeyFieldState extends State<StudioRemoteKeyField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final key = _controller.text.trim();
    if (key.isEmpty) return;
    widget.onSave(key);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.textPrimary(context);
    final secondary = AppColors.textSecondary(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.label, style: TextStyle(color: primary, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('image-remote-key-field'),
                    controller: _controller,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('image-remote-key-save'),
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.porchAmberOf(context),
                    foregroundColor: AppColors.onAccentOf(context),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Save key'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(widget.note, style: TextStyle(color: secondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
