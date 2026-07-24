// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unit tests for the shared Portrait & Avatars controller (phase #12):
// source/pack gating, the CTA matrix, upload plumbing (looks vs tagged
// expressions), and the one-shot run orchestration — card-first, portrait →
// switch stage → pack (edit-first vs img2img) → QC hold-back → import.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show ChangeNotifier, Uint8List;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart'
    show AppDatabase, CharactersCompanion;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/model_capabilities.dart';
import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/expression_pack_qc.dart'
    show VisionEvalFn;
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/avatar_creation/avatar_creation_controller.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_avatar_ctl_').path;
        }
        return null;
      });
}

/// A real decodable PNG (normalizePackBase must be able to read the portrait).
Uint8List _realPng({int w = 96, int h = 120}) =>
    Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)));

/// Records every generateImage call; slot generations return marker bytes
/// ("IMG:" + the prompt) so the QC fake can tell slots apart.
class _FakeImageGen extends ChangeNotifier implements ImageGenService {
  bool configured = true;
  final List<Map<String, Object?>> calls = [];
  Uint8List? portraitResult;
  bool failPortrait = false;
  int comfyNudges = 0;

  @override
  bool get isConfigured => configured;

  @override
  String get statusMessage => 'fake status';

  @override
  Future<void> nudgeComfyFree() async {
    comfyNudges++;
  }

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
    calls.add({
      'prompt': prompt,
      'isPortrait': isPortrait,
      'intent': intent,
      'editStrength': editStrength,
      'hasReference': referenceImage != null,
      'seed': seed,
    });
    if (isPortrait) {
      if (failPortrait) return null;
      return portraitResult ?? _realPng();
    }
    // Slot generation: marker bytes carrying the emotion (prompt leads with
    // the emotion modifier; the first comma-token is unique enough per slot).
    return Uint8List.fromList(utf8.encode('IMG:$prompt'));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late CharacterCard card;
  late _FakeImageGen gen;

  Future<void> waitUntilNotLoading(CharacterRepository r) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (r.isLoading) {
      if (DateTime.now().isAfter(deadline)) fail('load did not settle');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() async {
    _setupPathProviderMock();
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    try {
      await db.customStatement(
        'CREATE TABLE IF NOT EXISTS avatar_images ('
        'id TEXT NOT NULL, '
        'character_id TEXT NOT NULL, '
        'filename TEXT NOT NULL, '
        'label TEXT, '
        'display_order INTEGER NOT NULL DEFAULT 0, '
        'created_at INTEGER NOT NULL DEFAULT 0, '
        'PRIMARY KEY (id))',
      );
    } catch (_) {}
    final charId = await db.insertCharacterReturningId(
      CharactersCompanion(
        name: const Value('Aerin'),
        description: const Value('creator step target'),
      ),
    );
    storage = StorageService();
    await storage.initialized;
    repo = CharacterRepository(db, storage);
    await Future<void>.delayed(Duration.zero);
    await waitUntilNotLoading(repo);

    // The pre-saved card, as the manual creator hands it over: PNG on disk.
    storage.charactersDir.createSync(recursive: true);
    final portraitPath =
        '${storage.charactersDir.path}${Platform.pathSeparator}Aerin_test.png';
    File(portraitPath).writeAsBytesSync(_realPng());
    card = CharacterCard(name: 'Aerin', imagePath: portraitPath);
    card.dbId = charId;

    gen = _FakeImageGen();
    await storage.imageGenSettings.setImageGenBackend('drawthings');
  });

  tearDown(() async {
    await db.close();
  });

  AvatarCreationController controller({
    bool cardSaved = true,
    Future<VisionEvalFn?> Function()? resolveFire,
    Future<VisionSupport?> Function()? peek,
  }) {
    return AvatarCreationController(
      ensureCardSaved: () async => cardSaved ? card : null,
      repository: repo,
      storage: storage,
      imageGen: gen,
      resolveVisionFire: resolveFire ?? () async => null,
      peekVisionSupport: peek ?? () async => null,
      initialPrompt: 'elf knight, silver armor',
      card: cardSaved ? card : null,
    );
  }

