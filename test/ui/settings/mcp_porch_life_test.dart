// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Porch Life no longer hosts Docker MCP. Web Search stays. Recipe cards
// load from the library tools/ folder — the note names that path.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _PorchStorage extends FakeStorageService {
  _PorchStorage() {
    _realism.initializeBase(null, notifyListeners);
  }

  final RealismSettings _realism = RealismSettings();

  @override
  RealismSettings get realismSettings => _realism;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('Porch Life shows Web Search and the tools folder, not MCP', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _PorchStorage();
    final chat = FakeChatService();
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: const MaterialApp(home: Scaffold(body: PorchLifeTab())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Web Search'),
      300,
      scrollable: scrollable,
    );
    expect(find.text('Web Search'), findsOneWidget);
    expect(find.text('MCP tools'), findsNothing);
    expect(find.text('Connect Docker MCP'), findsNothing);
    expect(find.byKey(const Key('user-tools-folder-note')), findsOneWidget);
    expect(find.byKey(const Key('mcp-add-url')), findsNothing);
  });
}
