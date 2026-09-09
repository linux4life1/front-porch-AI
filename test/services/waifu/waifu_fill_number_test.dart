// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  test('API usage is the fill number, not a second chars/4 guess', () {
    final estimate = waifuMeasureRequest(
      systemPrompt: 'sys',
      prompt: 'hello',
      budget: 8192,
    );
    expect(
      waifuFillUsed(tokensUsed: 9000, fromApi: true, estimated: estimate.used),
      9000,
    );
    expect(
      waifuFillUsed(tokensUsed: 0, fromApi: false, estimated: estimate.used),
      estimate.used,
    );
    expect(waifuShouldCompact(used: 9000, budget: 8192), isTrue);
    expect(waifuShouldCompact(used: 9000, budget: 277518), isFalse);
  });

  test('resume restores contextBudget so 277k does not become 8192', () async {
    final dir = await Directory.systemTemp.createTemp('waifu_fill_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final folder = p.join(dir.path, 'proj');
    final session =
        WaifuSession(
            folderRoot: folder,
            coworker: CharacterCard(name: 'Iris'),
          )
          ..contextBudget = 277518
          ..tokensUsed = 30490
          ..tokensFromApi = true;
    await WaifuStore(dir.path).saveLast(session);
    final loaded = await WaifuStore(dir.path).loadSession(folder);
    expect(loaded, isNotNull);
    expect(loaded!.contextBudget, 277518);
    expect(loaded.tokensUsed, 30490);
    expect(loaded.tokensFromApi, isTrue);
  });
}
