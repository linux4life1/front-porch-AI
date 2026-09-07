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

import 'package:front_porch_ai/services/waifu/waifu_jail.dart';
import 'package:front_porch_ai/services/waifu/waifu_permissions.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_tools.dart';
import 'package:path/path.dart' as p;

class WaifuToolResult {
  const WaifuToolResult({required this.ok, required this.output, this.write});

  final bool ok;
  final String output;
  final WaifuWriteRecord? write;

  factory WaifuToolResult.error(String message) =>
      WaifuToolResult(ok: false, output: message);
}

/// In-process file tools. Every path goes through [WaifuJail].
class WaifuFs {
  WaifuFs(this.root);

  final String root;

  Future<WaifuToolResult> dispatch(
    String name,
    Map<String, dynamic> args,
  ) async {
    switch (canonicalWaifuToolName(name)) {
      case kWaifuToolRead:
        return _read(args);
      case kWaifuToolEdit:
        return _edit(args);
      case kWaifuToolWrite:
        return _write(args);
      case kWaifuToolGlob:
        return _glob(args);
      case kWaifuToolGrep:
        return _grep(args);
      default:
        return WaifuToolResult.error('unknown tool: $name');
    }
  }

  Future<WaifuJailHit> _hit(String? path) async {
    if (path == null) {
      return const WaifuJailHit.denied('jail: path is empty');
    }
    return WaifuJail.resolveLive(root, path);
  }

  Future<WaifuToolResult> _read(Map<String, dynamic> args) async {
    final hit = await _hit(waifuToolPathArg(args));
    if (!hit.ok) return WaifuToolResult.error(hit.error!);
    final file = File(hit.path!);
    if (!await file.exists()) {
      return WaifuToolResult.error('file not found: ${waifuToolPathArg(args)}');
    }
    final bytes = await file.readAsBytes();
    if (bytes.contains(0)) {
      return WaifuToolResult.error('binary file: ${waifuToolPathArg(args)}');
    }
    var text = utf8.decode(bytes, allowMalformed: true);
    final offset = _intArg(args, 'offset');
    final limit = _intArg(args, 'limit');
    if (offset != null || limit != null) {
      final lines = text.split('\n');
      final start = ((offset ?? 1) - 1).clamp(0, lines.length);
      final end = (start + (limit ?? lines.length)).clamp(0, lines.length);
      text = lines.sublist(start, end).join('\n');
    }
    if (text.length > kWaifuReadClipChars) {
      text = '${text.substring(0, kWaifuReadClipChars)}\n…(clipped)';
    }
    return WaifuToolResult(ok: true, output: text);
  }

  Future<WaifuToolResult> _write(Map<String, dynamic> args) async {
    final rel = waifuToolPathArg(args);
    final hit = await _hit(rel);
    if (!hit.ok) return WaifuToolResult.error(hit.error!);
    final contents =
        args['contents']?.toString() ??
        args['content']?.toString() ??
        args['text']?.toString() ??
        '';
    final file = File(hit.path!);
    var before = '';
    if (await file.exists()) {
      before = await file.readAsString();
    }
    await file.parent.create(recursive: true);
    try {
      await file.writeAsString(contents);
    } catch (e) {
      return WaifuToolResult.error('write failed: $e');
    }
    final shown = await _rel(hit.path!);
    return WaifuToolResult(
      ok: true,
      output: 'wrote $shown (${contents.length} chars)',
      write: WaifuWriteRecord(
        relativePath: shown,
        before: before,
        after: contents,
      ),
    );
  }

  Future<WaifuToolResult> _edit(Map<String, dynamic> args) async {
    final rel = waifuToolPathArg(args);
    final hit = await _hit(rel);
    if (!hit.ok) return WaifuToolResult.error(hit.error!);
    final old = args['old_string']?.toString() ?? '';
    final neu = args['new_string']?.toString() ?? '';
    if (old.isEmpty) {
      return WaifuToolResult.error('old_string is empty');
    }
    final file = File(hit.path!);
    if (!await file.exists()) {
      return WaifuToolResult.error('file not found: $rel');
    }
    final before = await file.readAsString();
    final count = old.allMatches(before).length;
    if (count != 1) {
      return WaifuToolResult.error(
        'old_string must match exactly once (found $count)',
      );
    }
    final after = before.replaceFirst(old, neu);
    try {
      await file.writeAsString(after);
    } catch (e) {
      return WaifuToolResult.error('edit failed: $e');
    }
    final shown = await _rel(hit.path!);
    return WaifuToolResult(
      ok: true,
      output: 'edited $shown',
      write: WaifuWriteRecord(relativePath: shown, before: before, after: after),
    );
  }

