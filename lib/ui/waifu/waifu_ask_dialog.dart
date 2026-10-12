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
import 'package:flutter/services.dart';

import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/waifu/waifu_dialog_face.dart';

/// Her permission ask. Shows the whole command or path, defaults to
/// Allow once, and answers Y / N from the keyboard.
class WaifuAskDialog extends StatelessWidget {
  const WaifuAskDialog({
    super.key,
    required this.request,
    required this.name,
    this.portrait,
  });

  final WaifuAskRequest request;
  final String name;
  final File? portrait;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    void answer(WaifuAskDecision d) => Navigator.pop(context, d);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyY): () =>
            answer(WaifuAskDecision.allowOnce),
        const SingleActivator(LogicalKeyboardKey.keyN): () =>
            answer(WaifuAskDecision.deny),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            answer(WaifuAskDecision.deny),
      },
      child: AlertDialog(
        backgroundColor: AppColors.cardOf(context),
        title: WaifuDialogFace(
          name: name,
          portrait: portrait,
          line: waifuAskHeadline(name, request),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (request.why.isNotEmpty) ...[
                Text(
                  request.why,
                  key: const Key('waifu-ask-why'),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (request.summary.trim().isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.insetPanelOf(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    request.summary,
                    key: const Key('waifu-ask-detail'),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Y allows once · N denies',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('waifu-ask-deny'),
            onPressed: () => answer(WaifuAskDecision.deny),
            child: Text(
              'Deny',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          TextButton(
            key: const Key('waifu-ask-always'),
            onPressed: () => answer(WaifuAskDecision.allowAlways),
            child: Text('Always this session', style: TextStyle(color: amber)),
          ),
          FilledButton(
            key: const Key('waifu-ask-once'),
            autofocus: true,
            onPressed: () => answer(WaifuAskDecision.allowOnce),
            style: FilledButton.styleFrom(
              backgroundColor: amber,
              foregroundColor: AppColors.onChaosAccent,
            ),
            child: const Text('Allow once'),
          ),
        ],
      ),
    );
  }
}
