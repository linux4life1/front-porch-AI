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

/// One OS-dropped item, already reduced to a path (or a reject reason).
class HomeDropSource {
  const HomeDropSource({
    required this.label,
    this.path = '',
    this.isDirectory = false,
  });

  /// Finder / Explorer name, used in the snackbar when we skip the item.
  final String label;

  /// Absolute path when the desktop drop plugin gave us one.
  final String path;

  /// Folders are never walked — folder import stays on the picker.
  final bool isDirectory;
}

/// Split a home-screen drop into the existing PNG and BYAF import lists.
class HomeDropPlan {
  const HomeDropPlan({
    this.pngPaths = const [],
    this.byafPaths = const [],
    this.rejectedNames = const [],
  });

  final List<String> pngPaths;
  final List<String> byafPaths;
  final List<String> rejectedNames;

  bool get hasImportable => pngPaths.isNotEmpty || byafPaths.isNotEmpty;

  /// PNG and BYAF in one drop — one bulk pass, not two stacked dialogs.
  bool get isMixed => pngPaths.isNotEmpty && byafPaths.isNotEmpty;

  String? get rejectMessage =>
      homeDropRejectMessage(rejectedNames, hasImportable: hasImportable);
}

/// Overlay copy while a drag hovers the character library.
const kHomeDropOverlayLabel = 'Drop PNG or BYAF cards';

/// Classify [paths] by extension. Windows and POSIX separators both work.
HomeDropPlan planHomeDrop(Iterable<String> paths) {
  return planHomeDropSources([
    for (final path in paths)
      HomeDropSource(label: homeDropFileName(path), path: path),
  ]);
}

HomeDropPlan planHomeDropSources(Iterable<HomeDropSource> sources) {
  final pngPaths = <String>[];
  final byafPaths = <String>[];
  final rejectedNames = <String>[];
  for (final source in sources) {
    if (source.isDirectory || source.path.isEmpty) {
      rejectedNames.add(_sourceLabel(source));
      continue;
    }
    final name = homeDropFileName(source.path).toLowerCase();
    if (name.endsWith('.png')) {
      pngPaths.add(source.path);
    } else if (name.endsWith('.byaf')) {
      byafPaths.add(source.path);
    } else {
      rejectedNames.add(_sourceLabel(source));
    }
  }
  return HomeDropPlan(
    pngPaths: pngPaths,
    byafPaths: byafPaths,
    rejectedNames: rejectedNames,
  );
}

String? homeDropRejectMessage(
  List<String> rejectedNames, {
  required bool hasImportable,
}) {
  if (rejectedNames.isEmpty) return null;
  if (!hasImportable) {
    if (rejectedNames.length == 1) {
      return 'Can\'t import "${rejectedNames.first}" — drop PNG character '
          'cards or .byaf files.';
    }
    return "Can't import those files — drop PNG character cards or .byaf files.";
  }
  if (rejectedNames.length == 1) {
    return 'Skipped ${rejectedNames.first} (not a PNG card or .byaf).';
  }
  return 'Skipped ${rejectedNames.length} unsupported files.';
}

String homeDropFileName(String path) {
  final slash = path.replaceAll('\\', '/');
  final i = slash.lastIndexOf('/');
  return i < 0 ? slash : slash.substring(i + 1);
}

String _sourceLabel(HomeDropSource source) {
  if (source.label.isNotEmpty) return source.label;
  return homeDropFileName(source.path);
}
