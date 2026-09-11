// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('honesty, Yolo, MCP, and tool copy tell the selected truth', () {
    final jailed = waifuHonestyBody(WaifuPathMode.folderJail);
    final open = waifuHonestyBody(WaifuPathMode.wholeDisk);
    expect(jailed, contains('safer default'));
    expect(jailed, contains('stay inside'));
    expect(open, contains('starting porch, not a fence'));
    expect(open, contains('absolute paths, ~, .., and cd'));

    expect(
      waifuYoloWarning(WaifuPathMode.folderJail),
      contains('folder jail still holds'),
    );
    expect(waifuYoloWarning(WaifuPathMode.wholeDisk), contains('whole disk'));
    expect(
      waifuYoloWarning(WaifuPathMode.wholeDisk),
      isNot(contains('jail still holds')),
    );
    expect(
      waifuMcpScopeWarning(WaifuPathMode.folderJail),
      contains('folder jail covers'),
    );
    expect(
      waifuMcpScopeWarning(WaifuPathMode.wholeDisk),
      contains('Whole-disk access is already open'),
    );
  });
}
