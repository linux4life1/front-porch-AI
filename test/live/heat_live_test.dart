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

// Heat against a real model (#770, docs/design/heat-meter.md). The whole
// chat runs live: the reply, the judges that read `contact`, and the climax
// check. Nothing here is scripted.
//
//   FPAI_LIVE_API_URL=http://127.0.0.1:8000/v1 \
//   FPAI_LIVE_MODEL=<model id> \
//   flutter test --tags live test/live/heat_live_test.dart
//
// Skips when the two variables are not set. Prints a per-turn table so a
// run reads as measurements, not only a pass.

@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../helpers/chat_db_teardown.dart';

/// flutter_test stubs HttpClient to 400; this restores the real client.
class _RealHttpOverrides extends HttpOverrides {}

String? _env(String key) {
  final v = Platform.environment[key]?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

final Directory _root = Directory.systemTemp.createTempSync('fpai_heat_live_');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall call) async =>
            call.method == 'getApplicationDocumentsDirectory'
            ? _root.path
            : null,
      );
  final apiUrl = _env('FPAI_LIVE_API_URL');
  final model = _env('FPAI_LIVE_MODEL');
  final rerolls = int.tryParse(_env('FPAI_HEAT_REROLLS') ?? '') ?? 4;

  late AppDatabase db;
  late ChatService chat;
  final savedOverrides = HttpOverrides.current;

  Future<void> settle() async {
    final until = DateTime.now().add(const Duration(minutes: 8));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    while ((chat.isGenerating || chat.isSettlingTurn) &&
        DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  ({bool climax, int heat, int lust, int heatDelta, String text}) last() {
    final m = chat.messages.last;
    final meta = m.activeMetadata ?? const <String, dynamic>{};
    return (
      climax: meta['climax_triggered'] == true,
      heat: chat.nsfwService.heatLevel,
      lust: chat.nsfwService.arousalLevel,
      heatDelta: (meta['heat_delta'] as num?)?.toInt() ?? 0,
      text: m.displayText.replaceAll('\n', ' '),
    );
  }

  String row(
    String label,
    ({bool climax, int heat, int lust, int heatDelta, String text}) r,
  ) =>
      '$label | Lust ${r.lust} | Heat ${r.heat} (${r.heatDelta >= 0 ? '+' : ''}${r.heatDelta}) | '
      'climax ${r.climax ? 'YES' : 'no'} | '
      '${r.text.length > 110 ? '${r.text.substring(0, 110)}…' : r.text}';

  setUp(() async {
    HttpOverrides.global = _RealHttpOverrides();
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    final storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..setGroupChatRepository(GroupChatRepository(storage, db));
    if (apiUrl != null && model != null) {
      chat.testLlmServiceOverride = OpenRouterService(
        apiUrl: apiUrl,
        apiKey: _env('FPAI_LIVE_API_KEY') ?? '',
        modelName: model,
      );
    }
    await storage.initialized;
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Mara',
        description:
            'Mara, 29, runs the bakery on Elm Street. Warm, teasing, quick '
            'to laugh, and openly attracted to {{user}}; tonight she has '
            'been flirting with {{user}} on her porch swing for hours.',
        personality: 'Playful, affectionate, confident, sensual.',
        scenario: 'A summer night on Mara\'s porch swing after a long date.',
        firstMessage:
            '*Mara tucks her legs up on the swing and grins.* "You know, '
            'you\'re trouble. I like trouble."',
        frontPorchExtensions: FrontPorchExtensions(
          afterglowEnabled: true,
          realismEnabled: true,
          intimateInto: const ['slow build-up', 'kissing'],
        ),
      )..dbId = 'char-heat-live-mara',
    );
  });

  tearDown(() async {
    HttpOverrides.global = savedOverrides;
    await disposeChatThenCloseDb(chat, db);
  });

  test(
    '#770: a flirt-built Lust and one touch do not climax; a long scene can',
    () async {
      if (apiUrl == null || model == null) {
        markTestSkipped('FPAI_LIVE_API_URL / FPAI_LIVE_MODEL not set');
        return;
      }
      final log = <String>['model: $model'];

      // Hours of flirting, no contact.
      await chat.sendMessage(
        '"Trouble, huh? You\'ve been looking at me like that all night."',
      );
      await settle();
      log.add(row('flirt', last()));
      // The rest of the evening's flirting, compressed: Lust where #770's
      // report starts. Set BEFORE the last flirt turn so that turn's stamp
      // holds it, and every reroll of the touch rewinds to it.
      chat.nsfwService.setArousalLevel(82);
      log.add('(Lust set to 82: a long flirt with no contact)');
      await chat.sendMessage(
        '"Keep smiling at me like that and I won\'t be able to think."',
      );
      await settle();
      log.add(row('flirt', last()));
      expect(
        chat.nsfwService.heatLevel,
        0,
        reason: 'talk alone builds no Heat',
      );

      // The first touch, rerolled.
      const touch =
          '*I pull her into my lap and kiss her deeply, my hand sliding up '
          'her thigh.*';
      await chat.sendMessage(touch);
      await settle();
      final firstTouch = [last()];
      log.add(row('touch #1', firstTouch.last));
      for (var i = 2; i <= rerolls; i++) {
        await chat.regenerateLastMessage();
        await settle();
        firstTouch.add(last());
        log.add(row('touch #$i', firstTouch.last));
      }

      // A sustained scene: how many turns until release, and at what Heat.
      final scene = [
        '*I keep kissing her, slowly undoing the buttons of her dress.*',
        '*My hands explore her bare skin, touching her more intimately.*',
        '*I lay her back on the swing and keep touching her, unhurried.*',
        '*I keep going, steady and attentive, following every reaction.*',
        '*I don\'t stop, pressing closer, touching her exactly how she likes.*',
        '*I keep the same rhythm, holding her as she trembles.*',
        '*I stay with her, not letting up.*',
        '*I keep going.*',
      ];
      int? climaxTurn;
      int? climaxHeat;
      for (var i = 0; i < scene.length; i++) {
        final heatBefore = chat.nsfwService.heatLevel;
        await chat.sendMessage(scene[i]);
        await settle();
        final r = last();
        log.add(row('scene ${i + 1}', r));
        if (r.climax) {
          climaxTurn = i + 1;
          climaxHeat =
              chat.messages.last.activeMetadata?['pre_climax_heat'] as int? ??
              heatBefore;
          break;
        }
      }
      log.add(
        climaxTurn == null
            ? 'no climax within ${scene.length} scene turns'
            : 'climax on scene turn $climaxTurn at Heat $climaxHeat',
      );
      // ignore: avoid_print — the run's measurements are the point.
      print('\n${log.join('\n')}\n');

      final touchClimaxes = firstTouch.where((r) => r.climax).length;
      expect(
        touchClimaxes,
        0,
        reason: '$touchClimaxes of ${firstTouch.length} first touches climaxed',
      );
      expect(
        firstTouch.every((r) => r.heat < 40),
        isTrue,
        reason: 'one touch should leave Heat well under the edge',
      );
    },
    timeout: const Timeout(Duration(minutes: 90)),
  );
}
