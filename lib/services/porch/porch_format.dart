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

/// `.porch` (one character) and `.porchpack` (several) files: zips with a
/// manifest. Pure: no Flutter, no I/O, safe to run in an isolate.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const String kPorchExtension = 'porch';
const String kPorchPackExtension = 'porchpack';
const String kPorchFormatId = 'fpai_porch';
const String kPorchPackFormatId = 'fpai_porchpack';
const int kPorchFormatVersion = 1;
const int kPorchPackFormatVersion = 1;
const String kPorchManifestName = 'manifest.json';

/// Unpacked ceiling for one file, checked against the sizes the archive
/// declares before anything is inflated. Each chat inside also keeps the
/// `.fpchat` codec's own ceiling.
const int kPorchMaxUnpackedBytes = 1024 * 1024 * 1024;

/// Ceiling on entries in one file (chats, images, or characters in a pack).
const int kPorchMaxEntries = 10000;

/// A file the importer will not use, said in words a person can act on.
class PorchRefused implements Exception {
  const PorchRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One gallery image: a look ([label] null) or an expression image.
class PorchImage {
  const PorchImage({required this.bytes, this.label, this.starred = false});
  final Uint8List bytes;
  final String? label;

  /// The character's ★ avatar (card cover and default face).
  final bool starred;
}

/// Everything one `.porch` carries.
class PorchCharacter {
  const PorchCharacter({
    required this.name,
    required this.stableId,
    required this.stableGroupId,
    required this.cardPng,
    this.chats = const [],
    this.looks = const [],
    this.expressions = const [],
  });

  final String name;

  /// The id the card itself carries (front_porch `stableId`); null on cards
  /// that never had one.
  final String? stableId;

  /// The exporting library's portrait basename, which keys its chats.
  final String stableGroupId;

  /// The V2 card PNG: portrait pixels, card fields and lorebook.
  final Uint8List cardPng;

  /// One `.fpchat` package per 1:1 chat, newest first.
  final List<Uint8List> chats;
  final List<PorchImage> looks;
  final List<PorchImage> expressions;
}

/// A file name for [characterName] that every desktop system accepts.
String porchSafeName(String characterName) {
  final cleaned = characterName
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  final capped = cleaned.length > 80
      ? cleaned.substring(0, 80).trim()
      : cleaned;
  return capped.isEmpty ? 'Character' : capped;
}

String porchFileName(String characterName) =>
    '${porchSafeName(characterName)}.$kPorchExtension';

String porchPackFileName(int count) =>
    'Front Porch characters ($count).$kPorchPackExtension';

Uint8List encodePorch(PorchCharacter c, {String appVersion = ''}) {
  final archive = Archive();
  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile(name, bytes.length, bytes));

  String pad(int i) => (i + 1).toString().padLeft(3, '0');
  final chats = [
    for (var i = 0; i < c.chats.length; i++) 'chats/${pad(i)}.fpchat',
  ];
  final looks = [
    for (var i = 0; i < c.looks.length; i++) 'looks/${pad(i)}.png',
  ];
  final faces = [
    for (var i = 0; i < c.expressions.length; i++) 'expressions/${pad(i)}.png',
  ];
  final manifest = <String, dynamic>{
    'format': kPorchFormatId,
    'version': kPorchFormatVersion,
    if (appVersion.isNotEmpty) 'app_version': appVersion,
    'name': c.name,
    if (c.stableId != null && c.stableId!.isNotEmpty) 'stable_id': c.stableId,
    'stable_group_id': c.stableGroupId,
    'card': 'card.png',
    'chats': chats,
    'looks': [
      for (var i = 0; i < c.looks.length; i++)
        {'file': looks[i], 'starred': c.looks[i].starred},
    ],
    'expressions': [
      for (var i = 0; i < c.expressions.length; i++)
        {
          'file': faces[i],
          'label': c.expressions[i].label,
          'starred': c.expressions[i].starred,
        },
    ],
  };
  add(kPorchManifestName, utf8.encode(jsonEncode(manifest)));
  add('card.png', c.cardPng);
  for (var i = 0; i < chats.length; i++) {
    add(chats[i], c.chats[i]);
  }
  for (var i = 0; i < looks.length; i++) {
    add(looks[i], c.looks[i].bytes);
  }
  for (var i = 0; i < faces.length; i++) {
    add(faces[i], c.expressions[i].bytes);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

PorchCharacter decodePorch(Uint8List bytes, {required String fileName}) {
  final files = _unzip(bytes, fileName);
  final manifest = _manifest(files, fileName, kPorchFormatId, () {
    return '“$fileName” isn’t a Front Porch character file. Export the '
        'character from Front Porch AI as a .porch file, then import that.';
  });
  _checkVersion(manifest, kPorchFormatVersion, fileName);

  final incomplete = PorchRefused(
    '“$fileName” is incomplete: part of the character is missing. Export the '
    'character again, then import the new file.',
  );
  Uint8List need(Object? path) {
    final data = path is String ? files[path] : null;
    if (data == null) throw incomplete;
    return data;
  }

  List<PorchImage> images(Object? list, {required bool withLabel}) {
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map)
          PorchImage(
            bytes: need(e['file']),
            label: withLabel && e['label'] is String ? e['label'] : null,
            starred: e['starred'] == true,
          ),
    ];
  }

