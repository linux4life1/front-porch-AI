// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/image_facade.dart';

void main() {
  test('phone config keeps the edit model that was saved', () async {
    final dir = Directory.systemTemp.createTempSync('edit-model-config');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = StorageService.sandbox(dir.path);
    final facade = ImageFacade(ImageGenService(storage), storage);
    await storage.imageGenSettings.setImageGenBackend('a1111');
    await storage.imageGenSettings.setImageGenEditModel(
      'portrait-edit.safetensors',
    );

    expect(facade.config()['editModel'], 'portrait-edit.safetensors');

    await facade.updateConfig({'editModel': 'next-edit.safetensors'});
    expect(facade.config()['editModel'], 'next-edit.safetensors');
  });
}
