// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/routes/expression_pack_routes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'workspace source, automatic prompt, resume and reroll use production routes',
    () async {
      // Remove Flutter's default 400 transport; this suite talks real HTTP to
      // the production Shelf routes. The model endpoint is deliberately absent.
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp(
        'expression_route_review_',
      );
      final storage = StorageService.sandbox(root.path);
      final prefs = await SharedPreferences.getInstance();
      storage.imageGenSettings.initializeBase(prefs, () {});
      await storage.imageGenSettings.setImageGenBackend('a1111');
      await storage.imageGenSettings.setImageGenModel('portrait');
      await storage.imageGenSettings.setLocalImageGenUrl('http://127.0.0.1:9');
      final db = AppDatabase.forTesting();
      final repo = CharacterRepository(db, storage);
      final image = ImageGenService(storage);
      final board = ExpressionPackBoard();
      final facade = ImageFacade(image, storage, repo, board);
      final router = Router();
      ExpressionPackRoutes(router, image: facade);
      final server = await shelf_io.serve(
        router.call,
        InternetAddress.loopbackIPv4,
        0,
      );
      Uri url(String path) => Uri.parse(
        'http://127.0.0.1:${server.port}/api/image/expression-pack$path',
      );
      Future<http.Response> post(String path, Map<String, Object?> body) =>
          http.post(
            url(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          );
      Future<void> stopped() async {
        for (var i = 0; i < 3000 && board.run!.session.isRunning; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(board.run!.session.isRunning, isFalse);
      }

      try {
        await repo.loadCharacters();
        final card = CharacterCard(
          name: 'Route review character',
          description: 'Illustrated portrait with dark hair',
        );
        await repo.addCharacter(card);
        // No card image exists: the workspace must retain the avatar fallback.
        await repo.addAvatar(
          card.dbId!,
          card.name,
          img.encodePng(img.Image(width: 64, height: 80)),
          'neutral',
        );
        var response = await http.get(url('/source?characterId=${card.dbId}'));
        expect(response.statusCode, 200);
        expect(
          jsonDecode(response.body)['image'],
          startsWith('data:image/png;base64,'),
        );
        response = await post('/write-prompt', {'characterId': card.dbId});
        expect(response.statusCode, 200);
        expect(jsonDecode(response.body)['prompt'], isNotEmpty);
        response = await post('', {
          'characterId': card.dbId,
          'workspace': true,
          'prompt': '',
        });
        expect(response.statusCode, 200);
        await stopped();
        expect(board.run!.characterId, card.dbId);
        expect(
          board.run!.session.slots.every(
            (s) => s.state == ExpressionSlotState.failed,
          ),
          isTrue,
        );
        final slot = board.run!.session.slots.first;
        board.run!.session.slots.last.state = ExpressionSlotState.pending;
        response = await post('/resume', {});
        expect(response.statusCode, 200);
        await stopped();
        response = await post('/reroll', {'emotion': slot.emotion});
        expect(response.statusCode, 200);
        await stopped();
        response = await post('/discard', {});
        expect(response.statusCode, 200);
        expect(board.run, isNull);
        response = await http.get(url(''));
        expect(response.statusCode, 404);
      } finally {
        await server.close(force: true);
        board.clear();
        board.dispose();
        image.dispose();
        repo.dispose();
        storage.dispose();
        await db.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
