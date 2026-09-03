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
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// A locally generated image inside a chat bubble (from `/image` or the Image
/// Studio's "Send to chat"). Left-click opens a zoomable full-size viewer;
/// right-click opens a context menu with Save image as… / Show in folder /
/// Copy prompt (the same showMenu-at-cursor pattern as the home grid cards).
class InlineChatImage extends StatefulWidget {
  final String path;
  final String? prompt;

  const InlineChatImage({super.key, required this.path, this.prompt});

  @override
  State<InlineChatImage> createState() => _InlineChatImageState();
}

class _InlineChatImageState extends State<InlineChatImage> {
  // Statted ONCE per element lifetime, not per build: this widget lives
  // inside message bubbles, which rebuild on every streaming token batch —
  // a per-build existsSync here is the exact bug class of the 20260716
  // sluggishness regression (see the io-lint CI gate).
  late bool _exists;

  @override
  void initState() {
    super.initState();
    _exists = File(widget.path).existsSync(); // io-ok: once per element, not per build
  }

  @override
  void didUpdateWidget(covariant InlineChatImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _exists = File(widget.path).existsSync(); // io-ok: only on path change
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    final file = File(path);
    if (!_exists) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 16,
              color: AppColors.textTertiary(context),
            ),
            const SizedBox(width: 6),
            Text(
              'Image file missing',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: () => _showFullSize(context, file),
        onSecondaryTapUp: (details) => _showContextMenu(context, details),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320, maxWidth: 420),
            child: Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => Icon(
                Icons.broken_image_outlined,
                color: AppColors.textTertiary(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showFullSize(BuildContext context, File file) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          onSecondaryTapUp: (details) => _showContextMenu(context, details),
          child: InteractiveViewer(
            maxScale: 6,
            child: Image.file(file, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(
    BuildContext context,
    TapUpDetails details,
  ) async {
    final position = details.globalPosition;
    final hasPrompt = (widget.prompt ?? '').trim().isNotEmpty;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: AppColors.surfaceContainerOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        _item(context, 'save', Icons.save_alt, 'Save image as…'),
        _item(context, 'folder', Icons.folder_open, 'Show in folder'),
        if (hasPrompt) _item(context, 'widget.prompt', Icons.copy, 'Copy widget.prompt'),
      ],
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'save':
        await _saveAs(context);
      case 'folder':
        await _revealInFolder();
      case 'widget.prompt':
        await Clipboard.setData(ClipboardData(text: widget.prompt!.trim()));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Prompt copied to clipboard')),
          );
        }
    }
  }

  PopupMenuItem<String> _item(
    BuildContext context,
    String value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem(
      value: value,
      child: ListTile(
        leading: Icon(icon, color: AppColors.iconSecondary(context), size: 20),
        title: Text(
          label,
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Future<void> _saveAs(BuildContext context) async {
    final bytes = await File(widget.path).readAsBytes();
    final target = await PickerPrefs.saveFile(
      category: PickerPrefs.catExport,
      bytes: bytes,
      dialogTitle: 'Save image',
      fileName: p.basename(widget.path),
      type: FileType.image,
    );
    if (target == null) return;
    final out = target;
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to ${p.basename(out)}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Couldn’t save image: $e')));
      }
    }
  }

  /// Reveal the image in the platform file manager (Windows/macOS select the
  /// file; Linux file managers have no portable "select", so open the folder).
  Future<void> _revealInFolder() async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', widget.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', widget.path]);
      } else {
        await Process.run('xdg-open', [p.dirname(widget.path)]);
      }
    } catch (e) {
      debugPrint('InlineChatImage: reveal in folder failed: $e');
    }
  }
}