  Future<WaifuToolResult> _glob(Map<String, dynamic> args) async {
    final pattern = args['pattern']?.toString() ?? '';
    if (pattern.isEmpty) {
      return WaifuToolResult.error('pattern is empty');
    }
    var start = root;
    final pathArg = waifuToolPathArg(args);
    if (pathArg != null) {
      final hit = await _hit(pathArg);
      if (!hit.ok) return WaifuToolResult.error(hit.error!);
      start = hit.path!;
    }
    final matches = <String>[];
    await for (final entity in Directory(
      start,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = await _rel(entity.path);
      if (waifuIsEnvPath(rel)) continue;
      if (waifuGlobMatch(rel, pattern)) matches.add(rel);
    }
    matches.sort();
    return WaifuToolResult(
      ok: true,
      output: matches.isEmpty ? '(no matches)' : matches.join('\n'),
    );
  }

  Future<WaifuToolResult> _grep(Map<String, dynamic> args) async {
    final pattern = args['pattern']?.toString() ?? '';
    if (pattern.isEmpty) {
      return WaifuToolResult.error('pattern is empty');
    }
    final glob = args['glob']?.toString();
    final pathArg = waifuToolPathArg(args);
    String start = root;
    if (pathArg != null) {
      final hit = await _hit(pathArg);
      if (!hit.ok) return WaifuToolResult.error(hit.error!);
      start = hit.path!;
    }
    final re = _compile(pattern);
    final hits = <String>[];
    final files = <File>[];
    final asFile = File(start);
    if (await asFile.exists()) {
      files.add(asFile);
    } else {
      await for (final entity in Directory(
        start,
      ).list(recursive: true, followLinks: false)) {
        if (entity is File) files.add(entity);
      }
    }
    for (final file in files) {
      if (hits.length >= kWaifuGrepMaxHits) break;
      final rel = await _rel(file.path);
      if (waifuIsEnvPath(rel)) continue;
      if (glob != null && glob.isNotEmpty && !waifuGlobMatch(rel, glob)) {
        continue;
      }
      String text;
      try {
        final bytes = await file.readAsBytes();
        if (bytes.contains(0)) continue;
        text = utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        continue;
      }
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (hits.length >= kWaifuGrepMaxHits) break;
        if (re.hasMatch(lines[i])) {
          hits.add('$rel:${i + 1}:${lines[i]}');
        }
      }
    }
    return WaifuToolResult(
      ok: true,
      output: hits.isEmpty ? '(no matches)' : hits.join('\n'),
    );
  }

  Future<String> _rel(String abs) async {
    final rootReal = await WaifuJail.canonicalRoot(root);
    final rel = p.relative(abs, from: rootReal).replaceAll('\\', '/');
    if (rel.startsWith('..')) return abs.replaceAll('\\', '/');
    return p.posix.normalize(rel);
  }
}

int? _intArg(Map<String, dynamic> args, String key) {
  final v = args[key];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

RegExp _compile(String pattern) {
  try {
    return RegExp(pattern);
  } catch (_) {
    return RegExp(RegExp.escape(pattern));
  }
}

bool waifuGlobMatch(String relative, String pattern) {
  final rel = relative.replaceAll('\\', '/');
  var pat = pattern.replaceAll('\\', '/');
  if (pat.startsWith('./')) pat = pat.substring(2);
  return _globToRegex(pat).hasMatch(rel);
}

RegExp _globToRegex(String pat) {
  final buf = StringBuffer('^');
  for (var i = 0; i < pat.length; i++) {
    final c = pat[i];
    if (c == '*') {
      if (i + 1 < pat.length && pat[i + 1] == '*') {
        i++;
        if (i + 1 < pat.length && pat[i + 1] == '/') {
          i++;
          buf.write('(?:.*/)?');
        } else {
          buf.write('.*');
        }
      } else {
        buf.write('[^/]*');
      }
    } else if (c == '?') {
      buf.write('[^/]');
    } else {
      buf.write(RegExp.escape(c));
    }
  }
  buf.write(r'$');
  return RegExp(buf.toString());
}
