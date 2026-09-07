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

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_i_holes_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('PATH-installed wins: url is not fetched', () async {
    var fetched = 0;
    var started = <String>[];
    final langs = WaifuLangRuntime(
      directory: p.join(root.path, 'lang'),
      catalog: [
        const WaifuLangDoor(
          id: 'rust',
          name: 'Rust',
          pathCommand: 'rust-analyzer',
          url: 'https://example.test/rs',
          sha256: 'abc',
        ),
      ],
      fetch: (url) async {
        fetched++;
        return WaifuLangBytes(url, const [1]);
      },
      which: (cmd) async =>
          cmd == 'rust-analyzer' ? '/usr/bin/rust-analyzer' : null,
      start: (cmd, args) async {
        started.add(cmd);
        return _FakeProc();
      },
    );
    await langs.enable('rust');
    expect(fetched, 0);
    expect(started, ['/usr/bin/rust-analyzer']);
    expect(langs.enabled, {'rust'});
  });

  test('Holy C enable does not HTTP or spawn', () async {
    var hits = 0;
    var spawned = 0;
    final langs = WaifuLangRuntime(
      directory: p.join(root.path, 'lang'),
      fetch: (url) async {
        hits++;
        return WaifuLangBytes(url, const [1]);
      },
      start: (cmd, args) async {
        spawned++;
        return _FakeProc();
      },
    );
    await langs.enable('holy_c');
    expect(hits, 0);
    expect(spawned, 0);
    expect(langs.enabled, isEmpty);
  });

  test('default fetch refuses file:// and does not spawn', () async {
    var spawned = 0;
    final langs = WaifuLangRuntime(
      directory: p.join(root.path, 'lang'),
      catalog: [
        const WaifuLangDoor(
          id: 'evil',
          name: 'Evil',
          url: 'file:///etc/passwd',
          sha256: '00',
        ),
      ],
      start: (cmd, args) async {
        spawned++;
        return _FakeProc();
      },
    );
    await langs.enable('evil');
    expect(spawned, 0);
    expect(langs.enabled, isEmpty);
  });
}

class _FakeProc implements WaifuLangProc {
  @override
  var running = true;

  @override
  Future<void> kill() async {
    running = false;
  }
}
