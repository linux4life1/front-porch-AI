// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/civitai_client.dart';

void main() {
  CivitaiCredentialStore memory(Map<String, String> box) {
    return CivitaiCredentialStore(
      readKey: (key) async => box[key],
      writeKey: (key, value) async => box[key] = value,
      deleteKey: (key) async => box.remove(key),
    );
  }

  test('civitai.red uses its own key when one is saved', () async {
    final box = <String, String>{};
    final store = memory(box);
    await store.save('local', 'green-key');
    await store.saveRed('local', 'red-key');
    expect(box['civitai_credential_local_red'], 'red-key');
    final relay = CivitaiRelay(store);
    final search = await relay.planSearch(
      accountId: 'local',
      query: 'Clothes',
      adult: true,
      lora: true,
      baseModel: 'SD 3.5',
    );
    expect(search.authorization, 'Bearer red-key');
    expect(search.uri!.queryParameters['baseModels'], 'SD 3.5');
    expect(search.uri!.queryParameters['query'], 'Clothes');
    expect(search.uri!.queryParameters['types'], 'LORA');
    expect(search.uri!.host, 'civitai.red');
    final green = await relay.planSearch(
      accountId: 'local',
      query: 'Clothes',
      adult: false,
      lora: true,
      baseModel: 'Qwen',
    );
    expect(green.authorization, isNull);
    expect(green.uri!.host, 'civitai.com');
    expect(green.uri!.queryParameters['baseModels'], 'Qwen');
  });
}
