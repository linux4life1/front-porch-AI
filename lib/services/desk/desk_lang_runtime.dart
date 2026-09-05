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

import 'package:crypto/crypto.dart';
import 'package:front_porch_ai/services/desk/desk_lang_catalog.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class DeskLangBytes {
  const DeskLangBytes(this.url, this.bytes);
  final String url;
  final List<int> bytes;
}

abstract class DeskLangProc {
  bool get running;
  Future<void> kill();
}

typedef DeskLangFetch = Future<DeskLangBytes> Function(String url);
typedef DeskLangWhich = Future<String?> Function(String command);
typedef DeskLangStart =
    Future<DeskLangProc> Function(String command, List<String> args);

/// Opt-in language doors. Yolo does not auto-enable. Sit down does not fetch.
class DeskLangRuntime {
  DeskLangRuntime({
    required this.directory,
    List<DeskLangDoor>? catalog,
    DeskLangFetch? fetch,
    DeskLangWhich? which,
    DeskLangStart? start,
  }) : catalog = List<DeskLangDoor>.from(catalog ?? kDeskLangCatalog),
       fetch = fetch ?? _defaultFetch,
       which = which ?? _defaultWhich,
       start = start ?? _defaultStart;

  final String directory;
  final List<DeskLangDoor> catalog;
  final DeskLangFetch fetch;
  final DeskLangWhich which;
  final DeskLangStart start;

  final enabled = <String>{};
  final _procs = <String, DeskLangProc>{};

  DeskLangDoor? door(String id) {
    for (final d in catalog) {
      if (d.id == id) return d;
    }
    return null;
  }

  void addCustom({
    required String id,
    required String command,
    List<String> args = const [],
    List<String> extensions = const [],
  }) {
    catalog.removeWhere((d) => d.id == id);
    catalog.add(
      DeskLangDoor(
        id: id,
        name: id,
        pathCommand: command,
        args: args,
        extensions: extensions,
      ),
    );
  }

  Future<void> enable(String id) async {
    if (enabled.contains(id)) return;
    final d = door(id);
    if (d == null) return;
    String? cmd;
    if (d.pathCommand != null && d.pathCommand!.trim().isNotEmpty) {
      final installed = await which(d.pathCommand!);
      cmd = installed ?? d.pathCommand;
      if (installed == null && d.url != null) cmd = null;
    }
    if (cmd == null && d.url != null && d.sha256 != null) {
      final body = await fetch(d.url!);
      final digest = sha256.convert(body.bytes).toString();
      if (digest != d.sha256) return;
      final file = File(p.join(directory, id, 'lsp.bin'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(body.bytes);
      cmd = file.path;
    }
    if (cmd == null || cmd.trim().isEmpty) return;
    final proc = await start(cmd, d.args);
    _procs[id] = proc;
    enabled.add(id);
  }

  Future<void> disable(String id) async {
    final proc = _procs.remove(id);
    enabled.remove(id);
    if (proc != null) await proc.kill();
  }

  Future<void> killAll() async {
    final ids = enabled.toList();
    for (final id in ids) {
      await disable(id);
    }
  }
}

Future<DeskLangBytes> _defaultFetch(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return DeskLangBytes(url, const []);
  }
  final client = http.Client();
  try {
    final req = http.Request('GET', uri)..followRedirects = false;
    final streamed = await client.send(req);
    if (streamed.statusCode != 200) {
      return DeskLangBytes(url, const []);
    }
    return DeskLangBytes(url, await streamed.stream.toBytes());
  } finally {
    client.close();
  }
}

Future<String?> _defaultWhich(String command) async {
  try {
    final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
      command,
    ]);
    if (result.exitCode != 0) return null;
    final line = result.stdout.toString().trim().split('\n').first.trim();
    return line.isEmpty ? null : line;
  } catch (_) {
    return null;
  }
}

Future<DeskLangProc> _defaultStart(String command, List<String> args) async {
  final proc = await Process.start(command, args);
  return _IoProc(proc);
}

class _IoProc implements DeskLangProc {
  _IoProc(this._process);
  final Process _process;
  var _running = true;

  @override
  bool get running => _running;

  @override
  Future<void> kill() async {
    _running = false;
    _process.kill();
  }
}
