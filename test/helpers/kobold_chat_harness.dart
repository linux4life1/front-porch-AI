// A real ChatService over a real KoboldService on the engine stand-in: what
// the app does for a send, a Stop or a regenerate shows in the order of the
// engine's own requests.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import 'chat_db_teardown.dart';
import 'fake_kobold_engine.dart';
import 'kobold_engine_harness.dart';

class KoboldChatHarness {
  KoboldChatHarness._(this.base, this.db, this.chat);

  final KoboldEngineHarness base;
  final AppDatabase db;
  final ChatService chat;

  FakeKoboldEngine get engine => base.engine;
  KoboldService get kobold => base.kobold;

  /// The chat is open on one character with Realism and Needs off, so a send
  /// is a reply and the passes after it, and the keeper is on for up to
  /// three chats.
  static Future<KoboldChatHarness> start({String name = 'Ada'}) async {
    final base = await KoboldEngineHarness.start();
    base.kobold.debugKeeperPlan = () async => const KoboldKeeperPlan.keep(3);
    final db = AppDatabase.forTesting();
    final chat =
        ChatService(
            base.kobold,
            UserPersonaService(db),
            base.storage,
            WorldRepository(base.storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, base.storage));
    final character = CharacterCard(
      name: name,
      description: 'Keeps the porch.',
      firstMessage: 'Evening.',
      imagePath: '/tmp/$name-kobold-chat.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
      ),
    );
    await CharacterRepository(db, base.storage).addCharacter(character);
    await chat.setActiveCharacter(character);
    base.engine
      ..forgetLog()
      ..live = [];
    final harness = KoboldChatHarness._(base, db, chat);
    addTearDown(harness.dispose);
    return harness;
  }

  /// Waits until the turn is over and everything the engine had queued
  /// behind it (the save of the reply, the passes) is done.
  Future<void> settle() async {
    for (
      var i = 0;
      i < 600 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await kobold.waitForIdle();
  }

  Future<void> dispose() async {
    await disposeChatThenCloseDb(chat, db);
    await base.dispose();
  }
}
