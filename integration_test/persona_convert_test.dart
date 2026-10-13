// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: character ↔ persona conversion through real taps.
//
//   1. A library card's "Use as Persona" saves a persona with the card's
//      text ({{char}}/{{user}} swapped), birthday and a COPY of its portrait.
//   2. That persona's "Make a Character" → Manual opens the manual wizard
//      with the name and description filled in, swapped back; leaving it
//      returns to the Persona page (it was pushed, not the tab).
//   3. "Make a Character" → AI Assist opens the AI creator with the persona
//      as its seed.
//
// Run it with:
//   flutter test integration_test/persona_convert_test.dart -d linux
//
// Isolation contract: identical to app_smoke_test.dart — see its header.

import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/home/cards/cards.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';
import 'package:front_porch_ai/ui/pages/user_persona/user_persona.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kName = 'Mabel Next Door';
const _kDescription = '{{char}} lives next door to {{user}}.';
const _kPersonality = 'Nosy but kind.';

/// An editable field anywhere on screen currently holding [text].
Finder _fieldHolding(String text) => find.byWidgetPredicate(
  (w) => w is EditableText && w.controller.text == text,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a character becomes a persona and the persona starts a '
      'character, manual and AI-assisted — sandboxed', (tester) async {
    try {
      final probe = await Socket.connect(
        InternetAddress.loopbackIPv4,
        5001,
        timeout: const Duration(milliseconds: 500),
      );
      probe.destroy();
      fail(
        'Something is listening on 127.0.0.1:5001 (a real KoboldCpp?). '
        'Close it before running the E2E suite.',
      );
    } on SocketException {
      // Nothing there — safe to proceed.
    }

    final sandbox = Directory.systemTemp.createTempSync('fpai_persona_conv_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(
      replyPieces: const ['unused'],
    );
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'realism_default': false,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
    });

    // ── Boot ────────────────────────────────────────────────────────────
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
    final personas = Provider.of<UserPersonaService>(ctx, listen: false);
    final repo = Provider.of<CharacterRepository>(ctx, listen: false);
    final storage = Provider.of<StorageService>(ctx, listen: false);
    final appState = Provider.of<AppState>(ctx, listen: false);
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    final d = ChatDriver(tester, chatService, backend);

    // A real card PNG with a 3×2 portrait.
    final source = p.join(sandbox.path, 'mabel_source.png');
    await File(source).writeAsBytes(
      img.encodePng(
        img.Image(width: 3, height: 2)..clear(img.ColorRgb8(200, 120, 40)),
      ),
    );
    storage.charactersDir.createSync(recursive: true);
    final card = CharacterCard(
      name: _kName,
      description: _kDescription,
      personality: _kPersonality,
      firstMessage: 'Evening!',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        birthday: '1990-06-14',
      ),
    )..imagePath = p.join(storage.charactersDir.path, 'mabel.png');
    await V2CardService().saveCardAsPng(card, card.imagePath!, source);
    await repo.addCharacter(card);
    await repo.loadCharacters();
    appState.setIndex(0);

    // ── 1. Use as Persona from the library card's menu ───────────────────
    final defaultBefore = personas.defaultPersona.id;
    final tile = find.ancestor(
      of: find.text(_kName),
      matching: find.byType(CharacterGridCard),
    );
    await pumpUntilFound(tester, tile.hitTestable());
    await tester.tapAt(tester.getCenter(tile.first), buttons: kSecondaryButton);
    await tapWhenHittable(tester, find.text('Use as Persona'));
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('persona-convert-swap')),
    );
    await d.tapUntilTrue(
      [find.byKey(const ValueKey('persona-convert-confirm'))],
      () => personas.personas.any((x) => x.name == _kName),
      () => 'the persona copy of $_kName to be saved',
    );
    final persona = personas.personas.firstWhere((x) => x.name == _kName);
    expect(
      persona.persona,
      '{{user}} lives next door to {{char}}.\n\nPersonality: Nosy but kind.',
    );
    expect(persona.birthday, '1990-06-14');
    expect(personas.defaultPersona.id, defaultBefore);
    final avatar = persona.avatarPath;
    expect(avatar, isNotNull, reason: 'the portrait comes along');
    expect(avatar, isNot(card.imagePath));
    final copied = img.decodePng(await File(avatar!).readAsBytes())!;
    expect([copied.width, copied.height], [3, 2]);
    expect(
      repo.characters.firstWhere((c) => c.name == _kName).description,
      _kDescription,
      reason: 'the character itself is not changed',
    );

    // ── 2. Make a Character → Manual ─────────────────────────────────────
    appState.setIndex(4);
    final personaCard = find.ancestor(
      of: find.text(_kName),
      matching: find.byType(PersonaGridCard),
    );
    Future<void> openMakeCharacter() async {
      await pumpUntilFound(tester, personaCard.hitTestable());
      await tapWhenHittable(
        tester,
        find.descendant(
          of: personaCard.first,
          matching: find.byIcon(Icons.more_vert),
        ),
      );
      await tapWhenHittable(tester, find.text('Make a Character'));
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('persona-to-char-manual')),
      );
    }

    await openMakeCharacter();
    await tapWhenHittable(
      tester,
      find.byKey(const ValueKey('persona-to-char-manual')),
    );
    await pumpUntilFound(tester, find.byType(CreateCharacterPage));
    final manual = tester.widget<CreateCharacterPage>(
      find.byType(CreateCharacterPage).last,
    );
    expect(manual.seed?.portraitPath, avatar);
    await d.waitForWidget(_fieldHolding(_kName));
    await tapWhenHittable(tester, find.text('Next: Personality'));
    // The persona's "Personality:" section goes back to its own field.
    await d.waitForWidget(
      _fieldHolding('{{char}} lives next door to {{user}}.'),
    );
    await d.waitForWidget(_fieldHolding(_kPersonality));
    // Pushed, so its back arrow pops back to the Persona page.
    await tapWhenHittable(
      tester,
      find.descendant(
        of: find.byType(AppBar).last,
        matching: find.byIcon(Icons.arrow_back),
      ),
    );
    await pumpUntilTrue(
      tester,
      () => find.byType(CreateCharacterPage).evaluate().length <= 1,
      describe: () => 'the seeded wizard to close',
    );
    expect(appState.selectedIndex, 4);

    // ── 3. Make a Character → AI Assist ──────────────────────────────────
    await openMakeCharacter();
    await tapWhenHittable(
      tester,
      find.byKey(const ValueKey('persona-to-char-ai')),
    );
    await pumpUntilFound(tester, find.byType(CharacterCreatorPage));
    final ai = tester.widget<CharacterCreatorPage>(
      find.byType(CharacterCreatorPage),
    );
    expect(ai.seed?.name, _kName);
    expect(ai.seed?.portraitPath, avatar);

    expect(backend.unexpectedPaths, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    await backend.close();
    try {
      sandbox.deleteSync(recursive: true);
    } on FileSystemException {
      // A straggler may still be writing; not a failure.
    }
  });
}
