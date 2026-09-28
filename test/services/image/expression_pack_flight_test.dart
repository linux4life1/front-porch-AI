// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/expression_pack_service.dart';
import 'package:front_porch_ai/services/image/expression_pack_flight.dart';
import 'package:front_porch_ai/services/image/expression_pack_route.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/middleware/auth_middleware.dart';

class _CountingImageGen extends ImageGenService {
  _CountingImageGen(super.storage);

  int generateCalls = 0;

  @override
  Future<Uint8List?> generateImage({
    required String prompt,
    String? negativePrompt,
    String? size,
    Uint8List? referenceImage,
    String? model,
    bool isPortrait = false,
    int? seed,
    double? denoise,
    StudioIntent intent = StudioIntent.create,
    double? editStrength,
  }) async {
    generateCalls++;
    return Uint8List.fromList(const [1, 2, 3]);
  }
}

void main() {
  late Directory dir;

  setUp(() {
    expressionPackBoard.clear();
    dir = Directory.systemTemp.createTempSync('fp-pack-flight');
  });

  tearDown(() {
    expressionPackBoard.clear();
    dir.deleteSync(recursive: true);
  });

  test(
    'a pack calls the driver once and not generateImage per emotion',
    () async {
      final storage = StorageService.sandbox(dir.path);
      final imageGen = _CountingImageGen(storage);
      final flight = await beginExpressionPack(
        imageGen: imageGen,
        settings: storage.imageGenSettings,
        emotions: const ['joy', 'anger'],
        basePrompt: 'portrait',
        negativePrompt: '',
        denoise: 0.7,
        size: '512x768',
        baseImage: Uint8List.fromList(const [1]),
        accountId: kStudioWebAccountId,
      );
      final session = flight.session;
      expect(session, isNotNull);
      expect(flight.busy, isFalse);
      final names = await flight.done;
      expect(imageGen.generateCalls, 0);
      expect(names, isEmpty);
      expect(session!.slots, hasLength(2));
      expect(
        session.slots.every((slot) => slot.state == ExpressionSlotState.failed),
        isTrue,
      );
      expect(session.slots.first.error, contains('No image model selected'));
      expect(imageGen.isGenerating, isFalse);
      final view = expressionPackBoard.read(kStudioWebAccountId);
      expect(view, isNotNull);
      expect(view!['filenames'], isEmpty);
      expect(view['running'], isFalse);
      expect(jsonEncode(view).contains('bytes'), isFalse);
      expect(expressionPackBoard.read('other-account'), isNull);
    },
  );

  test(
    'a second pack does not start while the first driver is running',
    () async {
      final storage = StorageService.sandbox(dir.path);
      final imageGen = _CountingImageGen(storage);
      final hold = Completer<List<String>>();
      final first = imageGen.startExpressionPack(['joy'], (_) => hold.future);
      final flight = await beginExpressionPack(
        imageGen: imageGen,
        settings: storage.imageGenSettings,
        emotions: const ['anger', 'fear'],
        basePrompt: 'portrait',
        negativePrompt: '',
        denoise: 0.7,
        size: '512x768',
        baseImage: Uint8List.fromList(const [1]),
        accountId: kStudioWebAccountId,
      );
      expect(flight.session, isNull);
      expect(flight.busy, isTrue);
      expect(await flight.done, isNull);
      expect(imageGen.generateCalls, 0);
      expect(imageGen.isGenerating, isTrue);
      expect(expressionPackBoard.read(kStudioWebAccountId), isNull);
      hold.complete(const ['joy.png']);
      expect(await first, ['joy.png']);
    },
  );

  test(
    'pack status is filenames and verdicts, and another account is 404',
    () async {
      final slot = ExpressionSlot('joy');
      slot.state = ExpressionSlotState.done;
      slot.bytes = Uint8List.fromList(const [9, 9, 9]);
      var cancelled = false;
      expressionPackBoard.publish(
        accountId: kStudioWebAccountId,
        running: true,
        slots: [slot],
        onCancel: () => cancelled = true,
      );
      final router = Router();
      registerExpressionPackRoutes(router);

      final same = await router.call(_request('GET', kStudioWebAccountId));
      expect(same.statusCode, 200);
      final body =
          jsonDecode(await same.readAsString()) as Map<String, dynamic>;
      expect(body['filenames'], ['joy.png']);
      expect(body.containsKey('bytes'), isFalse);
      expect(jsonEncode(body).contains('[9,9,9]'), isFalse);
      expect(body['verdicts'], isEmpty);

      slot.qc = const PackQcVerdict(
        samePerson: true,
        expressionMatches: false,
        note: 'flat',
      );
      final afterQc = await router.call(_request('GET', kStudioWebAccountId));
      final after =
          jsonDecode(await afterQc.readAsString()) as Map<String, dynamic>;
      final verdicts = after['verdicts'] as List<dynamic>;
      expect(verdicts.single['emotion'], 'joy');
      expect(verdicts.single['samePerson'], isTrue);
      expect(verdicts.single['expressionMatches'], isFalse);
      expect(verdicts.single['note'], 'flat');
      expect(jsonEncode(after).contains('[9,9,9]'), isFalse);

      final other = await router.call(_request('GET', 'other-account'));
      expect(other.statusCode, 404);

      final refused = await router.call(
        _request('POST', 'other-account', cancel: true),
      );
      expect(refused.statusCode, 404);
      expect(cancelled, isFalse);

      final stopped = await router.call(
        _request('POST', kStudioWebAccountId, cancel: true),
      );
      expect(stopped.statusCode, 200);
      expect(cancelled, isTrue);
    },
  );
}

shelf.Request _request(String method, String account, {bool cancel = false}) {
  return shelf.Request(
    method,
    Uri.parse(
      cancel
          ? 'http://localhost/api/image/expression-pack/cancel'
          : 'http://localhost/api/image/expression-pack',
    ),
    context: {kAuthUserIdContextKey: account},
  );
}
