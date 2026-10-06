// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Support for the .porch tests (not a test file): a whole library in its own
// data folder, with a real database, repository and chat.

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/porch/porch.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

/// Answers reply calls with one plain line and evals with nothing; the line
/// only has to exist so a chat has a real turn to carry.
class _ReplyLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    yield params.systemPrompt != null ? 'The porch swing creaks.' : '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ReplyLlm';
}

/// Call once from `main()` before the tests.
void setUpPorchTestPlatform() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        return Directory.systemTemp.createTempSync('fpai_porch_pp_').path;
      });
}

/// Call from `setUp`.
void resetPorchTestPrefs() {
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues({
    'update_auto_check': false,
    'realism_default': false,
  });
}

/// A small picture with real variation (a solid fill reads as a placeholder
/// portrait to the gallery code).
Uint8List porchTestPicture(int seed) {
  final image = img.Image(width: 48, height: 72);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(
        x,
        y,
        (x * 5 + seed * 40) % 256,
        (y * 3) % 256,
        seed * 60,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// One library: its own data folder, database, repository and chat.
class PorchTestLibrary {
  PorchTestLibrary(this.root)
    : storage = StorageService.sandbox(root),
      db = AppDatabase.forTesting() {
    repo = CharacterRepository(db, storage);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = _ReplyLlm();
  }

  final String root;
  final StorageService storage;
  final AppDatabase db;
  late final CharacterRepository repo;
  late final ChatService chat;

  PorchExporter get exporter =>
      PorchExporter(repo: repo, chat: chat, storage: storage);
  PorchImporter get importer => PorchImporter(repo: repo, chat: chat);

  CharacterCard named(String name) =>
      repo.characters.firstWhere((c) => c.name == name);

  /// A card with a real portrait and a one-entry lorebook, saved the way the
  /// library keeps cards: a V2 PNG in the characters folder.
  Future<CharacterCard> seed(String name, int n) async {
    final portrait = File('$root/portrait_$n.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(porchTestPicture(n));
    final card = CharacterCard(
      name: name,
      description: '$name lives at the end of the lane.',
      firstMessage: 'The screen door bangs.',
      lorebook: Lorebook(
        entries: [
          LorebookEntry(keys: ['lane'], content: '$name knows every gate.'),
        ],
      ),
    );
    final file =
        '${storage.charactersDir.path}/'
        '${name.replaceAll(' ', '_')}_17000000000$n.png';
    await V2CardService().saveCardAsPng(card, file, portrait.path);
    card.imagePath = file;
    await repo.addCharacter(card);
    return card;
  }

  Future<void> close() => disposeChatThenCloseDb(chat, db);
}
