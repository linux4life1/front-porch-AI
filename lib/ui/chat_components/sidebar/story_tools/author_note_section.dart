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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import '../sidebar_tokens.dart';

/// Author note section (group + 1:1 support) — lives inside the Story Tools
/// accordion.
class AuthorNoteSection extends StatefulWidget {
  final ChatService chatService;
  const AuthorNoteSection({super.key, required this.chatService});

  @override
  State<AuthorNoteSection> createState() => _AuthorNoteSectionState();
}

class _AuthorNoteSectionState extends State<AuthorNoteSection> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.chatService.authorNote);
  }

  @override
  void didUpdateWidget(covariant AuthorNoteSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.chatService.authorNote) {
      _controller.text = widget.chatService.authorNote;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = widget.chatService.activeGroup != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: isGroup
              ? 'Group Author\'s Note — injected for every character in the group.\n'
                    'For per-character author\'s notes, go to Group Settings → Prompt Engineering.'
              : 'Author\'s Note — injected into the character\'s context.',
          child: SidebarSubHeader(
            icon: Icons.sticky_note_2_outlined,
            label: isGroup ? "Group Author's Note" : "Author's Note",
            accent: AppColors.porchHoneyOf(context),
          ),
        ),
        const SizedBox(height: 8),
        AppTextField(
          controller: _controller,
          maxLines: 4,
          minLines: 2,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Instructions injected into context...',
            hintStyle: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.borderOf(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.borderOf(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.bondMidOf(context)),
            ),
            contentPadding: const EdgeInsets.all(10),
          ),
          onChanged: (val) {
            widget.chatService.setAuthorNote(
              val,
              strength: widget.chatService.authorNoteStrength,
            );
          },
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final strength = widget.chatService.authorNoteStrength;
            Color sliderColor;
            String tierLabel;
            if (strength <= 3) {
              sliderColor = AppColors.bondMidOf(context);
              tierLabel = 'Subtle';
            } else if (strength <= 7) {
              sliderColor = AppColors.porchAmberOf(context);
              tierLabel = 'Moderate';
            } else {
              sliderColor = AppColors.negativeAccentOf(context);
              tierLabel = 'Strong';
            }
            return Column(
              children: [
                Row(
                  children: [
                    Tooltip(
                      message:
                          'Controls how forcefully the author\'s note is applied.\n'
                          'Subtle: a gentle suggestion the AI may follow.\n'
                          'Moderate: standard injection into context.\n'
                          'Strong: an urgent directive the AI should apply immediately.',
                      child: Text(
                        'Strength: ',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                          activeTrackColor: sliderColor,
                          inactiveTrackColor: AppColors.borderOf(
                            context,
                          ).withValues(alpha: 0.3),
                          thumbColor: sliderColor,
                        ),
                        child: Slider(
                          value: strength.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: '$strength — $tierLabel',
                          onChanged: (val) {
                            widget.chatService.setAuthorNote(
                              widget.chatService.authorNote,
                              strength: val.round(),
                            );
                          },
                        ),
                      ),
                    ),
                    Text(
                      '$strength',
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: sliderColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: sliderColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          tierLabel,
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
