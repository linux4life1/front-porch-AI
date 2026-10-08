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
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/routes/character_routes.dart';
import 'package:front_porch_ai/services/web/routes/expression_pack_routes.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'production rules routes preserve ownership and require explicit edits',
    () async {
      final rig = await RulesRouteRig.open();
      try {
        var response = await http.get(rig.url('/settings'));
        expect(response.statusCode, 200);
        expect(jsonDecode(response.body)['prefix'], 'original');
        response = await rig.post('/settings', {
          'promptRules': ExpressionPromptRules(prefix: 'saved').toJson(),
        });
        expect(response.statusCode, 200);
        expect(
          rig.storage.expressionSettings.expressionPromptRules.prefix,
          'saved',
        );
        response = await rig.post('/preview', {'prompt': 'portrait'});
        expect(response.statusCode, 200);
        expect(
          jsonDecode(response.body)['previews'][0]['effective'],
          startsWith('saved'),
        );
        for (final route in ['/rules', '/resume', '/reroll']) {
          response = await rig.post(route, {
            'emotion': 'joy',
            'promptRules': ExpressionPromptRules().toJson(),
          });
          expect(response.statusCode, 404);
          expect(jsonDecode(response.body)['code'], 'no_pack');
        }
        rig.publish(PackOrigin.desktop);
        for (final route in ['/rules', '/resume', '/reroll']) {
          response = await rig.post(route, {
            'emotion': 'joy',
            'promptRules': ExpressionPromptRules(prefix: 'phone').toJson(),
          });
          expect(response.statusCode, 409);
          expect(jsonDecode(response.body)['code'], 'desktop_pack');
        }
        expect(rig.board.run!.session.promptRules.prefix, 'original');
        rig.publish(PackOrigin.phone);
        response = await rig.post('/rules', {});
        expect(response.statusCode, 400);
        expect(jsonDecode(response.body)['code'], 'bad_prompt_rules');
        expect(rig.board.run!.session.promptRules.prefix, 'original');
        response = await rig.post('/rules', {
          'promptRules': ExpressionPromptRules(prefix: 'local').toJson(),
        });
        expect(response.statusCode, 200);
        expect(
          rig.board.run!.session.effectivePromptFor(0),
          startsWith('local'),
        );
        expect(
          rig.storage.expressionSettings.expressionPromptRules.prefix,
          'saved',
        );
        response = await rig.post('/preview', {
          'activePack': true,
          'promptRules': ExpressionPromptRules(prefix: 'preview').toJson(),
        });
        expect(
          jsonDecode(response.body)['previews'][0]['effective'],
          startsWith('preview'),
        );
      } finally {
        await rig.close();
      }
    },
  );

  test(
    'web pack rules use the production API for lifecycle and iteration',
    () async {
      final rig = await RulesRouteRig.open();
      try {
        for (final mode in ['lifecycle', 'desktop', 'iteration']) {
          rig.board.clear();
          await rig.storage.expressionSettings.setExpressionPromptRules(
            ExpressionPromptRules(prefix: 'original'),
          );
          if (mode != 'lifecycle') {
            rig.publish(
              mode == 'desktop' ? PackOrigin.desktop : PackOrigin.phone,
            );
          }
          final result = await Process.run(
            'node',
            [
              'node_modules/vitest/vitest.mjs',
              'run',
              'src/components/models/studio/PackPanel.rules.live.test.tsx',
            ],
            workingDirectory: 'web_ui',
            environment: {
              'FPAI_RULES_TEST_URL': rig.base,
              'FPAI_RULES_TEST_MODE': mode,
              'NODE_OPTIONS': '--no-experimental-webstorage',
            },
          );
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout} ${result.stderr}',
          );
          if (mode == 'iteration') {
            expect(rig.generatedPrompts, hasLength(3));
            expect(
              rig.board.run!.session.slots.map((slot) => slot.state),
              everyElement(ExpressionSlotState.failed),
            );
          }
        }
      } finally {
        await rig.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: Platform.environment['FPAI_RULES_WEB_JOURNEY'] != '1'
        ? 'Set FPAI_RULES_WEB_JOURNEY=1 with web_ui dependencies installed.'
        : false,
  );
}

class RulesRouteRig {
  RulesRouteRig(
    this.directory,
    this.storage,
    this.db,
    this.repository,
    this.image,
    this.board,
    this.server,
  );
  final Directory directory;
  final StorageService storage;
  final AppDatabase db;
  final CharacterRepository repository;
  final ImageGenService image;
  final ExpressionPackBoard board;
  final HttpServer server;
  final generatedPrompts = <String>[];
  String get base => 'http://127.0.0.1:${server.port}';
  Uri url(String path) => Uri.parse('$base/api/image/expression-pack$path');
  Future<http.Response> post(String path, Map<String, Object?> body) =>
      http.post(
        url(path),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
  static Future<RulesRouteRig> open() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp(
      'real_pack_rules_routes_',
    );
    final storage = StorageService.sandbox(dir.path);
    final prefs = await SharedPreferences.getInstance();
    storage.expressionSettings.initializeBase(prefs, () {});
    storage.imageGenSettings.initializeBase(prefs, () {});
    await storage.expressionSettings.setExpressionPromptRules(
      ExpressionPromptRules(prefix: 'original'),
    );
    await storage.imageGenSettings.setImageGenBackend('a1111');
    await storage.imageGenSettings.setLocalImageGenUrl('http://127.0.0.1:9');
    final db = AppDatabase.forTesting();
    final repo = CharacterRepository(db, storage);
    await repo.loadCharacters();
    final card = CharacterCard(name: 'Rules route character');
    await repo.addCharacter(card);
    final png = img.encodePng(img.Image(width: 64, height: 80));
    for (final emotion in kCuratedExpressionSet.where(
      (value) => value != 'joy',
    )) {
      await repo.addAvatar(card.dbId!, card.name, png, emotion);
    }
    final image = ImageGenService(storage);
    final board = ExpressionPackBoard();
    final router = Router();
    ExpressionPackRoutes(
      router,
      image: ImageFacade(image, storage, repo, board),
    );
    WebCharacterRoutes(
      CharacterFacade(db, storage, null, null, repo),
      router,
      thumbnails: ThumbnailCache(storage.webThumbnailCacheDir),
    );
    final server = await shelf_io.serve(
      router.call,
      InternetAddress.loopbackIPv4,
      0,
    );
    return RulesRouteRig(dir, storage, db, repo, image, board, server);
  }

  void publish(PackOrigin origin) {
    generatedPrompts.clear();
    final session = ExpressionPackSession(
      emotions: ['joy', 'sadness'],
      basePrompt: 'portrait',
      negativePrompt: '',
      denoise: 0.7,
      editMode: false,
      promptRules: ExpressionPromptRules(prefix: 'original'),
      generate:
          ({
            required prompt,
            required negativePrompt,
            required seed,
            required denoise,
          }) async {
            generatedPrompts.add(prompt);
            return null;
          },
    );
    board.publish(
      PackRun(
        session: session,
        mode: PackMode.img2img,
        origin: origin,
        characterName: 'Rules route character',
        characterId: repository.characters.single.dbId,
      ),
    );
  }

  Future<void> close() async {
    await server.close(force: true);
    board.clear();
    image.dispose();
    repository.dispose();
    storage.dispose();
    await db.close();
    await directory.delete(recursive: true);
  }
}
