// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Image Studio remote host resolution, Pro/paid labels, and search filter.

import 'package:flutter_test/flutter_test.dart';

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
    expect(filterImageModels(models, 'paid').single.id, 'flux-2-pro');
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
}