  group('defaults & gating', () {
    test('engine configured → generate + pack on; unconfigured → upload only',
        () {
      final c = controller();
      expect(c.source, PortraitSource.generate);
      expect(c.packEnabled, isTrue);

      gen.configured = false;
      final c2 = controller();
      expect(c2.source, PortraitSource.upload);
      expect(c2.packEnabled, isFalse);
      expect(c2.canRun, isFalse);
    });

    test('remote backend without an edit model cannot generate a pack '
        '(no img2img floor remotely)', () async {
      await storage.imageGenSettings.setImageGenBackend('remote');
      final c = controller();
      expect(c.packPossible, isFalse);
      c.setPackEnabled(true);
      expect(c.packEnabled, isFalse, reason: 'setter must respect the gate');

      // An allowlisted edit model in the EDIT slot flips it on.
      await storage.imageGenSettings.setImageGenEditModel('qwen-image-max-edit');
      expect(c.packPossible, isTrue);
    });

    test('source "none" forbids the pack (nothing to build from)', () {
      final c = controller();
      c.setSource(PortraitSource.none);
      expect(c.packPossible, isFalse);
      expect(c.packEnabled, isFalse);
      expect(c.ctaLabel, isNull);
    });

    test('CTA matrix', () {
      final c = controller();
      expect(c.ctaLabel, 'Generate 1 portrait · 8 expressions');
      c.setFullSet(true);
      expect(c.ctaLabel, 'Generate 1 portrait · 28 expressions');
      c.setFullSet(false);
      c.setPackEnabled(false);
      expect(c.ctaLabel, 'Generate 1 portrait');
      c.setSource(PortraitSource.upload);
      c.setPackEnabled(true);
      expect(c.ctaLabel, 'Generate 8 expressions');
      // Pack-only run needs an uploaded portrait first.
      expect(c.canRun, isFalse);
    });
  });

  group('QC gate (capability-gated visibility)', () {
    test('nothing known → shown, unresolved', () async {
      final c = controller();
      await c.initQcGate();
      expect(c.qcVisible, isTrue);
      expect(c.qcKnownSupported, isFalse);
    });

    test('known-unsupported → the toggle does not exist', () async {
      final c = controller(peek: () async => VisionSupport.none);
      await c.initQcGate();
      expect(c.qcVisible, isFalse);
    });

    test('known-supported → shown, default OFF, flips without resolving',
        () async {
      final c = controller(
        peek: () async =>
            const VisionSupport(true, VisionSource.apiMetadata),
      );
      await c.initQcGate();
      expect(c.qcVisible, isTrue);
      expect(c.qcEnabled, isFalse);
      await c.setQcEnabled(true);
      expect(c.qcEnabled, isTrue);
    });

    test('unknown → toggling ON resolves; failure reverts', () async {
      var resolves = 0;
      final c = controller(
        resolveFire: () async {
          resolves++;
          return null; // "no vision" — explainer shown by the UI closure
        },
      );
      await c.initQcGate();
      await c.setQcEnabled(true);
      expect(resolves, 1);
      expect(c.qcEnabled, isFalse, reason: 'failed resolve must revert');
    });
  });

  group('uploads (apply immediately via existing plumbing)', () {
    test('applyPortrait overwrites the portrait file in place', () async {
      final c = controller();
      final before = File(card.imagePath!).lengthSync();
      final newBytes = _realPng(w: 64, h: 64);
      expect(await c.applyPortrait(newBytes), isTrue);
      expect(c.portraitBytes, newBytes);
      // Same path (folders key on the basename), new content re-embedded.
      expect(File(card.imagePath!).existsSync(), isTrue);
      expect(File(card.imagePath!).lengthSync(), isNot(before));
    });

    test('extra uploads: null emotion → look, tagged → expression', () async {
      final c = controller();
      await c.addExtraUpload(_realPng(), null);
      await c.addExtraUpload(_realPng(), 'joy');
      final avatars = await repo.getAvatarImages(card.dbId!);
      expect(avatars.length, 2);
      expect(avatars.where((a) => a.label == AvatarImage.lookLabel).length, 1);
      expect(avatars.where((a) => a.label == 'joy').length, 1);
      // A tagged upload counts as existing for the pack count.
      expect(c.missingEmotions, isNot(contains('joy')));
    });

    test('nothing lands when the card cannot be saved', () async {
      final c = controller(cardSaved: false);
      expect(await c.applyPortrait(_realPng()), isFalse);
      expect(await c.addExtraUpload(_realPng(), 'joy'), isFalse);
      expect((await repo.getAvatarImages(card.dbId!)), isEmpty);
    });
  });

