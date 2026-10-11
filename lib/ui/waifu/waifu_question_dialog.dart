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

import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/waifu/waifu_dialog_face.dart';

class WaifuQuestionDialog extends StatefulWidget {
  const WaifuQuestionDialog({
    super.key,
    required this.request,
    required this.name,
    this.portrait,
  });

  final WaifuQuestionRequest request;
  final String name;
  final File? portrait;

  @override
  State<WaifuQuestionDialog> createState() => _WaifuQuestionDialogState();
}

class _WaifuQuestionDialogState extends State<WaifuQuestionDialog> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _submitCustom() {
    final text = _custom.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final canAnswer = _custom.text.trim().isNotEmpty;
    return AlertDialog(
      backgroundColor: AppColors.cardOf(context),
      title: WaifuDialogFace(
        name: widget.name,
        portrait: widget.portrait,
        line: '${widget.name} has a question',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.request.prompt,
              key: const Key('waifu-question-prompt'),
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            for (final choice in widget.request.choices)
              ListTile(
                key: Key('waifu-question-$choice'),
                title: Text(
                  choice,
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
                onTap: () => Navigator.pop(context, choice),
              ),
            if (widget.request.choices.isNotEmpty) const SizedBox(height: 8),
            TextField(
              key: const Key('waifu-question-custom'),
              controller: _custom,
              autofocus: widget.request.choices.isEmpty,
              minLines: 1,
              maxLines: 4,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary(context),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submitCustom(),
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.request.choices.isEmpty
                    ? 'Type your answer'
                    : 'Or type a custom answer',
                hintStyle: TextStyle(color: AppColors.textTertiary(context)),
                filled: true,
                fillColor: AppColors.surfaceContainerOf(context),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: amber.withValues(alpha: 0.35)),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: Text(
            'Skip',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        FilledButton(
          key: const Key('waifu-question-answer'),
          onPressed: canAnswer ? _submitCustom : null,
          style: FilledButton.styleFrom(
            backgroundColor: amber,
            foregroundColor: AppColors.onChaosAccent,
          ),
          child: const Text('Answer'),
        ),
      ],
    );
  }
}
