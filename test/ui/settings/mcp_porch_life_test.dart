// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Porch Life no longer hosts Docker MCP. Web Search stays. Recipe cards
// load from the library tools/ folder — the note names that path.

import 'dart:io';

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

  @override
  bool get adultThemesEnabled => _realism.adultThemesEnabled;
  @override
  bool get realismDefault => _realism.realismDefault;
  @override
  bool get nsfwCooldownDefault => _realism.nsfwCooldownDefault;
  @override
  bool get objectivesEnabled => _realism.objectivesEnabled;
  @override
  bool get passageOfTimeDefault => _realism.passageOfTimeDefault;
  @override
  bool get standaloneClockEnabled => _realism.standaloneClockEnabled;
  @override
  bool get weatherEnabled => _realism.weatherEnabled;
  @override
  bool get weatherFahrenheit => _realism.weatherFahrenheit;
  @override
  bool get needsSimDefault => _realism.needsSimDefault;
  @override
  bool get dreamsEnabled => _realism.dreamsEnabled;
  @override
  bool get absenceBannerEnabled => _realism.absenceBannerEnabled;
  @override
  bool get absenceAckEnabled => _realism.absenceAckEnabled;
  @override
  int get absenceThresholdHours => _realism.absenceThresholdHours;
  @override
  bool get characterEvolutionEnabled => false;
  @override
  bool get journalEnabled => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('Settings has no MCP tab and no Docker MCP connect UI', () {
    final settings = File('lib/ui/pages/settings_page.dart').readAsStringSync();
    expect(settings, isNot(contains("Tab(text: 'MCP')")));
    expect(settings, contains("Tab(text: 'Porch Life')"));
    expect(File('lib/ui/settings/tabs/mcp_tab.dart').existsSync(), isFalse);
    expect(
      File('lib/ui/settings/widgets/mcp_servers_card.dart').existsSync(),
      isFalse,
    );
    final mcpWeb = File(
      'lib/ui/settings/tabs/porch_life_mcp_web_card.dart',
    ).readAsStringSync();
    expect(mcpWeb, isNot(contains('Connect Docker MCP')));
    expect(mcpWeb, isNot(contains('McpServersPanel')));
    expect(mcpWeb, contains('Web Search'));
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
