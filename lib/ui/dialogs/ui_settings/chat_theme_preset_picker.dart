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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Horizontal Chat Theme preset picker: "None" plus every
/// [ChatThemePreset], with chevrons that page the strip. Owns its scroll
/// position; a tap reports the fresh overrides through [onSelected].
class ChatThemePresetPicker extends StatefulWidget {
  final ChatThemeOverrides overrides;
  final ValueChanged<ChatThemeOverrides> onSelected;

  const ChatThemePresetPicker({
    super.key,
    required this.overrides,
    required this.onSelected,
  });

  @override
  State<ChatThemePresetPicker> createState() => _ChatThemePresetPickerState();
}

class _ChatThemePresetPickerState extends State<ChatThemePresetPicker> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overrides = widget.overrides;

    return Row(
      children: [
        IconButton(
          icon: Icon(
            Icons.chevron_left,
            color: AppColors.textTertiary(context),
          ),
          constraints: const BoxConstraints(minWidth: 28, minHeight: 72),
          padding: EdgeInsets.zero,
          onPressed: () {
            final offset = _scrollController.offset;
            _scrollController.animateTo(
              (offset - 144).clamp(
                0,
                _scrollController.position.maxScrollExtent,
              ),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
          },
        ),
        Expanded(
          child: SizedBox(
            height: 72,
            child: ListView.separated(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              itemCount: ChatThemePreset.presets.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isSelected = !overrides.hasTheme;
                  return GestureDetector(
                    onTap: () {
                      widget.onSelected(ChatThemeOverrides());
                    },
                    child: Container(
                      width: 64,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.porchAmberOf(
                                context,
                              ).withValues(alpha: 0.15)
                            : AppColors.surfaceContainerOf(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.formAccentOf(context)
                              : AppColors.borderOf(context),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'None',
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                }
                final preset = ChatThemePreset.presets[index - 1];
                final isSelected = overrides.themeId == preset.id;
                return GestureDetector(
                  onTap: () {
                    widget.onSelected(ChatThemeOverrides(themeId: preset.id));
                  },
                  child: Container(
                    width: 64,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerOf(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.formAccentOf(context)
                            : AppColors.borderOf(context),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: preset.defaultUserBubbleColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: preset.defaultAiBubbleColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          preset.displayName,
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          preset.defaultBorderStyle,
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.chevron_right,
            color: AppColors.textTertiary(context),
          ),
          constraints: const BoxConstraints(minWidth: 28, minHeight: 72),
          padding: EdgeInsets.zero,
          onPressed: () {
            final offset = _scrollController.offset;
            _scrollController.animateTo(
              (offset + 144).clamp(
                0,
                _scrollController.position.maxScrollExtent,
              ),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
          },
        ),
      ],
    );
  }
}
