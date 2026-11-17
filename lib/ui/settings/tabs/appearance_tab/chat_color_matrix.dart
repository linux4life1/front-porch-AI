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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/dialogs/color_picker_dialog.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// A compact, paired matrix for configuring chat bubble and text colors.
/// Pairs bubble fill and text ink to display immediate contrast relationships.
class ChatColorMatrix extends StatelessWidget {
  const ChatColorMatrix({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final ui = storage.uiSettings;
    final corners = AppCorners.of(context);

    final userBg = ui.globalUserBubbleColor;
    final userFg = ui.globalUserTextColor;
    final aiBg = ui.globalAiBubbleColor;
    final aiFg = ui.globalAiTextColor;
    final dialogue = ui.globalDialogueColor;
    final action = ui.globalActionColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 540;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                // User Message Group
                SizedBox(
                  width: isWide ? (constraints.maxWidth - 16) / 2 : double.infinity,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardOf(context),
                      borderRadius: corners.circular(10),
                      border: Border.all(
                        color: AppColors.borderOf(context),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'USER MESSAGE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            _ColorChip(
                              key: const ValueKey('chat-color-user-bubble'),
                              label: 'Bubble Fill',
                              color: userBg,
                              onTap: () => showColorPicker(
                                context,
                                userBg,
                                ui.setGlobalUserBubbleColor,
                              ),
                            ),
                            _PairedInkChip(
                              key: const ValueKey('chat-color-user-text'),
                              label: 'Text Ink',
                              inkColor: userFg,
                              bgColor: userBg,
                              onTap: () => showColorPicker(
                                context,
                                userFg,
                                ui.setGlobalUserTextColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // AI Character Message Group
                SizedBox(
                  width: isWide ? (constraints.maxWidth - 16) / 2 : double.infinity,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardOf(context),
                      borderRadius: corners.circular(10),
                      border: Border.all(
                        color: AppColors.borderOf(context),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CHARACTER MESSAGE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            _ColorChip(
                              key: const ValueKey('chat-color-ai-bubble'),
                              label: 'Bubble Fill',
                              color: aiBg,
                              onTap: () => showColorPicker(
                                context,
                                aiBg,
                                ui.setGlobalAiBubbleColor,
                              ),
                            ),
                            _PairedInkChip(
                              key: const ValueKey('chat-color-ai-text'),
                              label: 'Text Ink',
                              inkColor: aiFg,
                              bgColor: aiBg,
                              onTap: () => showColorPicker(
                                context,
                                aiFg,
                                ui.setGlobalAiTextColor,
                              ),
                            ),
                            _RoleTextChip(
                              key: const ValueKey('chat-color-dialogue'),
                              label: 'Dialogue',
                              sample: '"Quotes"',
                              color: dialogue,
                              onTap: () => showColorPicker(
                                context,
                                dialogue,
                                ui.setGlobalDialogueColor,
                              ),
                            ),
                            _RoleTextChip(
                              key: const ValueKey('chat-color-action'),
                              label: 'Actions',
                              sample: '*Actions*',
                              color: action,
                              isItalic: true,
                              onTap: () => showColorPicker(
                                context,
                                action,
                                ui.setGlobalActionColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final corners = AppCorners.of(context);
    return Tooltip(
      message: 'Change $label',
      child: Semantics(
        button: true,
        label: 'Change $label color',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: corners.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: corners.circular(8),
              border: Border.all(
                color: AppColors.borderOf(context),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppColors.borderOf(context),
                      width: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PairedInkChip extends StatelessWidget {
  const _PairedInkChip({
    super.key,
    required this.label,
    required this.inkColor,
    required this.bgColor,
    required this.onTap,
  });

  final String label;
  final Color inkColor;
  final Color bgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final corners = AppCorners.of(context);
    return Tooltip(
      message: 'Change $label',
      child: Semantics(
        button: true,
        label: 'Change $label color',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: corners.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: corners.circular(8),
              border: Border.all(
                color: AppColors.borderOf(context),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppColors.borderOf(context),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    'Aa',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: inkColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleTextChip extends StatelessWidget {
  const _RoleTextChip({
    super.key,
    required this.label,
    required this.sample,
    required this.color,
    required this.onTap,
    this.isItalic = false,
  });

  final String label;
  final String sample;
  final Color color;
  final VoidCallback onTap;
  final bool isItalic;

  @override
  Widget build(BuildContext context) {
    final corners = AppCorners.of(context);
    return Tooltip(
      message: 'Change $label color',
      child: Semantics(
        button: true,
        label: 'Change $label color',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: corners.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: corners.circular(8),
              border: Border.all(
                color: AppColors.borderOf(context),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sample,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                    color: color,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
