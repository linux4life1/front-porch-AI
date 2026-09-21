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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'home_drop_import.dart';

export 'home_drop_import.dart';

/// Desktop file drop onto the character library. Picker import still works.
class HomeDropZone extends StatefulWidget {
  const HomeDropZone({
    super.key,
    required this.child,
    required this.onDrop,
    this.enabled = true,
  });

  final Widget child;
  final Future<void> Function(List<HomeDropSource> sources) onDrop;
  final bool enabled;

  @override
  State<HomeDropZone> createState() => HomeDropZoneState();
}

class HomeDropZoneState extends State<HomeDropZone> {
  var _hover = false;
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) {
        if (widget.enabled) setState(() => _hover = true);
      },
      onDragExited: (_) => setState(() => _hover = false),
      onDragDone: (detail) async {
        setState(() => _hover = false);
        if (!widget.enabled) return;
        await _importDroppedItems(detail.files);
      },
      child: Stack(
        children: [
          widget.child,
          if (_hover) const Positioned.fill(child: HomeDropHighlight()),
        ],
      ),
    );
  }

  /// Widget tests fire this instead of a real OS drop.
  @visibleForTesting
  Future<void> debugDrop(List<HomeDropSource> sources) => _handle(sources);

  Future<void> _importDroppedItems(List<DropItem> files) async {
    final marks = <Uint8List>[];
    try {
      for (final file in files) {
        final mark = file.extraAppleBookmark;
        if (mark != null && mark.isNotEmpty) {
          try {
            await DesktopDrop.instance.startAccessingSecurityScopedResource(
              bookmark: mark,
            );
            marks.add(mark);
          } catch (e) {
            debugPrint('[HomeDrop] bookmark access failed: $e');
          }
        }
      }
      await _handle([
        for (final file in files)
          HomeDropSource(
            label: file.name.isEmpty ? homeDropFileName(file.path) : file.name,
            path: file.path,
            isDirectory: file is DropItemDirectory,
          ),
      ]);
    } finally {
      for (final mark in marks) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: mark,
        );
      }
    }
  }

  Future<void> _handle(List<HomeDropSource> sources) async {
    if (_busy || !widget.enabled) return;
    _busy = true;
    try {
      await widget.onDrop(sources);
    } finally {
      _busy = false;
    }
  }
}

/// Amber wash shown while a desktop drag hovers the home library.
class HomeDropHighlight extends StatelessWidget {
  const HomeDropHighlight({super.key});

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: amber.withValues(alpha: 0.18),
            border: Border.all(color: amber, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              kHomeDropOverlayLabel,
              style: const TextStyle(
                color: AppColors.onChaosAccent,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
