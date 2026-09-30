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

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Draw Things only fills Echo("models") when Model Browser is on. The app
/// still keeps the weights in its Models folder, and generation names a LoRA
/// by that file name. This reads the folder the macOS app uses, or
/// `DRAWTHINGS_MODELS_DIR` when a CLI server was pointed somewhere else.
Directory? drawThingsDefaultModelsDirectory() {
  final override = Platform.environment['DRAWTHINGS_MODELS_DIR'];
  if (override != null && override.trim().isNotEmpty) {
    return Directory(override.trim());
  }
  if (!Platform.isMacOS) return null;
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return null;
  return Directory(
    p.join(
      home,
      'Library',
      'Containers',
      'com.liuliu.draw-things',
      'Data',
      'Documents',
      'Models',
    ),
  );
}

/// Echo may return `lora/name.ckpt`. Generate wants the file name.
String drawThingsLoraBasename(String listed) {
  final normalized = listed.replaceAll('\\', '/');
  final cut = normalized.lastIndexOf('/');
  return (cut < 0 ? normalized : normalized.substring(cut + 1)).trim();
}

bool drawThingsHostIsLocal(String host) {
  switch (host.trim().toLowerCase()) {
    case '127.0.0.1':
    case 'localhost':
    case '::1':
    case '[::1]':
      return true;
    default:
      return false;
  }
}

/// One LoRA weight Draw Things can load, plus the base-model id from
/// `custom_lora.json` when that catalog names the file.
class DrawThingsLoraEntry {
  final String file;
  final String version;

  const DrawThingsLoraEntry(this.file, [this.version = '']);
}

/// LoRA weights Draw Things can load from [modelsDir].
///
/// A weight whose name contains "lora" is included. `custom_lora.json` can
/// also name a weight that does not have "lora" in the file name; that file
/// is included only when it is actually in the folder. [DrawThingsLoraEntry.version]
/// is the catalog's base-model id (`flux2_9b`, `qwen_image`, …).
Future<List<DrawThingsLoraEntry>> drawThingsLoraFilesIn(
  Directory modelsDir,
) async {
  if (!await modelsDir.exists()) return const [];
  final present = <String>{};
  final named = <String>{};
  await for (final entity in modelsDir.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final base = p.basename(entity.path);
    if (!_isWeight(base)) continue;
    present.add(base);
    if (base.toLowerCase().contains('lora')) named.add(base);
  }
  final versions = <String, String>{};
  final catalog = File(p.join(modelsDir.path, 'custom_lora.json'));
  if (await catalog.exists()) {
    try {
      final decoded = jsonDecode(await catalog.readAsString());
      if (decoded is List) {
        for (final row in decoded) {
          if (row is! Map) continue;
          final file = p.basename(row['file']?.toString() ?? '');
          if (file.isEmpty || !present.contains(file)) continue;
          named.add(file);
          final version = row['version']?.toString().trim() ?? '';
          if (version.isNotEmpty) versions[file] = version;
        }
      }
    } catch (_) {
      // A broken catalog must not hide the files that are on disk.
    }
  }
  final files = named.toList()..sort();
  return [
    for (final file in files) DrawThingsLoraEntry(file, versions[file] ?? ''),
  ];
}

bool _isWeight(String base) {
  final lower = base.toLowerCase();
  return lower.endsWith('.ckpt') ||
      lower.endsWith('.safetensors') ||
      lower.endsWith('.pt') ||
      lower.endsWith('.bin');
}
