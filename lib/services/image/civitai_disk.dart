// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Free bytes on the volume that holds [path], or null when this platform
/// will not say. The nearest folder that exists is asked, so a models
/// subfolder that is not created yet still gets an answer.
Future<int?> civitaiFreeDiskBytes(String path) async {
  var probe = p.normalize(path);
  while (!await Directory(probe).exists()) {
    final parent = p.dirname(probe);
    if (parent == probe) return null;
    probe = parent;
  }
  try {
    if (Platform.isWindows) return await _freeWindows(probe);
    return await _freePosix(probe);
  } catch (e) {
    debugPrint('civitai free-space probe failed: ${e.runtimeType}');
    return null;
  }
}

final RegExp _dfRow = RegExp(r'^(.+?)\s+(\d+)\s+(\d+)\s+(\d+)\s+\d+%\s+(.*)$');

Future<int?> _freePosix(String dir) async {
  final result = await Process.run('df', ['-Pk', dir]);
  if (result.exitCode != 0) return null;
  final lines = '${result.stdout}'.trim().split('\n');
  for (final line in lines.reversed) {
    final match = _dfRow.firstMatch(line.trim());
    if (match == null) continue;
    final kilobytes = int.tryParse(match.group(4) ?? '');
    return kilobytes == null ? null : kilobytes * 1024;
  }
  return null;
}

Future<int?> _freeWindows(String dir) async {
  final drive = p.rootPrefix(dir);
  if (drive.length < 2 || drive[1] != ':') return null;
  final result = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    "([System.IO.DriveInfo]::new('${drive[0]}')).AvailableFreeSpace",
  ]);
  if (result.exitCode != 0) return null;
  return int.tryParse('${result.stdout}'.trim());
}
