// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Model Settings dialog interaction net — required by the provability rule
// BEFORE model_settings_dialog.dart is split. No suite anywhere interacted
// with this dialog. Pins a landmark per future part (local panel, remote
// panel, picker) by rendering both backend modes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/model_settings_dialog.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Hardware extends FakeHardwareService {
  @override
  bool get cpuOnlyLowPerf => false;
}

class _ModelsManager extends FakeModelManager {
  @override
  get models => const [];
}

class _ModeStorage extends FakeStorageService {
  _ModeStorage(String backendType) {
    backendSettings.setBackendType(backendType);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDialog(WidgetTester tester, String backendType) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _ModeStorage(backendType);
    final llm = FakeLLMProvider(
      activeBackend: backendType == 'openRouter'
          ? BackendType.openRouter
          : BackendType.kobold,
    );
    final mm = _ModelsManager();
    final hw = _Hardware();
    final kobold = FakeKoboldService();
    addTearDown(() {
      storage.dispose();
      llm.dispose();
      mm.dispose();
      hw.dispose();
      kobold.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<ModelManager>.value(value: mm),
          ChangeNotifierProvider<HardwareService>.value(value: hw),
          ChangeNotifierProvider<KoboldService>.value(value: kobold),
        ],
        child: const MaterialApp(home: Material(child: ModelSettingsDialog())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('local backend mode renders the local panel', (tester) async {
    await pumpDialog(tester, 'local');
    expect(find.text('KoboldCpp'), findsOneWidget);
    expect(find.text('OpenRouter'), findsOneWidget);
    expect(
      find.textContaining('Model'),
      findsWidgets,
      reason: 'local panel landmark missing',
    );
  });

  testWidgets('remote backend mode renders the remote panel', (tester) async {
    await pumpDialog(tester, 'openRouter');
    expect(find.text('OpenRouter'), findsOneWidget);
    expect(find.text('Nano-GPT'), findsOneWidget);
    expect(find.text('LM Studio'), findsOneWidget);
    expect(
      find.textContaining('API'),
      findsWidgets,
      reason: 'remote panel landmark missing',
    );
  });
}
