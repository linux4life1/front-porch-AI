// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'remote Edit selection is returned as the effective Edit model',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fpai_edit_pick_',
      );
      final storage = StorageService.sandbox(directory.path);
      final image = ImageGenService(storage);
      final facade = ImageFacade(image, storage);
      try {
        await storage.imageGenSettings.setImageGenModel('create-api-model');
        await storage.imageGenSettings.setImageGenEditModel('old-edit-model');
        await facade.pickModel(edit: true, file: 'new-edit-model');
        expect(facade.config()['editModel'], 'new-edit-model');
        expect(facade.config()['model'], 'create-api-model');
      } finally {
        image.dispose();
        storage.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'the pack remote host updates the Edit slot without changing Create',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fpai_pack_host_',
      );
      final storage = StorageService.sandbox(directory.path);
      final image = ImageGenService(storage);
      final facade = ImageFacade(image, storage);
      try {
        await storage.imageGenSettings.setImageGenModel('create-api-model');
        await storage.imageGenSettings.setImageGenEditModel('edit.safetensors');
        await facade.updateConfig({
          'remoteApiUrl': 'https://example.test/v1',
          'mode': 'edit',
        });
        expect(facade.config()['model'], 'create-api-model');
        expect(facade.config()['editModel'], '');
      } finally {
        image.dispose();
        storage.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'phone settings cannot change while the production GPU lock is held',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fpai_settings_guard_',
      );
      final storage = StorageService.sandbox(directory.path);
      final image = ImageGenService(storage);
      final facade = ImageFacade(image, storage);
      await facade.updateConfig({
        'backend': 'a1111',
        'model': 'before.safetensors',
      });
      final before = facade.config();
      final release = Completer<List<String>>();
      final flight = image.startExpressionPack(['joy'], (_) => release.future);
      expect(image.isGenerating, isTrue);
      final busy = isA<DeskRefused>()
          .having((value) => value.code, 'code', 'busy')
          .having((value) => value.status, 'status', 409);
      try {
        await expectLater(facade.startPack({'workspace': true}), throwsA(busy));
        await expectLater(facade.updateConfig({'steps': 99}), throwsA(busy));
        await expectLater(
          facade.pickModel(edit: false, file: 'after.safetensors'),
          throwsA(busy),
        );
        await expectLater(
          facade.pickGraph(edit: false, id: 'sd'),
          throwsA(busy),
        );
        await expectLater(
          facade.pickSupport(
            edit: false,
            token: '%MODEL_VAE%',
            file: 'new.safetensors',
          ),
          throwsA(busy),
        );
        await expectLater(
          facade.saveGraphFile(
            bytes: utf8.encode('{"1":{"class_type":"KSampler","inputs":{}}}'),
            name: 'upload.json',
            edit: false,
            useFor: 'create',
          ),
          throwsA(busy),
        );
        final during = facade.config();
        expect(during['steps'], before['steps']);
        expect(during['model'], before['model']);
        expect(
          during['comfyCreateWorkflowId'],
          before['comfyCreateWorkflowId'],
        );
      } finally {
        release.complete([]);
        await flight;
        image.dispose();
        storage.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
}
