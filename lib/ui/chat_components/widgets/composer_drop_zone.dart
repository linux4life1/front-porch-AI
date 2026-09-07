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

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/chat_components/widgets/chat_image_attachment.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Drag a photo from the desktop onto the composer. Picker still works.
class ComposerDropZone extends StatefulWidget {
  const ComposerDropZone({
    super.key,
    required this.child,
    required this.onImage,
    this.enabled = true,
  });

  final Widget child;
  final Future<void> Function(Uint8List bytes) onImage;
  final bool enabled;

  @override
  State<ComposerDropZone> createState() => _ComposerDropZoneState();
}

class _ComposerDropZoneState extends State<ComposerDropZone> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) {
        if (widget.enabled) setState(() => _hover = true);
      },
      onDragExited: (_) => setState(() => _hover = false),
      onDragDone: (detail) async {
        setState(() => _hover = false);
        if (!widget.enabled) return;
        final png = await firstDroppedImage([
          for (final f in detail.files)
            (
              name: f.name.isEmpty ? f.path : f.name,
              read: () async {
                final mark = f.extraAppleBookmark;
                if (mark != null && mark.isNotEmpty) {
                  await DesktopDrop.instance
                      .startAccessingSecurityScopedResource(bookmark: mark);
                }
                try {
                  return await f.readAsBytes();
                } finally {
                  if (mark != null && mark.isNotEmpty) {
                    await DesktopDrop.instance
                        .stopAccessingSecurityScopedResource(bookmark: mark);
                  }
                }
              },
            ),
        ]);
        if (png != null) await widget.onImage(png);
      },
      child: Stack(
        children: [
          widget.child,
          if (_hover)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: amber.withValues(alpha: 0.18),
                    border: Border.all(color: amber, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'Drop a photo',
                      style: TextStyle(
                        color: AppColors.onChaosAccent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
