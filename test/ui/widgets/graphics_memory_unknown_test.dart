// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// When the graphics card's memory could not be read (0 MB), Manage Models
// said "0% of available VRAM" for every model, Settings said "0 MB of
// graphics memory", and the Local model card told every model it was "much
// bigger than your graphics card", all against a card of size zero. Unknown
// is now said as unknown, with no bigger/smaller verdict. The estimate's
// maths is untouched: only the unknown case changes.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/local_model_card.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../golden/support/fakes_storage.dart';
import '../../helpers/settings_page_harness.dart';

const _dir = 'test/fixtures/gguf_headers';

/// What the Linux sweep machine read without lspci: no name, no memory.
final _undetected = HardwareInfo(
  gpuName: 'Unknown GPU',
  vramMb: 0,
  ramMb: 32768,
  vendor: 'Unknown',
);

({GGUFModelInfo info, int bytes}) _model(String name) {
  final side = (jsonDecode(File('$_dir/$name.json').readAsStringSync()) as Map)
      .cast<String, dynamic>();
  final header = GGUFFileReader.parseHeaderBytes(
    File('$_dir/$name.gguf').readAsBytesSync(),
  )!;
  final bytes = side['fixture_file_bytes'] as int;
  return (
    info: GGUFParser.modelInfoFromHeader(header, fileSize: bytes)!,
    bytes: bytes,
  );
}

void main() {
  test('the Local model card gives no "bigger than your card" verdict '
      'against an unread card', () async {
    final qwen = _model('Qwen3-14B');
    // As on the sweep machine: Vulkan chosen in Settings, card unread.
    final storage = FakeStorageService();
    await storage.backendSettings.setUseVulkan(true);
    final facts = KoboldStatusFacts.of(
      storage: storage,
      hardware: _undetected,
      free: (graphics: null, system: 16384),
      info: qwen.info,
      bytes: qwen.bytes,
    )!;
    final pace = facts.lines.first;
    expect(pace, isNot(contains('bigger')));
    expect(pace, isNot(contains('fits')));
    expect(pace, contains('could not be read'));
  });

  testWidgets('My Models says the fit is unknown, not 0%', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalModelCard(
            model: LocalModelInfo(
              path: '/models/Qwen3-30B-A3B-Q4_K_M.gguf',
              filename: 'Qwen3-30B-A3B-Q4_K_M.gguf',
              sizeBytes: 18_556_686_336,
              modified: DateTime(2026, 1, 1),
            ),
            availableVramMb: 0,
            onDelete: () {},
          ),
        ),
      ),
    );
    expect(find.textContaining('of available VRAM'), findsNothing);
    expect(find.text(kGraphicsMemoryUnknown), findsOneWidget);
  });

  testWidgets('Settings names the memory as not detected, not 0 MB', (
    tester,
  ) async {
    await mountSettings(tester, lastUsedIsB: false, hardware: _undetected);
    await openTab(tester, 'Advanced');
    expect(find.text('0 MB of graphics memory.'), findsNothing);
    expect(find.text('$kGraphicsMemoryUnknown.'), findsOneWidget);
  });
}
