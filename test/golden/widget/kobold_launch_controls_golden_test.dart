// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

@Tags(['golden'])
@TestOn('linux')
library;

// Pixel goldens for the KoboldCpp launch controls:
//   graphics_memory_controls — GpuLayersField in its three states
//                              (Automatic; Automatic with the one-time note
//                              for someone who had a layer count; set by
//                              the user) and the five-level cache picker.
//   model_settings_local     — ModelSettingsDialog with the local backend,
//                              where those controls live.
//
// Light + dark for each (4 PNGs).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/model_settings_dialog.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../support/fakes.dart';
import '../support/fakes_services.dart';
import '../support/fakes_storage.dart';
import '../support/golden_app.dart';

class _Hardware extends FakeHardwareService {
  @override
  bool get cpuOnlyLowPerf => false;
}

class _NoModels extends FakeModelManager {
  @override
  get models => const [];
}

class _Engine extends ChangeNotifier implements BackendManager {
  @override
  bool get isIntelMac => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('graphics memory control in its three states, and the cache '
      'picker', (tester) async {
    await expectThemedGoldens(
      tester,
      childBuilder: () => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GpuLayersField(
              manual: false,
              onManualChanged: (_) {},
              controller: TextEditingController(text: '40'),
            ),
            const Divider(height: 28),
            GpuLayersField(
              manual: false,
              onManualChanged: (_) {},
              controller: TextEditingController(text: '40'),
              retiredLayers: 40,
              onDismissRetired: () {},
            ),
            const Divider(height: 28),
            GpuLayersField(
              manual: true,
              onManualChanged: (_) {},
              controller: TextEditingController(text: '40'),
            ),
            const Divider(height: 28),
            SizedBox(
              width: 320,
              child: KvQuantPicker(value: KvQuant.q8_0, onChanged: (_) {}),
            ),
          ],
        ),
      ),
      group: 'kobold_launch',
      name: 'graphics_memory_controls',
      surface: const Size(620, 540),
      settle: false,
    );
  });

  testWidgets('ModelSettingsDialog — local backend', (tester) async {
    final storage = FakeStorageService();
    storage.backendSettings.setBackendType('local');
    final llm = FakeLLMProvider(activeBackend: BackendType.kobold);
    final models = _NoModels();
    final hardware = _Hardware();
    final kobold = FakeKoboldService();
    final engine = _Engine();
    addTearDown(() {
      for (final n in [storage, llm, models, hardware, kobold, engine]) {
        n.dispose();
      }
    });

    await expectThemedGoldens(
      tester,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<ModelManager>.value(value: models),
          ChangeNotifierProvider<HardwareService>.value(value: hardware),
          ChangeNotifierProvider<KoboldService>.value(value: kobold),
          ChangeNotifierProvider<BackendManager>.value(value: engine),
        ],
        child: const ModelSettingsDialog(),
      ),
      group: 'kobold_launch',
      name: 'model_settings_local',
      surface: const Size(560, 1150),
      settle: false,
    );
  });
}
