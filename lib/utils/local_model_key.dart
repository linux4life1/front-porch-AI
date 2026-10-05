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

import 'package:path/path.dart' as p;

/// What a local model file is remembered by: its file name and its size in
/// bytes, never the folder it sits in.
///
/// A path names a place, not a model. The same file moved to another folder
/// or drive is the same model and keeps what is known about it; another file
/// put at the same path (a new quant, a re-tuned or re-templated upload) is
/// not, and almost always differs in size. A renamed file is a new name and is
/// looked at again once, which costs one small question. The file's folder,
/// the preset, the context size and the engine's settings are not properties
/// of the model and are left out.
///
/// [sizeOf] is a seam for tests; by default the size is read from the file,
/// at most once every two seconds per path, because the sidebar's pill asks
/// while it paints. A file that cannot be read is still named, by its name.
String localModelKey(String? modelPath, {int? Function(String path)? sizeOf}) {
  final path = modelPath?.trim() ?? '';
  if (path.isEmpty) return '';
  return '${p.basename(path)}#${(sizeOf ?? _fileSize)(path) ?? '?'}';
}

final Map<String, ({int? size, DateTime at})> _sizes = {};

int? _fileSize(String path) {
  final now = DateTime.now();
  final seen = _sizes[path];
  if (seen != null && now.difference(seen.at) < const Duration(seconds: 2)) {
    return seen.size;
  }
  int? size;
  try {
    size = File(path).lengthSync();
  } on FileSystemException {
    size = null;
  }
  if (_sizes.length > 32) _sizes.clear();
  _sizes[path] = (size: size, at: now);
  return size;
}
