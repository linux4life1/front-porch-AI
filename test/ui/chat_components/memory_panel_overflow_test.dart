// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Memory (RAG) sidebar: Settings / Sources / Data Bank used to sit in a
// rigid Row. The chat sidebar has no fixed width — dragging it to ~225px
// overflowed that Row by 8px (and by 0–2px as the drag continued). This
// pumps the real MemoryPanel at the reported width, the test-font
// near-miss, and a tighter wrap.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/memory_panel.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

class _FakeEmb extends ChangeNotifier implements EmbeddingService {
  @override
  bool get isAvailable => true;
  @override
  bool get isSettingUp => false;
  @override
  double get setupProgress => -1;
  @override
  String? get setupError => null;
  @override
  bool get modelOnDisk => true;
  @override
  String? get lastEngineError => null;
  @override
  String get setupStatus => '';
  @override
  void ensureReady() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpPanel(WidgetTester tester, {required double width}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  addTearDown(storage.dispose);
  await storage.memorySettings.setRagEnabled(true);
  final chat = FakeChatService();
  addTearDown(chat.dispose);
  final emb = _FakeEmb();
  addTearDown(emb.dispose);

  tester.view.physicalSize = Size(width + 40, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: storage),
        ChangeNotifierProvider<EmbeddingService>.value(value: emb),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: SingleChildScrollView(child: MemoryPanel(chatService: chat)),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setupPathProviderMock();

  // 225.4 is the field report. 200 is the Row's near-miss with test
  // fonts (2px overflow — same class as the field's 0.2–8px reports).
  // 180 forces the chips onto two lines.
  for (final width in [225.4, 200.0, 180.0]) {
    testWidgets('MemoryPanel controls do not overflow at $width', (
      tester,
    ) async {
      await _pumpPanel(tester, width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Sources'), findsOneWidget);
      expect(find.text('Data Bank'), findsOneWidget);
    });
  }
}
