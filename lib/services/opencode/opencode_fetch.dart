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

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

// The network and archive steps OpenCodeManager runs by default. Tests
// inject their own through the manager's constructor.

typedef OpenCodeDownloader =
    Future<List<int>> Function(
      Uri url, {
      void Function(int received, int? total)? onProgress,
    });

typedef OpenCodeUnpack = Future<File> Function(List<int> bytes, Directory dest);

typedef OpenCodePortPick = Future<int> Function();

typedef OpenCodeHealthGet =
    Future<({bool healthy, String version})> Function(Uri base);

typedef OpenCodeRemoteLookup =
    Future<({String tag, int? assetBytes})?> Function();

Future<List<int>> openCodeHttpDownload(
  Uri url, {
  void Function(int received, int? total)? onProgress,
}) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', url);
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw Exception('OpenCode download failed: HTTP ${response.statusCode}');
    }
    final chunks = <int>[];
    var received = 0;
    await for (final chunk in response.stream) {
      chunks.addAll(chunk);
      received += chunk.length;
      onProgress?.call(received, response.contentLength);
    }
    return chunks;
  } finally {
    client.close();
  }
}

Future<File> openCodeUnpackZip(List<int> bytes, Directory dest) async {
  await dest.create(recursive: true);
  final linuxTar = bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
  final archive = File(linuxTar ? '${dest.path}.tar.gz' : '${dest.path}.zip');
  await archive.writeAsBytes(bytes, flush: true);
  try {
    if (linuxTar) {
      final r = await Process.run('tar', [
        '-xzf',
        archive.path,
        '-C',
        dest.path,
      ]);
      if (r.exitCode != 0) {
        throw Exception('Unpack failed: ${r.stderr}');
      }
      return openCodeFindUnpackedBinary(dest);
    }
    if (Platform.isWindows) {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Expand-Archive -Force -Path "${archive.path}" '
            '-DestinationPath "${dest.path}"',
      ]);
      if (r.exitCode != 0) {
        throw Exception('Unpack failed: ${r.stderr}');
      }
    } else {
      final r = await Process.run('unzip', [
        '-o',
        archive.path,
        '-d',
        dest.path,
      ]);
      if (r.exitCode != 0) {
        throw Exception('Unpack failed: ${r.stderr}');
      }
    }
    return openCodeFindUnpackedBinary(dest);
  } finally {
    try {
      await archive.delete();
    } on FileSystemException catch (e) {
      debugPrint('[OpenCode] could not remove ${archive.path}: $e');
    }
  }
}

File openCodeFindUnpackedBinary(Directory dest) {
  final want = Platform.isWindows ? 'opencode.exe' : 'opencode';
  final direct = File(p.join(dest.path, want));
  if (direct.existsSync()) return direct;
  for (final entity in dest.listSync(recursive: true, followLinks: false)) {
    if (entity is File && p.basename(entity.path) == want) {
      return entity;
    }
  }
  throw Exception('OpenCode zip did not contain $want');
}

Future<int> openCodePickFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<({bool healthy, String version})> openCodeGetHealth(Uri base) async {
  final uri = base.replace(path: '/global/health');
  final resp = await http.get(uri).timeout(const Duration(seconds: 2));
  if (resp.statusCode != 200) {
    return (healthy: false, version: '');
  }
  final json = jsonDecode(resp.body);
  if (json is! Map) return (healthy: false, version: '');
  return (
    healthy: json['healthy'] == true,
    version: (json['version'] as String?) ?? '',
  );
}
