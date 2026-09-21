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

import 'package:front_porch_ai/ui/chat_components/sidebar/sidebar_tokens.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Drag handle + optional right pane. Extracted from ChatPage so Waifu Coder
/// can sit the coworker portrait on the same chrome. Width 0 is closed;
/// dragging below [SidebarTokens.minWidth] snaps closed.
class ChatResizeSidebar extends StatelessWidget {
  const ChatResizeSidebar({
    super.key,
    required this.width,
    required this.onWidth,
    required this.child,
  });

  final double width;
  final ValueChanged<double> onWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              final next = width - details.delta.dx;
              if (next < SidebarTokens.minWidth) {
                onWidth(0);
              } else {
                onWidth(
                  next.clamp(SidebarTokens.minWidth, SidebarTokens.maxWidth),
                );
              }
            },
            child: Container(
              width: 6,
              color: Colors.transparent,
              child: Center(
                child: Container(
                  width: 3,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.resolve(
                      context,
                      Colors.white24,
                      Colors.black12,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (width > 0) SizedBox(width: width, child: child),
      ],
    );
  }
}
