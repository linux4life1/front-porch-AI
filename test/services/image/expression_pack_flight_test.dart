// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// An expression pack runs the Edit graph or says why it cannot. It is never
// made with the Create graph instead. Cancelling stops the ComfyUI job, and a
// pack holds the generation lock. Talks to a real loopback ComfyUI.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/expression_pack_service.dart';
import 'package:front_porch_ai/services/image/expression_pack_board.dart';
import 'package:front_porch_ai/services/image/expression_pack_flight.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/image_prompt/expression_prompts.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import '../web/desk_graphs.dart';
import '../web/image_desk_harness.dart';

final Uint8List _base = Uint8List.fromList(
  img.encodePng(img.Image(width: 8, height: 8)),
);

class _Studio {
  _Studio(this.storage, this.image);

  final StorageService storage;
  final ImageGenService image;
}

_Studio _boot() {
  final dir = Directory.systemTemp.createTempSync('pack-flight');
  addTearDown(() => dir.deleteSync(recursive: true));
  final storage = StorageService.sandbox(dir.path);
  return _Studio(storage, ImageGenService(storage));
}

/// ComfyUI with both an Edit and a Create checkpoint installed, and uploaded
/// graphs for both.
Future<_Studio> _comfyStudio(DeskComfy comfy) async {
  final s = _boot();
  final settings = s.storage.imageGenSettings;
  await settings.setImageGenBackend('comfyui');
  await settings.setComfyUiUrl(comfy.url);
  await settings.setComfyEditWorkflowId(kComfyUploadedWorkflowId);
  await settings.setComfyEditUploadedWorkflow(jsonEncode(deskEditGraph));
  await settings.setImageGenEditModel('edit-model.safetensors');
  await settings.setComfyCreateWorkflowId(kComfyUploadedWorkflowId);
  await settings.setComfyCreateUploadedWorkflow(jsonEncode(deskCreateGraph));
  await settings.setImageGenModel('create-model.safetensors');
  return s;
}

/// The Edit graph is the one pointed at the Edit checkpoint; the Create graph
/// (which img2img also gives a photo node) is pointed at the Create one.
bool _isEditGraph(Map<String, dynamic> graph) =>
    ((graph['ckpt'] as Map)['inputs'] as Map)['ckpt_name'] ==
    'edit-model.safetensors';

