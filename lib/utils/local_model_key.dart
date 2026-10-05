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
/// [sizeOf] is a seam for tests. A file that cannot be read is still named, by
/// its name. Ask through [LocalModelKeys] anywhere that runs often.
String localModelKey(String? modelPath, {int? Function(String path)? sizeOf}) {
  final path = modelPath?.trim() ?? '';
  if (path.isEmpty) return '';
  return '${p.basename(path)}#${(sizeOf ?? _fileSize)(path) ?? '?'}';
}

int? _fileSize(String path) {
  try {
    return File(path).lengthSync();
  } on FileSystemException {
    return null;
  }
}

/// What an identity says in the place of a model's key while the engine runs
/// a model nobody has confirmed (it is loading, or went back to another after
/// a reload that did not take): it names no model, so nothing is kept under it
/// and nobody is asked on its own. [episode] tells one such stretch from the
/// next, so a verdict given in one is not read in another.
String unknownLocalModelKey(Object episode) => '$_unknown#$episode';

/// Whether [identity] carries [unknownLocalModelKey].
bool namesUnknownLocalModel(String identity) =>
    identity.contains('|$_unknown#');

const String _unknown = '(unknown)';

/// [localModelKey] read from the file once per model and per load of the
/// engine, not on a timer and not on every paint: the sidebar's pill asks for
/// it while it builds, and a multi-GB file is not stat-ed per frame (cheap on
/// APFS, a Defender round-trip on Windows).
///
/// [stamp] says when the file may have changed under what is asked about: the
/// engine's resident generation, which goes up when a start comes up or a swap
/// is read back as running what it was asked for, not when a reload is only
/// asked for (it can still fail). A file replaced on disk while another one
/// runs is not the running model, so nothing changes until the engine loads
/// what is at the path.
class LocalModelKeys {
  String? _path;
  Object? _stamp;
  String _key = '';

  String of(
    String? modelPath, {
    required Object stamp,
    int? Function(String path)? sizeOf,
  }) {
    final path = modelPath?.trim() ?? '';
    if (_path == path && _stamp == stamp) return _key;
    _path = path;
    _stamp = stamp;
    return _key = localModelKey(path, sizeOf: sizeOf);
  }
}
