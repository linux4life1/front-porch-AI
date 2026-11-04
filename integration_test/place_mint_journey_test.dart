// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 7 mint journey (design §6 row 7): a named arrival the library
// does not know raises the mint dialog in a live chat; 'Just add'
// saves it through the real save law (fresh row, model-made, lore
// entries, inherited weather); 'Add and move' makes it the setting.
// The sandbox backend scripts the clock verdict and the draft — the
// transport, the seam, the dialog and the repository are the real ones.

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
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kGreeting = 'Welcome to the minting porch.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a named arrival becomes a place by the tap, not before '
      '— sandboxed', (tester) async {
    final sandbox = Directory.systemTemp.createTempSync('fpai_mint_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);

    final backend = await FakeBackendServer.start(
      replyPieces: const [
        'The fake backend wanders into a walled garden of salt by the '
            'tideline.',
      ],
    );

    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'realism_default': true,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
      // The whole slice 6/7 feature rides this one switch (design §7):
      // mint suggestions are OFF until the author turns them on.
      'scene_suggestions_enabled': true,
      'passage_of_time_default': true,
    });

    app.main(const []);
    await pumpUntilFound(tester, find.byType(MainLayout));
    try {
      await windowManager.setSize(const Size(1200, 800));
      await windowManager.setAlignment(Alignment.bottomRight);
    } catch (_) {}
    await tester.pump(const Duration(seconds: 2));

    final ctx = tester.element(find.byType(MainLayout));
    final worldRepo = Provider.of<WorldRepository>(ctx, listen: false);
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    final d = ChatDriver(tester, chatService, backend);
    await worldRepo.ready;

    // A root world so the suggestion has relatives to be alien to:
    // the fake answers 'new' for The Salt Garden, which is NOT offered.
    final root = World(
      name: 'Bletch Saltworks',
      description: 'A harbour town that earns its salt.',
      lorebook: Lorebook(entries: []),
      climateEnabled: true,
      biomeId: 'temperate',
    );
    await worldRepo.saveWorld(root);

    // One child, so the Setting HAS relatives (the prompt condition).
    await worldRepo.saveWorld(
      World(
        name: 'Ropewalk',
        description: 'Tar and hemp.',
        lorebook: Lorebook(entries: []),
        parentWorldId: root.id,
        climateEnabled: false,
      ),
    );

    // Enter a live chat with the Ropewalk (a level-1 place: a mint
    // lands under it inside the cap).
    final ropewalk = worldRepo.worlds.firstWhere((w) => w.name == 'Ropewalk');
    final character = CharacterCard(
      name: 'Keeper',
      description: 'Keeps the minting porch in the E2E.',
      firstMessage: _kGreeting,
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    );
    await Provider.of<CharacterRepository>(
      ctx,
      listen: false,
    ).addCharacter(character);
    await chatService.setActiveCharacter(character);
    // ignore: use_build_context_synchronously — root MainLayout element.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));
    await d.waitForWidget(find.textContaining(_kGreeting, findRichText: true));
    await chatService.setChatPlaceSlots(primaryId: ropewalk.id);

    // A turn. The post-reply clock eval carries scene_place (the switch
    // is on, the setting has relatives) and the fake answers 'new' +
    // the pair — the seam must FLAG, nothing may be minted yet.
    await d.sendMessage('Tell me about this evening here.');
    await d.waitFor(
      () => chatService.pendingPlaceMint != null,
      () =>
          'the mint proposal (chats=${backend.chatRequests} '
          'evals=${backend.evalRequests} have=${chatService.pendingPlaceMint})',
      timeout: const Duration(seconds: 120),
    );
    expect(chatService.pendingPlaceMint!.name, 'The Salt Garden');
    expect(
      worldRepo.worlds.any((w) => w.name == 'The Salt Garden'),
      isFalse,
      reason: 'flagging is not minting — design §3: the tap mints',
    );

    // 'Just add': a real child row through the real save law.
    final result = await chatService.acceptMintedPlace(alsoMove: false);
    expect(result.ok, isTrue, reason: result.error);
    final minted = worldRepo.worldById(result.world!.id)!;
    expect(minted.parentWorldId, ropewalk.id);
    expect(minted.climateEnabled, isFalse);
    expect(minted.isModelMade, isTrue);
    expect(minted.lorebook.entries.length, 3);
    expect(
      chatService.chatPrimaryWorldId,
      ropewalk.id,
      reason: 'Just add does not move the scene',
    );
    expect(chatService.pendingPlaceMint, isNull);

    // A second arrival at the SAME name the library now holds: the mint
    // never re-mints it (a second row would be "The Salt Garden (2)" —
    // the duplicate bug). The arrival rides the move law instead, and
    // the answer routes through the same accept path as the dialog's
    // Move button: the existing place becomes the setting and Ropewalk
    // demotes to the top of Lore.
    chatService.flagSuggestedPlaceMint(
      'The Salt Garden',
      'again, from the narration',
    );
    expect(
      chatService.pendingPlaceMint,
      isNull,
      reason: 'an existing name must never raise the mint dialog',
    );
    expect(
      chatService.pendingPlaceMove?.id,
      minted.id,
      reason: 'the arrival becomes a move to the place that exists',
    );
    await chatService.acceptPlaceMove();
    expect(chatService.chatPrimaryWorldId, minted.id);
    final slots = await worldRepo.getChatWorldAttachments(
      chatService.currentSessionId!,
    );
    expect(slots.loreIds.first, ropewalk.id);
    expect(
      worldRepo.worlds.where((w) => w.name == 'The Salt Garden').length,
      1,
      reason: 'arriving twice writes exactly one place',
    );

    // Ignore: the dialog must stop coming for that name this chat.
    chatService.flagSuggestedPlaceMint('Tide Gate', 'an arch');
    chatService.ignoreMintedPlace();
    expect(chatService.pendingPlaceMint, isNull);

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
