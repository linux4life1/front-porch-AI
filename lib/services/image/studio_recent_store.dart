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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// One picture on Image Studio's Recent shelf.
@immutable
class StudioRecentEntry {
  const StudioRecentEntry({
    required this.name,
    required this.path,
    required this.createdAt,
    this.prompt = '',
    this.style = '',
    this.mode = 'create',
    this.model = '',
    this.kept = false,
    this.bytes = 0,
  });

  /// File basename (`rec_<ms>.png`); the id the phone and desktop share.
  final String name;
  final String path;
  final DateTime createdAt;
  final String prompt;
  final String style;

  /// `create` or `edit`: which Studio tab made it.
  final String mode;
  final String model;

  /// Starred: never trimmed, whatever the limit.
  final bool kept;
  final int bytes;

  StudioRecentEntry copyWith({bool? kept}) => StudioRecentEntry(
    name: name,
    path: path,
    createdAt: createdAt,
    prompt: prompt,
    style: style,
    mode: mode,
    model: model,
    kept: kept ?? this.kept,
    bytes: bytes,
  );

  Map<String, Object> toJson() => {
    'name': name,
    'prompt': prompt,
    'style': style,
    'mode': mode,
    'model': model,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'kept': kept,
    'bytes': bytes,
  };
}

/// Every Image Studio Create and Edit result, kept on disk so closing the
/// Studio, leaving the phone page or restarting the app loses nothing.
///
/// The desktop Studio and the phone's Studio share one store per
/// [StorageService] ([of]), so a picture made on one shows on the other and
/// both follow the same limit. Only `rec_*` files in the folder are touched,
/// which keeps a folder the user picked safe from the trim.
class StudioRecentStore extends ChangeNotifier {
  StudioRecentStore({
    required Directory? Function() folder,
    required int Function() limit,
    DateTime Function()? clock,
  }) : _folder = folder,
       _limit = limit,
       _clock = clock ?? DateTime.now;

  final Directory? Function() _folder;
  final int Function() _limit;
  final DateTime Function() _clock;
  Future<void> _tail = Future.value();

  static final Expando<StudioRecentStore> _stores = Expando('studio_recent');

  /// The one store for [storage]'s library.
  static StudioRecentStore of(StorageService storage) =>
      _stores[storage] ??= StudioRecentStore(
        folder: () => folderFor(storage.rootPath, storage.imageGenSettings),
        limit: () => storage.imageGenSettings.studioRecentLimit,
      );

  /// The user's chosen folder, else `KoboldManager/studio-recent` under the
  /// storage root. Null when there is no storage root yet.
  static Directory? folderFor(String? root, ImageGenSettings settings) {
    final chosen = settings.studioRecentFolder;
    if (chosen.isNotEmpty) return Directory(chosen);
    if (root == null || root.isEmpty) return null;
    return Directory(p.join(root, 'KoboldManager', 'studio-recent'));
  }

  static final RegExp _namePattern = RegExp(r'^rec_\d+\.png$');

  /// Whether [name] is a Recent picture's id (never a path).
  static bool isRecentName(String name) => _namePattern.hasMatch(name);

  /// The folder pictures go to now, for display.
  String? get folderPath => _folder()?.path;

