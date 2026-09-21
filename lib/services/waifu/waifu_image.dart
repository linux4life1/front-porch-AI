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

import 'package:front_porch_ai/services/waifu/waifu_brand.dart';
import 'package:path/path.dart' as p;

const kWaifuInboxDir = '$kWaifuDotDir/inbox';
const kWaifuInboxPhotoMaxBytes = 6 * 1024 * 1024;

/// Save an attached PNG under the sit-down folder so the bubble can show it.
Future<String> waifuSaveInboxPhoto(String folderRoot, Uint8List png) async {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  final isPng =
      png.length >= signature.length &&
      List.generate(
        signature.length,
        (index) => png[index] == signature[index],
      ).every((matches) => matches);
  if (!isPng || png.length > kWaifuInboxPhotoMaxBytes) {
    throw const FormatException(
      'Waifu Coder inbox accepts only bounded, prepared PNG photos',
    );
  }
  final dir = Directory(p.join(folderRoot, kWaifuInboxDir));
  await dir.create(recursive: true);
  final path = p.join(
    dir.path,
    'photo_${DateTime.now().millisecondsSinceEpoch}.png',
  );
  await File(path).writeAsBytes(png);
  return path;
}
