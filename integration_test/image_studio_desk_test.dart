// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One journey: open Image Studio, switch Create and Edit, open Change model,
// and confirm Generate stays off while a required file is empty.
// Run alone: flutter test integration_test/image_studio_desk_test.dart -d macos

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/image_studio/studio_model_sheet.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

InkWell _tab(String subtitle, WidgetTester tester) {
  return tester.widget<InkWell>(
    find
        .ancestor(of: find.text(subtitle), matching: find.byType(InkWell))
        .first,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Studio switches Create and Edit, opens Change model, and keeps Generate off',
    (tester) async {
      try {
        final probe = await Socket.connect(
          InternetAddress.loopbackIPv4,
          5001,
          timeout: const Duration(milliseconds: 500),
        );
        probe.destroy();
        fail('Something is listening on 127.0.0.1:5001 — close it first.');
      } on SocketException {
        // Nothing there.
      }

      final sandbox = Directory.systemTemp.createTempSync('fpai_studio_desk_');
      PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
      final backend = await FakeBackendServer.start(
        replyPieces: const ['Studio desk.'],
      );
      addTearDown(backend.close);
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'import_llmerta_porch_memories': false,
        'backend_type': 'openRouter',
        'remote_api_url': '${backend.baseUrl}/v1',
        'remote_model_name': 'smoke-model',
      });

      app.main(const []);
      await pumpUntilFound(tester, find.byType(MainLayout));
      try {
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setSize(const Size(1200, 800));
        await windowManager.setAlignment(Alignment.bottomRight);
        await windowManager.blur();
      } catch (e) {
        debugPrint('[e2e] window_manager placement skipped: $e');
      }
      await tester.pump(const Duration(seconds: 2));

      final ctx = tester.element(find.byType(MainLayout));
      final character = CharacterCard(
        name: 'Desk',
        description: 'A character used only to open Image Studio.',
        firstMessage: 'The studio desk is ready.',
      );
      await Provider.of<CharacterRepository>(
        ctx,
        listen: false,
      ).addCharacter(character);
      final chatService = Provider.of<ChatService>(ctx, listen: false);
      await chatService.setActiveCharacter(character);
      // ignore: use_build_context_synchronously — ctx stays the MainLayout.
      Navigator.of(
        ctx,
      ).push(MaterialPageRoute(builder: (_) => const ChatPage()));
      await pumpUntilFound(tester, find.byTooltip('Image Studio'));
      await tester.tap(find.byTooltip('Image Studio'));
      await pumpUntilFound(tester, find.text('Generate Image'));

      // Remote with no edit model does not build "Apply change". The tab's
      // own tap handler is the switch: the active tab does not accept a tap.
      expect(_tab('change this portrait', tester).onTap, isNotNull);
      await tester.tap(find.text('change this portrait'));
      await pumpUntilTrue(
        tester,
        () => _tab('change this portrait', tester).onTap == null,
        describe: () => 'Edit tab did not become the active Studio tab',
      );
      await tester.tap(find.text('make a new portrait'));
      await pumpUntilTrue(
        tester,
        () => _tab('change this portrait', tester).onTap != null,
        describe: () => 'Create tab did not become the active Studio tab',
      );

      final prompt = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText?.contains('Describe what you want') ??
                false),
      );
      await tester.ensureVisible(prompt);
      await tester.enterText(prompt, 'a porch at dusk');
      await tester.pump(const Duration(milliseconds: 300));

      await tester.ensureVisible(find.text('Change model').first);
      await tester.tap(find.text('Change model').hitTestable());
      await pumpUntilFound(tester, find.byType(StudioModelSheet));
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Generate Image'),
            )
            .onPressed,
        isNull,
      );
    },
  );
}