  group('run orchestration', () {
    test('img2img path: portrait → review gate → pack, everything imported',
        () async {
      // DT backend, EMPTY edit slot → packEditMode false → img2img.
      final c = controller();
      final stages = <AvatarRunStage>[];
      c.addListener(() {
        if (stages.isEmpty || stages.last != c.stage) stages.add(c.stage);
      });
      await c.run();

      // Pauses at the veto gate: only the portrait is generated so far.
      expect(c.stage, AvatarRunStage.portraitReview);
      expect(gen.calls.length, 1);
      expect(gen.calls.first['isPortrait'], isTrue);
      expect(c.portraitBytes, isNotNull);

      // Accept → the pack runs and everything imports.
      await c.continueFromReview();
      expect(c.stage, AvatarRunStage.done);
      expect(stages, isNot(contains(AvatarRunStage.switching)),
          reason: 'no edit model → no switching stage');
      // 1 portrait + 8 curated slots.
      expect(gen.calls.length, 9);
      for (final call in gen.calls.skip(1)) {
        expect(call['intent'], StudioIntent.create);
        expect(call['hasReference'], isTrue);
      }
      // Shared seed across every slot (Studio doctrine).
      final seeds = gen.calls.skip(1).map((c) => c['seed']).toSet();
      expect(seeds.length, 1);
      expect(c.importedCount, 8);
      final avatars = await repo.getAvatarImages(card.dbId!);
      expect(avatars.length, 8);
    });

    test('edit-first path: switching stage + edit intent + comfy-safe nudge',
        () async {
      await storage.imageGenSettings.setImageGenEditModel('flux1-kontext-dev');
      final c = controller();
      final stages = <AvatarRunStage>[];
      c.addListener(() {
        if (stages.isEmpty || stages.last != c.stage) stages.add(c.stage);
      });
      await c.run();
      expect(c.stage, AvatarRunStage.portraitReview);
      await c.continueFromReview();

      expect(stages, contains(AvatarRunStage.switching));
      expect(gen.comfyNudges, 1);
      for (final call in gen.calls.skip(1)) {
        expect(call['intent'], StudioIntent.edit);
        expect(call['editStrength'], kCreatorPackDenoise);
      }
      expect(c.importedCount, 8);
    });

    test('review gate: regenerate re-runs the portrait with the edited prompt',
        () async {
      final c = controller();
      await c.run();
      expect(c.stage, AvatarRunStage.portraitReview);
      expect(gen.calls.length, 1);

      // Veto: change the prompt and regenerate — a second portrait call, still
      // paused at the gate, no pack yet.
      c.promptController.text = 'golden armor, different face';
      expect(c.canRegeneratePortrait, isTrue);
      await c.regeneratePortrait();
      expect(c.stage, AvatarRunStage.portraitReview);
      expect(gen.calls.length, 2);
      expect(gen.calls.last['isPortrait'], isTrue);
      expect(gen.calls.last['prompt'], 'golden armor, different face');
      expect(c.importedCount, 0);
    });

    test('review gate: continue still works with an emptied prompt (not stuck)',
        () async {
      final c = controller();
      await c.run();
      expect(c.stage, AvatarRunStage.portraitReview);
      // Emptying the prompt only disables Regenerate — continue is unguarded.
      c.promptController.text = '';
      expect(c.canRegeneratePortrait, isFalse);
      await c.regeneratePortrait(); // no-op with empty prompt
      expect(gen.calls.length, 1);
      await c.continueFromReview();
      expect(c.stage, AvatarRunStage.done);
      expect(c.importedCount, 8);
    });

    test('review gate: "skip expressions" finishes with just the portrait',
        () async {
      final c = controller();
      await c.run();
      expect(c.stage, AvatarRunStage.portraitReview);
      await c.continueFromReview(withPack: false);
      expect(c.stage, AvatarRunStage.done);
      expect(c.importedCount, 0);
      expect(gen.calls.length, 1); // portrait only
      expect((await repo.getAvatarImages(card.dbId!)), isEmpty);
    });

    test('no review gate when there is no pack (portrait-only)', () async {
      final c = controller();
      c.setPackEnabled(false);
      await c.run();
      expect(c.stage, AvatarRunStage.done);
      expect(gen.calls.length, 1);
    });

    test('no review gate for a pack-only run off an uploaded portrait',
        () async {
      final c = controller();
      c.setSource(PortraitSource.upload);
      await c.applyPortrait(_realPng());
      c.setPackEnabled(true);
      await c.run();
      expect(c.stage, AvatarRunStage.done);
      expect(gen.calls.where((x) => x['isPortrait'] == true), isEmpty);
      expect(c.importedCount, 8);
    });

    test('portrait failure fails loudly and loses nothing', () async {
      gen.failPortrait = true;
      final c = controller();
      await c.run();
      expect(c.stage, AvatarRunStage.failed);
      expect(c.statusDetail, isNotEmpty);
      expect((await repo.getAvatarImages(card.dbId!)), isEmpty);
    });

    test('QC holds back flagged slots from the import', () async {
      final c = controller(
        resolveFire: () async =>
            ({required String prompt, required List<String> imagesB64}) async {
              // The slot image is the second attachment; our fake generator
              // stamped the prompt (which LEADS with the emotion modifier)
              // into it. Flag exactly the "anger" slot as a different person.
              final slotText = utf8.decode(base64Decode(imagesB64[1]));
              final isAnger = slotText.contains('furious scowl');
              return '{"same_person": ${isAnger ? 'false' : 'true'}, '
                  '"expression": "${isAnger ? 'anger' : 'neutral'}", '
                  '"flaw": "none"}';
            },
      );
      // QC replies name "neutral" for every non-anger slot, which only
      // matches the neutral target — so restrict the run to 2 emotions by
      // pre-tagging the other 6 as existing.
      for (final e in ['joy', 'sadness', 'fear', 'surprise', 'love']) {
        await c.addExtraUpload(_realPng(), e);
      }
      await c.addExtraUpload(_realPng(), 'embarrassment');
      await c.setQcEnabled(true); // resolves via the fake fire
      expect(c.qcEnabled, isTrue);

      await c.run();
      expect(c.stage, AvatarRunStage.portraitReview);
      await c.continueFromReview();
      expect(c.stage, AvatarRunStage.done);
      // Only neutral + anger were generated; anger was flagged (not the same
      // person) and held back.
      expect(c.flaggedExcluded, 1);
      expect(c.importedCount, 1);
    });

    test('cancel keeps completed images', () async {
      final c = controller();
      c.addListener(() {
        // Cancel as soon as the pack starts: slot 1 finishes, the rest stay
        // pending, and what finished is still imported.
        if (c.stage == AvatarRunStage.pack && !c.session!.isRunning) return;
        if (c.stage == AvatarRunStage.pack && c.session!.doneCount == 1) {
          c.cancel();
        }
      });
      await c.run();
      // The pack only starts once past the review gate.
      expect(c.stage, AvatarRunStage.portraitReview);
      await c.continueFromReview();
      expect(c.stage, AvatarRunStage.done);
      expect(c.importedCount, greaterThanOrEqualTo(1));
      expect(c.importedCount, lessThan(8));
      final avatars = await repo.getAvatarImages(card.dbId!);
      expect(avatars.length, c.importedCount);
    });
  });
}