Future<ExpressionPackFlight> _begin(
  _Studio s,
  PackPlan plan,
  ExpressionPackBoard board, {
  List<String> emotions = const ['joy', 'sad'],
  void Function()? onCancelled,
}) => beginExpressionPack(
  imageGen: s.image,
  plan: plan,
  emotions: emotions,
  basePrompt: 'a woman on a porch, $kExpressionFraming',
  negativePrompt: '',
  denoise: 0.7,
  size: '64x64',
  baseImage: _base,
  characterName: 'Mara',
  characterId: 'mara-1',
  board: board,
  onCancelled: onCancelled,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => HttpOverrides.global = null);

  group('what a pack will do', () {
    const both = ['edit-model.safetensors', 'create-model.safetensors'];

    test('ComfyUI with a ready Edit graph: Edit', () async {
      final comfy = await DeskComfy.start(checkpoints: both);
      final s = await _comfyStudio(comfy);
      final plan = await planExpressionPack(s.storage);
      expect(plan.canStart, isTrue, reason: plan.refusal);
      expect(plan.edit, isTrue);
    });

    test('an Edit graph that is not ready is a refusal that says why, even '
        'when the Create graph is ready', () async {
      final comfy = await DeskComfy.start(checkpoints: both);
      final s = await _comfyStudio(comfy);
      // Edit is a bundled graph whose model files were never chosen.
      await s.storage.imageGenSettings.setComfyEditWorkflowId(
        'qwen_image_edit',
      );
      final plan = await planExpressionPack(s.storage);

      expect(plan.canStart, isFalse);
      expect(plan.mode, isNull);
      expect(plan.refusal, contains('Edit graph'));
      expect(plan.refusal, contains('not ready'));
      expect(plan.refusal, contains('never made with the Create graph'));
      expect(plan.refusal, contains('TextEncodeQwenImageEditPlus'));
    });

    test('ComfyUI that cannot be reached is a refusal that says so', () async {
      final s = _boot();
      final settings = s.storage.imageGenSettings;
      await settings.setImageGenBackend('comfyui');
      await settings.setComfyUiUrl('http://127.0.0.1:1');
      final plan = await planExpressionPack(s.storage);
      expect(plan.canStart, isFalse);
      expect(plan.refusal, contains('can’t be reached at http://127.0.0.1:1'));
    });

    test('a backend with no Edit path makes the pack by img2img', () async {
      final s = _boot();
      await s.storage.imageGenSettings.setImageGenBackend('a1111');
      final plan = await planExpressionPack(s.storage);
      expect(plan.canStart, isTrue);
      expect(plan.mode, PackMode.img2img);
    });

    test('a remote API with no edit model is a refusal', () async {
      final s = _boot();
      await s.storage.imageGenSettings.setImageGenBackend('remote');
      final plan = await planExpressionPack(s.storage);
      expect(plan.canStart, isFalse);
      expect(plan.refusal, kRemotePackNeedsEditModel);
    });
  });

  group('a pack that starts', () {
    test('runs the Edit graph for every picture, never the Create graph, and '
        'shows on the board', () async {
      final comfy = await DeskComfy.start(
        checkpoints: ['edit-model.safetensors', 'create-model.safetensors'],
        finish: true,
      );
      final s = await _comfyStudio(comfy);
      final board = ExpressionPackBoard();
      final plan = await planExpressionPack(s.storage);

      final flight = await _begin(s, plan, board);
      expect(flight.session, isNotNull);
      expect(board.run!.mode, PackMode.edit);
      expect(board.run!.characterName, 'Mara');
      final names = await flight.done;

      expect(names, ['joy', 'sad']);
      expect(comfy.postedAll, hasLength(2));
      expect(comfy.postedAll.every(_isEditGraph), isTrue);
      expect(comfy.uploads, 2, reason: 'the base portrait rides each picture');
      final texts = [
        for (final g in comfy.postedAll)
          ((g['pos'] as Map)['inputs'] as Map)['text'],
      ];
      expect(texts, [
        expressionEditInstruction('joy'),
        expressionEditInstruction('sad'),
      ]);
      expect(board.view()!['done'], 2);
      expect(s.image.isGenerating, isFalse);
    });

    test('is turned away while another picture is being made', () async {
      final comfy = await DeskComfy.start(
        checkpoints: ['edit-model.safetensors', 'create-model.safetensors'],
        hang: true,
      );
      final s = await _comfyStudio(comfy);
      final pending = s.image.generateImage(prompt: 'a quiet porch');
      while (comfy.postedAll.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final board = ExpressionPackBoard();
      final flight = await _begin(s, const PackPlan.edit(), board);

      expect(flight.session, isNull);
      expect(flight.busy, isTrue);
      expect(board.run, isNull);
      await s.image.cancelJob();
      await pending.timeout(const Duration(seconds: 10));
    });

    test('cancelling stops the ComfyUI job, marks the picture to redo, and '
        'frees the lock', () async {
      final comfy = await DeskComfy.start(
        checkpoints: ['edit-model.safetensors', 'create-model.safetensors'],
        hang: true,
      );
      final s = await _comfyStudio(comfy);
      final board = ExpressionPackBoard();
      var told = 0;
      final flight = await _begin(
        s,
        const PackPlan.edit(),
        board,
        onCancelled: () => told++,
      );
      while (comfy.postedAll.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));

      flight.session!.cancel();
      final names = await flight.done.timeout(const Duration(seconds: 10));

      expect(names, isEmpty);
      expect(comfy.stops.join(), contains('interrupt'));
      expect(comfy.stops.join(), contains('"delete":["job1"]'));
      expect(told, 1);
      final slots = flight.session!.slots;
      expect(slots.first.state, ExpressionSlotState.pending);
      expect(slots.first.error, isNull);
      expect(comfy.postedAll, hasLength(1), reason: 'the next one never began');
      expect(s.image.isGenerating, isFalse);
    });

    test('cancelling after it ended does not stop a later picture', () async {
      final comfy = await DeskComfy.start(
        checkpoints: ['edit-model.safetensors', 'create-model.safetensors'],
        hang: true,
      );
      final s = await _comfyStudio(comfy);
      final flight = await _begin(
        s,
        const PackPlan.edit(),
        ExpressionPackBoard(),
      );
      while (comfy.postedAll.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      flight.session!.cancel();
      await flight.done.timeout(const Duration(seconds: 10));

      // Someone else starts a picture; the ended pack's cancel is pressed again.
      final later = s.image.generateImage(prompt: 'a quiet porch');
      while (comfy.postedAll.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final stopsBefore = comfy.stops.length;
      flight.session!.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(comfy.stops.length, stopsBefore);
      await s.image.cancelJob();
      await later.timeout(const Duration(seconds: 10));
    });
  });
}
