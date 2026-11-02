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
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';

/// A Studio workspace's tie to the Recent shelf: the shelf picture it shows
/// now, keeping each new result, starring, and a picture handed to the Edit
/// tab from the Create tab's shelf.
class StudioRecentLink {
  /// The shelf picture on show, or null for none.
  StudioRecentEntry? shown;

  /// A picture to load into the Edit tab as its source.
  final ValueNotifier<Uint8List?> editPicture = ValueNotifier(null);

  /// Keep a fresh result on the shelf and show it. [onChanged] runs once the
  /// entry is known. A failure is logged; the picture stays on screen.
  Future<void> remember(
    BuildContext context,
    Uint8List png,
    String prompt, {
    bool edit = false,
    required VoidCallback onChanged,
  }) async {
    shown = null;
    try {
      shown = await rememberStudioResult(
        context.read<StorageService>(),
        png,
        prompt: prompt,
        edit: edit,
      );
    } on FileSystemException catch (e) {
      debugPrint('Image Studio: could not keep the picture on Recent: $e');
    }
    onChanged();
  }

  /// Star or unstar the shown picture.
  Future<void> toggleKeep(BuildContext context, VoidCallback onChanged) async {
    final entry = shown;
    if (entry == null) return;
    try {
      shown = await StudioRecentStore.of(
        context.read<StorageService>(),
      ).setKept(entry.name, !entry.kept);
    } on FileSystemException catch (e) {
      debugPrint('Image Studio: could not star ${entry.name}: $e');
    }
    onChanged();
  }

  void dispose() => editPicture.dispose();
}
