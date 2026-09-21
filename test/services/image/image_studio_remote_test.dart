// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Image Studio remote host resolution, Pro/paid labels, and search filter.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';

void main() {
  test('empty Studio URL falls back to chat URL without inventing a key', () {
    final keys = {
      kNanoGptApiV1: 'sk-nano-test',
      kOpenRouterApiV1: 'sk-or-test',
    };
    final account = resolveImageStudioRemoteAccount(
      imageRemoteApiUrl: '',
      chatRemoteApiUrl: kNanoGptApiV1,
      keyFor: (u) => keys[u] ?? '',
    );
    expect(account.url, kNanoGptApiV1);
    expect(account.key, 'sk-nano-test');
  });

  test('Studio URL wins over chat mouth for fetch/generate credentials', () {
    final keys = {
      kNanoGptApiV1: 'sk-nano-test',
      kOpenRouterApiV1: 'sk-or-test',
    };
    final account = resolveImageStudioRemoteAccount(
      imageRemoteApiUrl: kOpenRouterApiV1,
      chatRemoteApiUrl: kNanoGptApiV1,
      keyFor: (u) => keys[u] ?? '',
    );
    expect(account.url, kOpenRouterApiV1);
    expect(account.key, 'sk-or-test');
  });

  test('list label marks Nano Pro vs paid; OpenRouter keeps pricing', () {
    expect(
      imageModelListLabel(
        const ImageModelInfo(id: 'hidream', name: 'Hidream', isPaid: false),
      ),
      'Hidream · Pro',
    );
    expect(
      imageModelListLabel(
        const ImageModelInfo(id: 'flux-2-pro', name: 'FLUX.2 Pro'),
      ),
      'FLUX.2 Pro · paid',
    );
    expect(
      imageModelListLabel(
        const ImageModelInfo(
          id: 'or/img',
          name: 'OR Img',
          pricingInfo: r'$0.01 / $0.02',
        ),
      ),
      r'OR Img — $0.01 / $0.02',
    );
  });

  test('search filter matches name, id, and Pro/paid label', () {
    const models = [
      ImageModelInfo(id: 'hidream', name: 'Hidream', isPaid: false),
      ImageModelInfo(id: 'flux-2-pro', name: 'FLUX.2 Pro'),
      ImageModelInfo(id: 'qwen-image-3', name: 'Qwen Image 3'),
    ];
    expect(filterImageModels(models, 'qwen').single.id, 'qwen-image-3');
    expect(filterImageModels(models, 'pro').map((m) => m.id), [
      'hidream',
      'flux-2-pro',
    ]);
    expect(filterImageModels(models, 'paid').map((m) => m.id), [
      'flux-2-pro',
      'qwen-image-3',
    ]);
    expect(filterImageModels(models, 'nope'), isEmpty);
  });

  test('picker sort keeps subscription-included models first', () {
    const models = [
      ImageModelInfo(id: 'z-paid', name: 'Zebra'),
      ImageModelInfo(id: 'a-pro', name: 'Aardvark', isPaid: false),
      ImageModelInfo(id: 'm-paid', name: 'Moose'),
    ];
    final sorted = [...models]..sort(compareImageModelsForPicker);
    expect(sorted.first.id, 'a-pro');
    expect(sorted.last.id, 'z-paid');
  });

  test(
    'applyImageRemoteHost writes Studio URL only and restores last model',
    () async {
      final image = ImageGenSettings();
      final chat = BackendSettings();
      await chat.setRemoteApiUrl(kNanoGptApiV1);
      await image.setImageGenModel('hidream');

      await applyImageRemoteHost(
        image: image,
        url: kOpenRouterApiV1,
        chatRemoteApiUrl: chat.remoteApiUrl,
        editScoped: false,
      );
      expect(image.imageRemoteApiUrl, kOpenRouterApiV1);
      expect(chat.remoteApiUrl, kNanoGptApiV1);
      expect(image.remoteImageModelFor(kNanoGptApiV1), 'hidream');

      await image.setImageGenModel('or-img');
      await applyImageRemoteHost(
        image: image,
        url: kNanoGptApiV1,
        chatRemoteApiUrl: chat.remoteApiUrl,
        editScoped: false,
      );
      expect(image.imageRemoteApiUrl, kNanoGptApiV1);
      expect(image.imageGenModel, 'hidream');
      expect(image.remoteImageModelFor(kOpenRouterApiV1), 'or-img');
      expect(chat.remoteApiUrl, kNanoGptApiV1);
    },
  );

  test('looksLikeLocalImageModel catches checkpoints, not Nano API ids', () {
    expect(looksLikeLocalImageModel('qwen_image_edit_2511_i8x.ckpt'), isTrue);
    expect(
      looksLikeLocalImageModel(r'C:\ComfyUI\models\qwen.safetensors'),
      isTrue,
    );
    expect(looksLikeLocalImageModel('/home/me/models/foo.pt'), isTrue);
    expect(looksLikeLocalImageModel('qwen-image-max-edit'), isFalse);
    expect(looksLikeLocalImageModel('qwen-image-2.1/edit'), isFalse);
  });

  test(
    'pickRemoteImageModelId prefers per-host API id over a leftover ckpt',
    () {
      expect(
        pickRemoteImageModelId(
          slotModel: 'qwen_image_edit_2511_i8x.ckpt',
          hostModel: 'qwen-image-max-edit',
        ),
        'qwen-image-max-edit',
      );
      expect(
        pickRemoteImageModelId(
          slotModel: 'qwen_image_edit_2511_i8x.ckpt',
          hostModel: '',
        ),
        isNull,
      );
    },
  );

  test(
    'applyImageRemoteHost refuses to persist a Comfy ckpt and clears the slot',
    () async {
      final image = ImageGenSettings();
      await image.setImageGenEditModel('qwen_image_edit_2511_i8x.ckpt');
      await applyImageRemoteHost(
        image: image,
        url: kNanoGptApiV1,
        chatRemoteApiUrl: '',
        editScoped: true,
      );
      expect(image.imageRemoteApiUrl, kNanoGptApiV1);
      expect(image.imageGenEditModel, isEmpty);
      expect(image.remoteImageModelFor(kNanoGptApiV1, edit: true), isEmpty);
    },
  );

  test(
    'remote image HTTP ceiling is 600s and surfaces minutes, not TimeoutException',
    () {
      expect(kRemoteImageHttpTimeout, const Duration(seconds: 600));
      expect(
        formatRemoteImageTimeoutMessage(),
        'Remote image timed out after 10m — try again or a faster model',
      );
      expect(
        formatRemoteImageTimeoutMessage(const Duration(seconds: 300)),
        'Remote image timed out after 5m — try again or a faster model',
      );
      expect(
        formatRemoteImageTimeoutMessage(),
        isNot(contains('TimeoutException')),
      );
    },
  );

  test('sanitizeRemoteImageSlot restores the per-host edit id', () async {
    final image = ImageGenSettings();
    await image.setImageRemoteApiUrl(kNanoGptApiV1);
    await image.setImageGenEditModel('qwen_image_edit_2511_i8x.ckpt');
    await image.setRemoteImageModelFor(
      kNanoGptApiV1,
      'qwen-image-max-edit',
      edit: true,
    );
    final picked = await sanitizeRemoteImageSlot(
      image: image,
      hostUrl: kNanoGptApiV1,
      editScoped: true,
    );
    expect(picked, 'qwen-image-max-edit');
    expect(image.imageGenEditModel, 'qwen-image-max-edit');
  });
}
