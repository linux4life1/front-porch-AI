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

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/fpchat_image_names.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Adds the image a message shows (its `image_path`) to an export's
/// [images], keyed by file name. A missing or unreadable file is skipped.
Future<void> collectFpchatMessageImage(
  ChatMessage m,
  Map<String, List<int>> images,
) async {
  final md = m.activeMetadata;
  if (md == null) return;
  final imagePath = md['image_path'] as String?;
  if (imagePath == null || imagePath.isEmpty) return;
  try {
    final f = File(imagePath);
    if (await f.exists()) {
      final name = path.basename(imagePath);
      images[name] = await f.readAsBytes();
    }
  } catch (e) {
    debugPrint('[fpchat] skip image $imagePath: $e');
  }
}

/// Writes a package's [images] to disk under session [sid] and points each
/// message's `image_path` at its new file. The image service saves first;
/// without one (or when it declines) the file lands in the chats folder's
/// `images/`, never over an existing file.
Future<void> materializeFpchatImages(
  List<ChatMessage> msgs,
  Map<String, List<int>> images, {
  required String sid,
  required ImageGenService? imageGen,
  required StorageService storage,
}) async {
  if (images.isEmpty) return;
  final igs = imageGen;
  var seq = 0;
  for (final m in msgs) {
    final md = m.activeMetadata;
    if (md == null) continue;
    final old = md['image_path'] as String?;
    if (old == null) continue;
    final base = path.basename(old);
    final raw = images[base];
    if (raw == null) continue;
    final bytes = Uint8List.fromList(raw);
    seq++;
    // Strip prior fpchat_ prefixes; cap stem + keep extension (Windows MAX_PATH).
    final cleanBase = stripFpchatImagePrefixes(base);
    final preferred = cappedFpchatImageName(sid, seq, cleanBase);
    String? dest;
    if (igs != null) {
      dest = await igs.saveImageToDisk(bytes, preferred);
    }
    if (dest == null) {
      final dir = Directory(path.join(storage.chatsDir.path, 'images'));
      await dir.create(recursive: true);
      dest = path.join(dir.path, preferred);
      var n = 1;
      while (await File(dest!).exists()) {
        dest = path.join(
          dir.path,
          cappedFpchatImageName(sid, seq, cleanBase, collision: n),
        );
        n++;
      }
      await File(dest).writeAsBytes(bytes, flush: true);
    }
    md['image_path'] = dest;
    m.activeMetadata = md;
  }
}
