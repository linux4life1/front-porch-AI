// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proven red: a markdown-only plan (no YAML) plus Accept with the
// encoded editor body must flip status to accepted and mode to Build.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

const _mdOnly = '''
# Swift EPUB Reader with Metal GPU Acceleration

## Overview

A book.

---

## Stack
''';

void main() {
  test(
    'Accept of a markdown-only plan writes accepted and enters Build',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_accept_md_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      const rel = '.waifu/plans/swift-epub-reader.md';
      final file = File(p.join(root.path, rel));
      await file.create(recursive: true);
      await file.writeAsString(_mdOnly);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
        mode: WaifuMode.plan,
        activePlanPath: rel,
      );
      final loaded = await waifuLoadActivePlan(session);
      expect(loaded, isNotNull);
      expect(loaded!.status, WaifuPlanStatus.draft);
      final accepted = await waifuAcceptPlan(
        session: session,
        todos: WaifuTodos(),
        editedBody: waifuPlanEncode(loaded),
      );
      expect(accepted, isNotNull);
      expect(accepted!.status, WaifuPlanStatus.accepted);
      expect(session.mode, WaifuMode.build);
      expect(
        waifuPlanParse(await file.readAsString()).status,
        WaifuPlanStatus.accepted,
      );
    },
  );
}