  final name = manifest['name'];
  final stableGroupId = manifest['stable_group_id'];
  if (name is! String || name.trim().isEmpty || stableGroupId is! String) {
    throw incomplete;
  }
  final chats = manifest['chats'];
  final stableId = manifest['stable_id'];
  return PorchCharacter(
    name: name,
    stableId: stableId is String && stableId.isNotEmpty ? stableId : null,
    stableGroupId: stableGroupId,
    cardPng: need(manifest['card']),
    chats: chats is List ? [for (final p in chats) need(p)] : const [],
    looks: images(manifest['looks'], withLabel: false),
    expressions: images(manifest['expressions'], withLabel: true),
  );
}

Uint8List encodePorchPack(
  List<({String name, Uint8List bytes})> characters, {
  String appVersion = '',
}) {
  final archive = Archive();
  final used = <String>{};
  final entries = <Map<String, String>>[];
  for (final c in characters) {
    final base = porchSafeName(c.name);
    var file = '$base.$kPorchExtension';
    for (var n = 2; !used.add(file.toLowerCase()); n++) {
      file = '$base ($n).$kPorchExtension';
    }
    entries.add({'file': file, 'name': c.name});
    archive.addFile(ArchiveFile(file, c.bytes.length, c.bytes));
  }
  final manifest = utf8.encode(
    jsonEncode({
      'format': kPorchPackFormatId,
      'version': kPorchPackFormatVersion,
      if (appVersion.isNotEmpty) 'app_version': appVersion,
      'entries': entries,
    }),
  );
  archive.addFile(ArchiveFile(kPorchManifestName, manifest.length, manifest));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// The `.porch` files a pack lists, in its order. The manifest is checked
/// before any character is read.
List<({String fileName, Uint8List bytes})> decodePorchPack(
  Uint8List bytes, {
  required String fileName,
}) {
  final files = _unzip(bytes, fileName);
  final manifest = _manifest(files, fileName, kPorchPackFormatId, () {
    return '“$fileName” is missing its list of characters, so it can’t be '
        'read. Export the characters from Front Porch AI again.';
  });
  _checkVersion(manifest, kPorchPackFormatVersion, fileName);
  final entries = manifest['entries'];
  if (entries is! List || entries.isEmpty) {
    throw PorchRefused(
      '“$fileName” is missing its list of characters, so it can’t be read. '
      'Export the characters from Front Porch AI again.',
    );
  }
  final out = <({String fileName, Uint8List bytes})>[];
  var missing = 0;
  for (final e in entries) {
    final file = e is Map ? e['file'] : null;
    final data = file is String && file.endsWith('.$kPorchExtension')
        ? files[file]
        : null;
    if (data == null) {
      missing++;
    } else {
      out.add((fileName: file as String, bytes: data));
    }
  }
  if (missing > 0) {
    throw PorchRefused(
      '“$fileName” is incomplete: $missing of its ${entries.length} '
      'characters are missing. Export them again, then import the new file.',
    );
  }
  return out;
}

Map<String, Uint8List> _unzip(Uint8List bytes, String fileName) {
  final damaged = PorchRefused(
    '“$fileName” couldn’t be opened. It may be damaged or only partly '
    'copied. Export it again, then import the new file.',
  );
  // The decoder returns an empty archive for bytes that are not a zip at
  // all, so check the local-file signature (PK\x03\x04) first.
  if (bytes.length < 4 ||
      bytes[0] != 0x50 ||
      bytes[1] != 0x4B ||
      bytes[2] != 0x03 ||
      bytes[3] != 0x04) {
    throw damaged;
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: true);
  } catch (_) {
    throw damaged;
  }
  if (archive.files.isEmpty) throw damaged;
  final out = <String, Uint8List>{};
  var unpacked = 0;
  for (final file in archive.files) {
    if (!file.isFile) continue;
    unpacked += file.size;
    if (out.length >= kPorchMaxEntries || unpacked > kPorchMaxUnpackedBytes) {
      throw PorchRefused(
        '“$fileName” is too large to import. Export fewer characters at a '
        'time, then import those files.',
      );
    }
    try {
      final data = file.content as List<int>;
      out[file.name.replaceAll('\\', '/')] = data is Uint8List
          ? data
          : Uint8List.fromList(data);
    } catch (_) {
      throw damaged;
    }
  }
  return out;
}

Map<String, dynamic> _manifest(
  Map<String, Uint8List> files,
  String fileName,
  String formatId,
  String Function() notOurs,
) {
  final raw = files[kPorchManifestName];
  if (raw == null) throw PorchRefused(notOurs());
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(raw));
  } catch (_) {
    throw PorchRefused(notOurs());
  }
  if (decoded is! Map || decoded['format'] != formatId) {
    throw PorchRefused(notOurs());
  }
  return Map<String, dynamic>.from(decoded);
}

void _checkVersion(Map<String, dynamic> manifest, int known, String fileName) {
  final v = manifest['version'];
  if (v is! int || v < 1) {
    throw PorchRefused(
      '“$fileName” has a contents list this app can’t read. Export it again '
      'from Front Porch AI, then import the new file.',
    );
  }
  if (v > known) {
    throw PorchRefused(
      '“$fileName” was made by a newer Front Porch AI. Update the app, then '
      'import it again.',
    );
  }
}
