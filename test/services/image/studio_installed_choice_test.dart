// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/studio_desk_logic.dart';
import 'package:front_porch_ai/services/storage_service.dart';

void main() {
  const diffusion = ['z_image_turbo_bf16.safetensors'];
  const checkpoints = ['sdxl.safetensors'];
  const gguf = ['z_image_turbo_q8.gguf'];
  const loras = ['detail.safetensors'];
  const emptySlots = ['', '', '', '', '', '', '', ''];

  test('a diffusion workflow does not take a checkpoint-only file', () {
    final choice = installedDeskChoice(
      backend: 'comfyui',
      workflowId: 'z_image_turbo',
      file: 'sdxl.safetensors',
      lora: false,
      checkpoints: checkpoints,
      diffusionModels: diffusion,
      ggufUnets: gguf,
      loras: loras,
      loraSlotFiles: emptySlots,
    );
    expect(choice.accept, isFalse);

    final taken = installedDeskChoice(
      backend: 'comfyui',
      workflowId: 'z_image_turbo',
      file: 'z_image_turbo_bf16.safetensors',
      lora: false,
      checkpoints: checkpoints,
      diffusionModels: diffusion,
      ggufUnets: gguf,
      loras: loras,
      loraSlotFiles: emptySlots,
    );
    expect(taken.accept, isTrue);
    expect(taken.kind, 'comfy');
    expect(taken.token, '%MODEL_DIFFUSION%');
    expect(taken.toJson('z_image_turbo')['workflowId'], 'z_image_turbo');
  });

  test('an sd workflow takes a checkpoint and refuses a gguf', () {
    final checkpoint = installedDeskChoice(
      backend: 'comfyui',
      workflowId: 'sd',
      file: 'sdxl.safetensors',
      lora: false,
      checkpoints: checkpoints,
      diffusionModels: diffusion,
      ggufUnets: gguf,
      loras: loras,
      loraSlotFiles: emptySlots,
    );
    expect(checkpoint.accept, isTrue);
    expect(checkpoint.token, '%MODEL_CHECKPOINT%');

    final refused = installedDeskChoice(
      backend: 'comfyui',
      workflowId: 'sd',
      file: 'z_image_turbo_q8.gguf',
      lora: false,
      checkpoints: checkpoints,
      diffusionModels: diffusion,
      ggufUnets: gguf,
      loras: loras,
      loraSlotFiles: emptySlots,
    );
    expect(refused.accept, isFalse);
  });

  test('a LoRA is selected only when the loader list contains it', () {
    final listed = installedDeskChoice(
      backend: 'comfyui',
      workflowId: 'sd',
      file: 'detail.safetensors',
      lora: true,
      checkpoints: checkpoints,
      diffusionModels: diffusion,
      ggufUnets: gguf,
      loras: loras,
      loraSlotFiles: emptySlots,
    );
    expect(listed.accept, isTrue);
    expect(listed.kind, 'lora');
    expect(listed.slot, 0);

    final missing = installedDeskChoice(
      backend: 'comfyui',
      workflowId: 'sd',
      file: 'other.safetensors',
      lora: true,
      checkpoints: checkpoints,
      diffusionModels: diffusion,
      ggufUnets: gguf,
      loras: loras,
      loraSlotFiles: emptySlots,
    );
    expect(missing.accept, isFalse);
  });

  test('Automatic1111 selects a model and not an unlisted LoRA', () {
    final model = installedDeskChoice(
      backend: 'a1111',
      workflowId: '',
      file: 'portrait.safetensors',
      lora: false,
      checkpoints: const [],
      diffusionModels: const [],
      ggufUnets: const [],
      loras: const [],
      loraSlotFiles: emptySlots,
    );
    expect(model.accept, isTrue);
    expect(model.kind, 'slot');

    final lora = installedDeskChoice(
      backend: 'a1111',
      workflowId: '',
      file: 'portrait.safetensors',
      lora: true,
      checkpoints: const [],
      diffusionModels: const [],
      ggufUnets: const [],
      loras: const [],
      loraSlotFiles: emptySlots,
    );
    expect(lora.accept, isFalse);
  });

  test(
    'a LoRA fills the first empty slot and leaves the model alone',
    () async {
      final dir = Directory.systemTemp.createTempSync('installed-lora');
      addTearDown(() => dir.deleteSync(recursive: true));
      final settings = StorageService.sandbox(dir.path).imageGenSettings;
      await settings.setImageGenBackend('comfyui');
      await settings.setImageGenModel('z_image_turbo_bf16.safetensors');
      await settings.setComfyCreateModelChoice(
        'z_image_turbo',
        '%MODEL_DIFFUSION%',
        'z_image_turbo_bf16.safetensors',
      );
      await settings.setImageGenLoraSlot(0, file: 'kept.safetensors');

      final choice = installedDeskChoice(
        backend: 'comfyui',
        workflowId: 'z_image_turbo',
        file: 'detail.safetensors',
        lora: true,
        checkpoints: checkpoints,
        diffusionModels: diffusion,
        ggufUnets: gguf,
        loras: const ['detail.safetensors', 'kept.safetensors'],
        loraSlotFiles: [
          for (final slot in settings.imageGenLoraSlots) slot.file,
        ],
      );
      expect(choice.slot, 1);
      await applyInstalledDeskChoice(
        settings: settings,
        choice: choice,
        workflowId: 'z_image_turbo',
        file: 'detail.safetensors',
        edit: false,
      );

      expect(settings.imageGenModel, 'z_image_turbo_bf16.safetensors');
      expect(
        settings.comfyCreateModelChoices['z_image_turbo/%MODEL_DIFFUSION%'],
        'z_image_turbo_bf16.safetensors',
      );
      expect(settings.imageGenLoraSlots[0].file, 'kept.safetensors');
      expect(settings.imageGenLoraSlots[1].file, 'detail.safetensors');
    },
  );

  test('a full LoRA board is not selected', () {
    final choice = installedDeskChoice(
      backend: 'comfyui',
      workflowId: 'sd',
      file: 'detail.safetensors',
      lora: true,
      checkpoints: checkpoints,
      diffusionModels: diffusion,
      ggufUnets: gguf,
      loras: loras,
      loraSlotFiles: List.filled(8, 'busy.safetensors'),
    );
    expect(choice.accept, isFalse);
    expect(choice.kind, 'lora-full');
  });
}
