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

import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:path/path.dart' as p;

class WaifuLangDoor {
  const WaifuLangDoor({
    required this.id,
    required this.name,
    this.extensions = const [],
    this.markers = const [],
    this.pathCommand,
    this.args = const [],
    this.url,
    this.sha256,
  });

  final String id;
  final String name;
  final List<String> extensions;
  final List<String> markers;
  final String? pathCommand;
  final List<String> args;
  final String? url;
  final String? sha256;
}

/// Metadata only. Sitting down never fetches these artifacts.
const kWaifuLangCatalog = <WaifuLangDoor>[
  WaifuLangDoor(
    id: 'dart',
    name: 'Dart',
    extensions: ['.dart'],
    markers: ['pubspec.yaml'],
    pathCommand: 'dart',
    args: ['language-server'],
  ),
  WaifuLangDoor(
    id: 'gdscript',
    name: 'GDScript',
    extensions: ['.gd'],
    markers: ['project.godot'],
    pathCommand: 'godot',
  ),
  WaifuLangDoor(
    id: 'python',
    name: 'Python',
    extensions: ['.py'],
    markers: ['pyproject.toml', 'requirements.txt'],
    pathCommand: 'pylsp',
  ),
  WaifuLangDoor(
    id: 'rust',
    name: 'Rust',
    extensions: ['.rs'],
    markers: ['Cargo.toml'],
    pathCommand: 'rust-analyzer',
  ),
  WaifuLangDoor(
    id: 'go',
    name: 'Go',
    extensions: ['.go'],
    markers: ['go.mod'],
    pathCommand: 'gopls',
  ),
  WaifuLangDoor(
    id: 'typescript',
    name: 'TypeScript',
    extensions: ['.ts', '.tsx', '.js'],
    markers: ['package.json', 'tsconfig.json'],
    pathCommand: 'typescript-language-server',
    args: ['--stdio'],
  ),
  WaifuLangDoor(
    id: 'c',
    name: 'C/C++',
    extensions: ['.c', '.h', '.cc', '.cpp'],
    pathCommand: 'clangd',
  ),
  WaifuLangDoor(
    id: 'java',
    name: 'Java',
    extensions: ['.java'],
    markers: ['pom.xml', 'build.gradle'],
    pathCommand: 'jdtls',
  ),
  WaifuLangDoor(
    id: 'kotlin',
    name: 'Kotlin',
    extensions: ['.kt'],
    pathCommand: 'kotlin-language-server',
  ),
  WaifuLangDoor(
    id: 'swift',
    name: 'Swift',
    extensions: ['.swift'],
    markers: ['Package.swift'],
    pathCommand: 'sourcekit-lsp',
  ),
  WaifuLangDoor(
    id: 'ruby',
    name: 'Ruby',
    extensions: ['.rb'],
    markers: ['Gemfile'],
    pathCommand: 'solargraph',
  ),
  WaifuLangDoor(
    id: 'php',
    name: 'PHP',
    extensions: ['.php'],
    pathCommand: 'intelephense',
  ),
  WaifuLangDoor(
    id: 'lua',
    name: 'Lua',
    extensions: ['.lua'],
    pathCommand: 'lua-language-server',
  ),
  WaifuLangDoor(
    id: 'bash',
    name: 'Bash',
    extensions: ['.sh'],
    pathCommand: 'bash-language-server',
  ),
  WaifuLangDoor(
    id: 'zig',
    name: 'Zig',
    extensions: ['.zig'],
    pathCommand: 'zls',
  ),
  WaifuLangDoor(
    id: 'nim',
    name: 'Nim',
    extensions: ['.nim'],
    pathCommand: 'nimlsp',
  ),
  WaifuLangDoor(
    id: 'haskell',
    name: 'Haskell',
    extensions: ['.hs'],
    pathCommand: 'haskell-language-server',
  ),
  WaifuLangDoor(
    id: 'elixir',
    name: 'Elixir',
    extensions: ['.ex', '.exs'],
    markers: ['mix.exs'],
    pathCommand: 'elixir-ls',
  ),
  WaifuLangDoor(
    id: 'html',
    name: 'HTML/CSS',
    extensions: ['.html', '.css'],
    pathCommand: 'vscode-html-language-server',
  ),
  WaifuLangDoor(
    id: 'json',
    name: 'JSON',
    extensions: ['.json'],
    pathCommand: 'vscode-json-language-server',
  ),
  WaifuLangDoor(
    id: 'yaml',
    name: 'YAML',
    extensions: ['.yaml', '.yml'],
    pathCommand: 'yaml-language-server',
  ),
  WaifuLangDoor(
    id: 'markdown',
    name: 'Markdown',
    extensions: ['.md'],
    pathCommand: 'marksman',
  ),
  WaifuLangDoor(
    id: 'sql',
    name: 'SQL',
    extensions: ['.sql'],
    pathCommand: 'sqls',
  ),
  WaifuLangDoor(
    id: 'terraform',
    name: 'Terraform',
    extensions: ['.tf'],
    pathCommand: 'terraform-ls',
  ),
  WaifuLangDoor(
    id: 'nix',
    name: 'Nix',
    extensions: ['.nix'],
    pathCommand: 'nil',
  ),
  WaifuLangDoor(id: 'holy_c', name: 'Holy C', extensions: ['.HC', '.hc']),
];

Future<Set<String>> waifuDetectLangs(
  String folder, {
  List<WaifuLangDoor>? catalog,
}) async {
  final doors = catalog ?? kWaifuLangCatalog;
  final dir = Directory(folder);
  if (!await dir.exists()) return {};
  final names = <String>{};
  final exts = <String>{};
  await for (final entity in dir.list(followLinks: false)) {
    final base = p.basename(entity.path);
    names.add(base);
    final ext = p.extension(base);
    if (ext.isNotEmpty) exts.add(ext.toLowerCase());
  }
  final hits = <String>{};
  for (final door in doors) {
    if (door.markers.any(names.contains)) {
      hits.add(door.id);
      continue;
    }
    if (door.extensions.any((e) => exts.contains(e.toLowerCase()))) {
      hits.add(door.id);
    }
  }
  return hits;
}

/// Suggestions only. Never enables a door — including in Yolo.
Future<void> waifuPrepareLangs(WaifuSession session) async {
  final found = await waifuDetectLangs(session.folderRoot);
  session.suggestedLangs
    ..clear()
    ..addAll(found);
}