  /// Runs [job] after every earlier job, so the desktop and the phone never
  /// trim and write the same folder at once.
  Future<T> _serial<T>(Future<T> Function() job) {
    final run = _tail.then((_) => job());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// Keep [png] as the newest picture. Returns null when there is no folder.
  Future<StudioRecentEntry?> add(
    Uint8List png, {
    required String prompt,
    required String mode,
    String style = '',
    String model = '',
  }) => _serial(() async {
    final dir = _folder();
    if (dir == null) return null;
    await dir.create(recursive: true);
    var ms = _clock().millisecondsSinceEpoch;
    while (await File(_png(dir, ms)).exists()) {
      ms++;
    }
    final entry = StudioRecentEntry(
      name: 'rec_$ms.png',
      path: _png(dir, ms),
      createdAt: DateTime.fromMillisecondsSinceEpoch(ms),
      prompt: prompt,
      style: style,
      mode: mode,
      model: model,
      bytes: png.length,
    );
    await File(entry.path).writeAsBytes(png, flush: true);
    await _writeSidecar(entry);
    await _trim(dir);
    notifyListeners();
    return entry;
  });

  /// Newest first, starred and unstarred together.
  Future<List<StudioRecentEntry>> list() => _serial(() async {
    final dir = _folder();
    return dir == null ? const <StudioRecentEntry>[] : _read(dir);
  });

  /// The picture file for [name], or null when [name] is not a Recent id or
  /// the picture is gone.
  File? fileFor(String name) {
    if (!isRecentName(name)) return null;
    final dir = _folder();
    if (dir == null) return null;
    final file = File(p.join(dir.path, name));
    return file.existsSync() ? file : null;
  }

  /// Star or unstar [name]. Unstarring may trim it at once when the shelf is
  /// over its limit. Returns the updated entry, or null when it is gone.
  Future<StudioRecentEntry?> setKept(String name, bool kept) =>
      _serial(() async {
        final dir = _folder();
        if (dir == null || !isRecentName(name)) return null;
        final found = (await _read(dir)).where((e) => e.name == name);
        if (found.isEmpty) return null;
        final updated = found.first.copyWith(kept: kept);
        await _writeSidecar(updated);
        if (!kept) await _trim(dir);
        notifyListeners();
        return await File(updated.path).exists() ? updated : null;
      });

  Future<bool> delete(String name) => _serial(() async {
    final dir = _folder();
    if (dir == null || !isRecentName(name)) return false;
    final file = File(p.join(dir.path, name));
    if (!await file.exists()) return false;
    await _remove(file.path);
    notifyListeners();
    return true;
  });

  /// Delete every unstarred picture. Returns how many went.
  Future<int> clearUnkept() => _serial(() async {
    final dir = _folder();
    if (dir == null) return 0;
    var gone = 0;
    for (final e in await _read(dir)) {
      if (e.kept) continue;
      await _remove(e.path);
      gone++;
    }
    if (gone > 0) notifyListeners();
    return gone;
  });

  /// Apply a new limit straight away (the shelf calls this after a change).
  Future<void> applyLimit() => _serial(() async {
    final dir = _folder();
    if (dir != null) await _trim(dir);
    notifyListeners();
  });

  /// Tell listeners the folder changed (a new folder holds other pictures).
  void folderChanged() => notifyListeners();

  static String _png(Directory dir, int ms) => p.join(dir.path, 'rec_$ms.png');

  static String _sidecar(String pngPath) =>
      '${p.withoutExtension(pngPath)}.json';

  Future<void> _writeSidecar(StudioRecentEntry e) async {
    final meta = Map<String, Object>.of(e.toJson())
      ..remove('name')
      ..remove('bytes');
    await File(_sidecar(e.path)).writeAsString(jsonEncode(meta), flush: true);
  }

  Future<void> _remove(String pngPath) async {
    for (final path in [pngPath, _sidecar(pngPath)]) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
  }

  /// Drop the oldest unstarred pictures past the limit. Off still holds the
  /// newest one, because the phone serves and inserts from this folder.
  Future<bool> _trim(Directory dir) async {
    final limit = _limit();
    if (limit == kStudioRecentKeepAll) return false;
    final cap = limit < 1 ? 1 : limit;
    final unkept = (await _read(dir)).where((e) => !e.kept).toList();
    if (unkept.length <= cap) return false;
    for (final e in unkept.skip(cap)) {
      await _remove(e.path);
    }
    return true;
  }

  Future<List<StudioRecentEntry>> _read(Directory dir) async {
    if (!await dir.exists()) return const [];
    final out = <StudioRecentEntry>[];
    await for (final f in dir.list(followLinks: false)) {
      if (f is! File) continue;
      final name = p.basename(f.path);
      if (!isRecentName(name)) continue;
      try {
        out.add(await _entry(f, name));
      } on FileSystemException {
        // Deleted while listing (the user's file manager, another app).
      }
    }
    out.sort(
      (a, b) => b.name.length != a.name.length
          ? b.name.length.compareTo(a.name.length)
          : b.name.compareTo(a.name),
    );
    return out;
  }

  Future<StudioRecentEntry> _entry(File png, String name) async {
    final ms = int.parse(name.substring(4, name.length - 4));
    Map<String, dynamic> meta = const {};
    final side = File(_sidecar(png.path));
    try {
      if (await side.exists()) {
        final decoded = jsonDecode(await side.readAsString());
        if (decoded is Map<String, dynamic>) meta = decoded;
      }
    } on FormatException catch (e) {
      debugPrint('StudioRecentStore: unreadable notes for $name: $e');
    }
    return StudioRecentEntry(
      name: name,
      path: png.path,
      createdAt: DateTime.fromMillisecondsSinceEpoch(ms),
      prompt: meta['prompt']?.toString() ?? '',
      style: meta['style']?.toString() ?? '',
      mode: meta['mode'] == 'edit' ? 'edit' : 'create',
      model: meta['model']?.toString() ?? '',
      kept: meta['kept'] == true,
      bytes: await png.length(),
    );
  }
}

/// Put a fresh Image Studio result on the Recent shelf with the style and
/// model it was made with. One rule for the desktop Studio and the phone.
Future<StudioRecentEntry?> rememberStudioResult(
  StorageService storage,
  Uint8List png, {
  required String prompt,
  required bool edit,
}) {
  final settings = storage.imageGenSettings;
  return StudioRecentStore.of(storage).add(
    png,
    prompt: prompt,
    mode: edit ? 'edit' : 'create',
    style: settings.imageGenStyle,
    model: edit ? settings.imageGenEditModel : settings.imageGenModel,
  );
}
