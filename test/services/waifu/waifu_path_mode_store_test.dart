// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('whole-disk choice survives a parked-session reload', () async {
    final dir = await Directory.systemTemp.createTemp('waifu_scope_store_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final store = WaifuStore(dir.path);
    await store.saveLast(
      WaifuSession(
        folderRoot: '${dir.path}/project',
        coworker: CharacterCard(
          name: 'Iris',
          systemPrompt: 'Keep the author voice.',
          mesExample: 'Iris: Hmph.',
        ),
        pathMode: WaifuPathMode.wholeDisk,
      ),
    );

    final loaded = await store.loadLast();
    expect(loaded, isNotNull);
    final restored = loaded!;
    expect(restored.pathMode, WaifuPathMode.wholeDisk);
    expect(restored.coworker.systemPrompt, 'Keep the author voice.');
    expect(restored.coworker.mesExample, 'Iris: Hmph.');
  });
}
