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

const kDeskProjectMarkers = [
  'pubspec.yaml',
  '.git',
  'package.json',
  'Cargo.toml',
  'project.godot',
];

class DeskDirEntry {
  const DeskDirEntry({required this.name, required this.path});

  final String name;
  final String path;

  /// Unix hidden folder. `.git` is a project *marker*, not a pick target.
  bool get isHidden => name.startsWith('.');
}

class DeskFolderListing {
  const DeskFolderListing({
    required this.path,
    required this.parentPath,
    required this.directories,
    required this.projectHints,
  });

  final String path;
  final String? parentPath;
  final List<DeskDirEntry> directories;
  final List<String> projectHints;

  /// Home directories sort `.cache` before `Documents`. Default picker
  /// hides those so the first screen is real folders, not dotfiles.
  List<DeskDirEntry> visible({bool includeHidden = false}) => [
    for (final d in directories)
      if (includeHidden || !d.isHidden) d,
  ];
}

/// HOME on Unix, USERPROFILE on Windows, else the system temp directory.
String deskDefaultStartPath() {
  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) return home;
  final profile = Platform.environment['USERPROFILE'];
  if (profile != null && profile.isNotEmpty) return profile;
  return Directory.systemTemp.path;
}

Future<DeskFolderListing> listDeskDirectory(String path) async {
  final parent = p.dirname(path);
  final parentPath = parent == path ? null : parent;
  final dir = Directory(path);
  if (!await dir.exists()) {
    return DeskFolderListing(
      path: path,
      parentPath: parentPath,
      directories: const [],
      projectHints: const [],
    );
  }

  final directories = <DeskDirEntry>[];
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! Directory) continue;
    directories.add(
      DeskDirEntry(name: p.basename(entity.path), path: entity.path),
    );
  }
  directories.sort(
    (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );

  final hints = <String>[];
  for (final marker in kDeskProjectMarkers) {
    final candidate = p.join(path, marker);
    if (await FileSystemEntity.type(candidate) ==
        FileSystemEntityType.notFound) {
      continue;
    }
    hints.add(marker);
  }

  return DeskFolderListing(
    path: path,
    parentPath: parentPath,
    directories: directories,
    projectHints: hints,
  );
}
